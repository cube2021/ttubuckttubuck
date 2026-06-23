import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

import '../models/park.dart';
import '../models/weather_context.dart';
import 'national_park_api_service.dart';

class ParkService {
  static const List<String> _overpassServers = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  // =========================================================
  // radius (개선)
  // =========================================================
  static int _determineRadius(double distanceKm) {
    if (distanceKm < 0.5) return 1200;
    if (distanceKm < 2.0) return 1500;
    return 2000;
  }

  // =========================================================
  // route sampling
  // =========================================================
  static List<LatLng> _sampleRoute(List<LatLng> route) {
    if (route.isEmpty) return [];
    if (route.length <= 6) return route;

    final step = (route.length / 6).ceil();
    final samples = <LatLng>[];

    for (int i = 0; i < route.length; i += step) {
      samples.add(route[i]);
    }

    return samples;
  }

  // =========================================================
  // Overpass
  // =========================================================
  static Future<http.Response?> _fetchOverpass(String query) async {
    for (final server in _overpassServers) {
      try {
        final res = await http.post(
          Uri.parse(server),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'ttubuk_ttubuk_app',
            'Accept': 'application/json',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 6)); // 대기 시간 12초에서 6초로 단축하여 빠른 백업 시도

        if (res.statusCode == 200) return res;
      } catch (_) {}
    }
    return null;
  }

  // =========================================================
  // MAIN
  // =========================================================
  static Future<List<Park>> findParksNearRouteFast(
    List<LatLng> route,
    double distanceKm, {
    String? moodId,
    WeatherContext? weather,
  }) async {
    if (route.isEmpty) return [];

    final radius = _determineRadius(distanceKm);
    final samples = _sampleRoute(route);
    debugPrint('[ParkService] findParksNearRouteFast: routePoints=${route.length}, samples=${samples.length}, radius=$radius');

    final parks = <Park>[];
    final seen = <String>{};

    // =====================================================
    // National data
    // =====================================================
    final nationalLists = await Future.wait(
      samples.map((p) => NationalParkApiService.findNear(
            p,
            radiusM: radius,
            maxResults: 8,
            useRemoteApi: false,
          )),
    );

    final totalNational = nationalLists.fold<int>(0, (s, l) => s + l.length);
    debugPrint('[ParkService] National lists loaded: $totalNational records from ${nationalLists.length} samples');

    for (final list in nationalLists.expand((e) => e)) {
      final id = 'nat_${list.manageNo}';
      if (!seen.add(id)) continue;

      parks.add(Park(
        name: list.name,
        location: LatLng(list.latitude, list.longitude),
        typeLabel: '🌳 공원',
        distanceFromRoute: 0,
        rating: 4.2,
        congestion: '',
        hasToilet: list.hasToilet,
        hasBench: list.hasBench,
        hasLighting: list.hasLighting,
        hasParking: list.hasParking,
        hasExerciseEquipment: list.hasExerciseEquipment,
        area: list.areaM2,
        openDate: list.openDate ?? '',
        manageNo: list.manageNo,
        dataSource: 'national',
        routes: const [],
        moodScore: 0,
        sortDistance: 0,
      ));
    }

    // =====================================================
    // OSM PARK + POLYGON (BBOX 최적화로 속도 대폭 개선)
    // =====================================================
    double minLat = samples.map((p) => p.latitude).reduce(math.min);
    double maxLat = samples.map((p) => p.latitude).reduce(math.max);
    double minLng = samples.map((p) => p.longitude).reduce(math.min);
    double maxLng = samples.map((p) => p.longitude).reduce(math.max);
    
    // radiusM 반경을 위경도 마진도로 환산 (1도 ≈ 111km)
    final double latMargin = radius / 111000.0;
    final double avgLat = (minLat + maxLat) / 2;
    final double lngMargin = radius / (111000.0 * math.cos(avgLat * math.pi / 180.0));
    
    final bboxStr = '${minLat - latMargin},${minLng - lngMargin},${maxLat + latMargin},${maxLng + lngMargin}';
    final query = '[out:json][timeout:8];(\n'
        '  way["leisure"="park"]($bboxStr);\n'
        '  relation["leisure"="park"]($bboxStr);\n'
        '  way["landuse"~"recreation_ground|grass|forest"]($bboxStr);\n'
        ');\n'
        'out center;';

    final res = await _fetchOverpass(query);
    if (res == null) {
      debugPrint('[ParkService] Overpass returned null (all servers failed)');
    } else {
      debugPrint('[ParkService] Overpass HTTP ${res.statusCode} bodyLength=${res.body.length}');
      final data = json.decode(res.body);
      final elements = data['elements'] as List? ?? [];
      debugPrint('[ParkService] Overpass elements found: ${elements.length}');

      for (final el in elements) {
        final id = '${el['type']}_${el['id']}';
        if (!seen.add(id)) continue;

        final tags = el['tags'] as Map? ?? {};
        final rawName = tags['name'] ?? tags['ref'] ?? tags['operator'];
        String name = rawName != null ? rawName.toString().trim() : '';

        // 이름이 비어있거나, 성의 없는 분류명(공원, 녹지, 운동기구, 장소 등)일 경우 지도와 리스트에서 제외
        if (name.isEmpty ||
            name == '공원' ||
            name == '녹지' ||
            name == '운동기구' ||
            name == '산책로' ||
            name == '장소' ||
            name == '운동시설' ||
            name == '체육시설' ||
            name == '쉼터') {
          continue;
        }

        String typeLabel;
        if (tags['leisure'] == 'park') {
          typeLabel = '🌳 공원';
        } else if (tags.containsKey('landuse')) {
          typeLabel = '🌱 녹지';
        } else if (tags.containsKey('highway') || tags.containsKey('foot')) {
          typeLabel = '🚶 산책로';
        } else {
          typeLabel = '📍 장소';
        }

        double? lat;
        double? lng;

        if (el['center'] != null) {
          lat = (el['center']['lat'] as num?)?.toDouble();
          lng = (el['center']['lon'] as num?)?.toDouble();
        } else if (el['lat'] != null) {
          lat = (el['lat'] as num?)?.toDouble();
          lng = (el['lon'] as num?)?.toDouble();
        } else if (el['geometry'] != null && el['geometry'] is List) {
          try {
            final geom = (el['geometry'] as List).cast<Map>();
            if (geom.isNotEmpty) {
              double sumLat = 0;
              double sumLon = 0;
              int cnt = 0;
              for (final g in geom) {
                final gLat = (g['lat'] as num?)?.toDouble();
                final gLon = (g['lon'] as num?)?.toDouble();
                if (gLat != null && gLon != null) {
                  sumLat += gLat;
                  sumLon += gLon;
                  cnt++;
                }
              }
              if (cnt > 0) {
                lat = sumLat / cnt;
                lng = sumLon / cnt;
              }
            }
          } catch (_) {}
        }

        if (lat == null || lng == null) continue;

        final bool hasToilet = tags['toilet'] == 'yes' || tags['amenity'] == 'toilets' || tags['facility:toilet'] == 'yes' || tags['toilets'] == 'yes';
        final bool hasBench = tags['bench'] != 'no';
        final bool hasLighting = true; // 대부분 공원엔 조명이 있으므로 항상 true 반환
        final bool hasParking = tags['parking'] == 'yes' || tags['amenity'] == 'parking' || tags['parking_space'] != null;
        final bool hasExercise = tags['leisure'] == 'fitness_station' || tags['sport'] != null || tags['exercise'] == 'yes' || tags['outdoor_seating'] == 'yes';

        parks.add(Park(
          name: name,
          location: LatLng(lat, lng),
          typeLabel: typeLabel,
          distanceFromRoute: 0,
          rating: 4.0,
          congestion: '',
          hasToilet: hasToilet,
          hasBench: hasBench,
          hasLighting: hasLighting,
          hasParking: hasParking,
          hasExerciseEquipment: hasExercise,
          area: 10000,
          openDate: '',
          manageNo: null,
          dataSource: 'osm',
          routes: const [],
          moodScore: 0,
          sortDistance: 0,
        ));
      }
      final osmCount = parks.where((p) => p.dataSource == 'osm').length;
      debugPrint('[ParkService] parks added from overpass: $osmCount');
    }

    // 이름 기준 중복 제거 및 병합 (동일한 이름을 가진 공원 정비)
    final uniqueParks = <String, Park>{};
    for (final p in parks) {
      final existing = uniqueParks[p.name];
      if (existing == null) {
        uniqueParks[p.name] = p;
      } else {
        // 이미 동일 이름의 공원이 존재할 경우 신뢰도 높은 데이터를 선택 병합
        if (p.dataSource == 'national' && existing.dataSource != 'national') {
          uniqueParks[p.name] = p; // 국가 표준 데이터 우선
        } else if (p.area > existing.area) {
          uniqueParks[p.name] = p; // 더 넓은 면적 데이터 우선
        }
      }
    }
    final mergedParks = uniqueParks.values.toList();

    // 정밀 GIS 데이터셋을 통한 화장실/주차장 정보 보정 (공원 위치 기준 반경 300m 매핑)
    try {
      await NationalParkApiService.enrichParkFacilities(mergedParks, radiusM: 300);
    } catch (e) {
      debugPrint('[ParkService] GIS 데이터 보정 중 오류 발생: $e');
    }

    // 각 공원의 루트 대비 거리 계산 후 거리순 정렬
    final center = route.isNotEmpty ? route[route.length ~/ 2] : const LatLng(37.5665, 126.9780);
    for (final p in mergedParks) {
      final dlat = p.location.latitude - center.latitude;
      final dlng = p.location.longitude - center.longitude;
      p.distanceFromRoute = math.sqrt(dlat * dlat + dlng * dlng) * 111000;
      p.sortDistance = p.distanceFromRoute;

      // 날씨가 나쁠 때 시설(조명·벤치)이 잘 갖춰진 공원을 우선
      if (weather != null && (weather.isRainy || weather.isPoorAir)) {
        if (p.hasLighting) p.sortDistance -= 80;
        if (p.hasBench) p.sortDistance -= 40;
      }
    }
    mergedParks.sort((a, b) => a.sortDistance.compareTo(b.sortDistance));
    return mergedParks.take(15).toList();
  }
}