import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/park.dart';
import '../models/park_route.dart';

/// 공원 내부 실제 OSM 산책로를 Overpass API로 탐색하여 ParkRoute 목록을 반환합니다.
class ParkRouteService {
  // 여러 Overpass 서버를 순서대로 시도
  static const List<String> _overpassServers = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  // =========================================================
  // 공개 API
  // =========================================================

  /// [park]의 위치를 기반으로 공원 내 실제 OSM 산책로를 탐색합니다.
  /// 데이터가 없으면 수학적 원형 fallback 루트를 반환합니다.
  static Future<List<ParkRoute>> getRoutesForParkAsync(Park park) async {
    final center = park.location;

    // 공원 면적에 따라 탐색 반경 결정 (200m ~ 800m)
    int radiusM = 350;
    if (park.area > 0) {
      radiusM = math.sqrt(park.area / math.pi).round().clamp(200, 800);
    }

    try {
      final segments = await _fetchFootwaySegments(center, radiusM);

      if (segments.isEmpty) {
        debugPrint('🚶 [${park.name}] Overpass 산책로 없음 → fallback');
        return [_makeFallbackRoute(center, park.name, radiusM / 1000.0)];
      }

      debugPrint('🚶 [${park.name}] 세그먼트 ${segments.length}개 수신');

      final routes = _buildRoutes(segments, center, park.name);

      if (routes.isEmpty) {
        return [_makeFallbackRoute(center, park.name, radiusM / 1000.0)];
      }

      return routes;
    } catch (e) {
      debugPrint('🚶 [${park.name}] 산책로 탐색 오류: $e');
      return [_makeFallbackRoute(center, park.name, radiusM / 1000.0)];
    }
  }

  // =========================================================
  // Overpass 쿼리 – out geom 으로 좌표 직접 수신
  // =========================================================

