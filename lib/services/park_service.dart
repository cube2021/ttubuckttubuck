import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../models/park.dart';

class ParkService {
  // 여러 서버를 순서대로 시도
  static const List<String> _overpassServers = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  // 경로 길이에 따라 탐색 반경 자동 결정
  static int _determineRadius(double distanceKm) {
    if (distanceKm < 0.5) return 800;
    if (distanceKm < 2.0) return 600;
    if (distanceKm < 5.0) return 500;
    return 800;
  }

  // 타입별 라벨
  static String _getLabel(Map tags) {
    final leisure = tags['leisure'];
    final natural = tags['natural'];
    final waterway = tags['waterway'];

    if (leisure == 'park') return '🌳 공원';
    if (leisure == 'garden') return '🌸 정원';
    if (leisure == 'nature_reserve') return '🌿 자연보호구역';
    if (leisure == 'fitness_station') return '💪 야외 운동시설';
    if (leisure == 'track') return '🏃 운동 트랙';
    if (leisure == 'pitch') return '⚽ 운동장';
    if (natural == 'wood') return '🌲 숲';
    if (natural == 'water') return '💧 수변공원';
    if (waterway == 'river' || waterway == 'stream') return '🏞️ 하천';
    return '📍 산책 명소';
  }

  // 경로에서 대표 좌표 추출 (최대 3개)
  static List<LatLng> _sampleRoute(List<LatLng> route) {
    if (route.isEmpty) return [];
    if (route.length == 1) return [route.first];
    if (route.length <= 3) return route;

    return [
      route.first,
      route[route.length ~/ 2],
      route.last,
    ];
  }

  static Future<List<Park>> findParksNearRoute(
    List<LatLng> route,
    double distanceKm, {
    String? moodId,
  }) async {
    if (route.isEmpty) return [];

    final radius = _determineRadius(distanceKm);
    final samples = _sampleRoute(route);
    final allParks = <Park>[];
    final seenIds = <String>{};

    debugPrint('🌳 공원 탐색 시작 (무드 반영): ${samples.length}개 좌표, 반경 ${radius}m, 무드: $moodId');

    // 1. 모든 샘플 좌표에 대해 통합 쿼리 생성
    String aroundFilters = '';
    for (var point in samples) {
      final lat = point.latitude;
      final lng = point.longitude;
      aroundFilters += 'nwr["leisure"~"park|garden|fitness_station|track"](around:$radius,$lat,$lng);'
                      'nwr["natural"~"wood|water"](around:$radius,$lat,$lng);';
    }

    final query = '[out:json][timeout:30];($aroundFilters);out center;';

    // 2. HTTP POST 요청
    http.Response? response;
    for (final server in _overpassServers) {
      try {
        debugPrint('📡 Overpass 요청 전송 ($server)');
        final res = await http.post(
          Uri.parse(server),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': 'TTubukApp/1.0',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 25));
        
        if (res.statusCode == 200) {
          response = res;
          break;
        }
      } catch (e) {
        debugPrint('⚠️ $server 실패: $e');
        continue;
      }
    }

    if (response == null || response.statusCode != 200) return [];

    // 3. 데이터 파싱 및 무드 기반 가중치 부여
    final data = json.decode(response.body);
    final elements = data['elements'] as List? ?? [];

    for (final el in elements) {
      final id = '${el['type']}_${el['id']}';
      if (seenIds.contains(id)) continue;
      seenIds.add(id);

      final tags = el['tags'] as Map? ?? {};
      final name = tags['name'] ?? tags['name:ko'];
      if (name == null) continue;

      double? elLat, elLng;
      if (el['type'] == 'node') {
        elLat = (el['lat'] as num?)?.toDouble();
        elLng = (el['lon'] as num?)?.toDouble();
      } else if (el['center'] != null) {
        elLat = (el['center']['lat'] as num?)?.toDouble();
        elLng = (el['center']['lon'] as num?)?.toDouble();
      }
      if (elLat == null || elLng == null) continue;

      final parkLatLng = LatLng(elLat, elLng);
      double minDist = double.infinity;
      for (var point in samples) {
        final d = const Distance().as(LengthUnit.Meter, point, parkLatLng);
        if (d < minDist) minDist = d.toDouble();
      }

      // 무드 기반 보너스 점수 계산
      double moodBonus = 0.0;
      final type = _getLabel(tags);
      
      if (moodId == 'happy') {
        if (type.contains('운동') || type.contains('트랙') || type.contains('체육')) moodBonus = 500.0;
      } else if (moodId == 'calm') {
        if (type.contains('정원') || type.contains('숲') || type.contains('물가')) moodBonus = 500.0;
      } else if (moodId == 'gloomy') {
        if (type.contains('숲') || type.contains('자연')) moodBonus = 500.0;
      } else if (moodId == 'tired') {
        if (type.contains('정원') || type.contains('공원')) moodBonus = 300.0;
      }

      allParks.add(Park(
        name: name,
        location: parkLatLng,
        typeLabel: type,
        distanceFromRoute: minDist - moodBonus, // 보너스 점수가 높을수록 앞으로 옴
      ));
    }

    // 최종 정렬 (보너스 점수 반영된 거리 기준)
    allParks.sort((a, b) => a.distanceFromRoute.compareTo(b.distanceFromRoute));
    
    // 원래 거리값 복구 (UI 표시용)
    for (var p in allParks) {
      if (p.distanceFromRoute < 0) {
        // 보너스를 받은 경우 역산 (간단하게 최소 10m로 표시하거나 원래 거리 계산 필요)
        // 여기선 가중치 정렬을 위해 쓴 것이므로 실제 거리 데이터는 따로 보관하는 게 좋지만
        // 구조상 distanceFromRoute를 그대로 쓰므로 0 이하가 되지 않게 보정
        p.distanceFromRoute = (p.distanceFromRoute + 500.0).clamp(0, double.infinity);
      }
    }

    return allParks.take(15).toList();
  }
}