  /// Overpass API로 공원 주변 footway/path/pedestrian way를 가져옵니다.
  /// `out geom;` 옵션을 사용해 별도의 노드 쿼리 없이 좌표를 한 번에 받습니다.
  static Future<List<List<LatLng>>> _fetchFootwaySegments(
    LatLng center,
    int radiusM,
  ) async {
    final lat = center.latitude;
    final lng = center.longitude;

    // highway=footway|path|pedestrian|steps 를 모두 포함
    final query = '''
[out:json][timeout:25];
(
  way["highway"~"^(footway|path|pedestrian|steps)\$"](around:$radiusM,$lat,$lng);
);
out geom;
''';

    for (final server in _overpassServers) {
      try {
        debugPrint('📡 Overpass 산책로 쿼리 ($server)');
        final res = await http.post(
          Uri.parse(server),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': 'TTubukApp/1.0',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 20));

        if (res.statusCode != 200) {
          debugPrint('⚠️ $server HTTP ${res.statusCode}');
          continue;
        }

        final data = json.decode(res.body) as Map<String, dynamic>;
        final elements = data['elements'] as List? ?? [];

        final segments = <List<LatLng>>[];

        for (final el in elements) {
          if (el['type'] != 'way') continue;

          // `out geom;` 결과에는 각 way에 'geometry' 배열이 포함됨
          final geometry = el['geometry'] as List?;
          if (geometry == null || geometry.length < 2) continue;

          final points = <LatLng>[];
          for (final node in geometry) {
            final nodeLat = (node['lat'] as num?)?.toDouble();
            final nodeLng = (node['lon'] as num?)?.toDouble();
            if (nodeLat != null && nodeLng != null) {
              points.add(LatLng(nodeLat, nodeLng));
            }
          }

          if (points.length >= 2) {
            segments.add(points);
          }
        }

        debugPrint('✅ 산책로 세그먼트 ${segments.length}개 파싱 완료');
        return segments;
      } catch (e) {
        debugPrint('⚠️ $server 실패: $e');
        continue;
      }
    }

    return [];
  }

  // =========================================================
  // 세그먼트 → 루트 생성
  // =========================================================

  /// 세그먼트 목록에서 걸을 수 있는 루트를 최대 2개 생성합니다.
  static List<ParkRoute> _buildRoutes(
    List<List<LatLng>> segments,
    LatLng center,
    String parkName,
  ) {
    final routes = <ParkRoute>[];

    // 1) 가장 긴 연결 체인 (메인 코스)
    final mainChain = _buildLongestChain(List.from(segments));
    if (mainChain.length >= 2) {
      final simplified = _simplify(mainChain);
      final distKm = _calcDistKm(simplified);
      if (distKm >= 0.05) {
        routes.add(ParkRoute(
          id: 'osm_main_${center.latitude.toStringAsFixed(4)}_${center.longitude.toStringAsFixed(4)}',
          name: '🌿 $parkName 실제 산책로',
          distanceKm: double.parse(distKm.toStringAsFixed(2)),
          durationMinutes: (distKm * 15).round().clamp(5, 180),
          difficulty: distKm < 1.5 ? '쉬움' : (distKm < 3.5 ? '보통' : '어려움'),
          description: '공원 내 OSM 지도에 등록된 실제 산책로를 따라 걷는 코스입니다. 표시된 경로는 실제 보행 가능한 길입니다.',
          points: simplified,
        ));
      }
    }

    // 2) 가장 긴 단일 세그먼트 (보조 코스)
    if (segments.length > 2) {
      final sorted = List<List<LatLng>>.from(segments)
        ..sort((a, b) => b.length.compareTo(a.length));

      final secondary = sorted.first;
      final distKm = _calcDistKm(secondary);

      // 메인 코스와 시작점이 50m 이상 떨어진 경우만 추가
      bool addSecondary = true;
      if (routes.isNotEmpty) {
        final sep = const Distance().as(
          LengthUnit.Meter,
          routes.first.points.first,
          secondary.first,
        );
        if (sep < 50) addSecondary = false;
      }

      if (addSecondary && distKm >= 0.05) {
        routes.add(ParkRoute(
          id: 'osm_alt_${center.latitude.toStringAsFixed(4)}_${center.longitude.toStringAsFixed(4)}',
          name: '🚶 $parkName 보조 코스',
          distanceKm: double.parse(distKm.toStringAsFixed(2)),
          durationMinutes: (distKm * 15).round().clamp(5, 120),
          difficulty: '쉬움',
          description: '공원 내 보조 산책로 코스입니다. 짧게 걷기 좋은 경로입니다.',
          points: _simplify(secondary),
        ));
      }
    }

    return routes;
  }

  // =========================================================
  // 그리디 체인 빌더
  // =========================================================

  /// 세그먼트들을 탐욕적으로 이어붙여 가장 긴 연결 경로를 만듭니다.
  /// 연결 임계값: 20m 이내의 끝점끼리 연결
  static List<LatLng> _buildLongestChain(List<List<LatLng>> segments) {
    if (segments.isEmpty) return [];

    // 세그먼트를 길이 내림차순 정렬
    segments.sort((a, b) => b.length.compareTo(a.length));

    final chain = <LatLng>[...segments.first];
    final used = <int>{0};

    const double threshold = 20.0; // 연결 임계 거리 (m)
    bool expanded = true;
    int maxIter = segments.length * 3;

    while (expanded && maxIter-- > 0) {
      expanded = false;

      for (int i = 1; i < segments.length; i++) {
        if (used.contains(i)) continue;

        final seg = segments[i];
        if (seg.isEmpty) continue;

        final chainEnd = chain.last;
        final chainStart = chain.first;

        // 체인 끝 → 세그먼트 앞
        if (_dist(chainEnd, seg.first) < threshold) {
          chain.addAll(seg.skip(1));
          used.add(i);
          expanded = true;
          break;
        }
        // 체인 끝 → 세그먼트 뒤 (역방향)
        if (_dist(chainEnd, seg.last) < threshold) {
          chain.addAll(seg.reversed.skip(1));
          used.add(i);
          expanded = true;
          break;
        }
        // 세그먼트 끝 → 체인 앞
        if (_dist(chainStart, seg.last) < threshold) {
          chain.insertAll(0, seg.take(seg.length - 1));
          used.add(i);
          expanded = true;
          break;
        }
        // 세그먼트 앞 → 체인 앞 (역방향)
        if (_dist(chainStart, seg.first) < threshold) {
          chain.insertAll(0, seg.reversed.take(seg.length - 1));
          used.add(i);
          expanded = true;
          break;
        }
      }
    }

    return chain;
  }

  // =========================================================
  // 유틸리티
  // =========================================================

  static double _dist(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  static double _calcDistKm(List<LatLng> pts) {
    double d = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      d += const Distance().as(LengthUnit.Kilometer, pts[i], pts[i + 1]);
    }
    return d;
  }

  /// 너무 촘촘한 점 제거 (minDistM 미만 간격 제거)
  static List<LatLng> _simplify(List<LatLng> pts, {double minDistM = 3.0}) {
    if (pts.length < 3) return pts;
    final out = <LatLng>[pts.first];
    for (int i = 1; i < pts.length - 1; i++) {
      if (_dist(out.last, pts[i]) >= minDistM) out.add(pts[i]);
    }
    out.add(pts.last);
    return out;
  }

  // =========================================================
  // Fallback 원형 루트
  // =========================================================

  /// OSM 데이터가 없을 때 공원 중심을 기반으로 원형 루트를 생성합니다.
  static ParkRoute _makeFallbackRoute(
    LatLng center,
    String parkName,
    double radiusKm,
  ) {
    final r = radiusKm.clamp(0.05, 0.4);
    final latScale = r / 111.0;
    final lngScale = r / (111.0 * math.cos(center.latitude * math.pi / 180.0));

    final pts = List.generate(13, (i) {
      final angle = (i * 30) * math.pi / 180.0;
      return LatLng(
        center.latitude + latScale * math.sin(angle),
        center.longitude + lngScale * math.cos(angle),
      );
    });

    final distKm = r * 2 * math.pi;

    return ParkRoute(
      id: 'fallback_${center.latitude}_${center.longitude}',
      name: '🌳 $parkName 둘레 산책로',
      distanceKm: double.parse(distKm.toStringAsFixed(1)),
      durationMinutes: (distKm * 15).round().clamp(5, 120),
      difficulty: '쉬움',
      description: '공원 주변을 순환하는 기본 산책 코스입니다. (OSM 산책로 데이터 미제공 공원)',
      points: pts,
    );
  }
}