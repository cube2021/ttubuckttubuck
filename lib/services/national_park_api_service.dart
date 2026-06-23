import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/national_park_api_query.dart';
import '../models/national_park_record.dart';
import '../models/park.dart';
import 'config.dart';

/// 전국도시공원정보표준데이터 Open API
/// 문서: https://www.data.go.kr/data/15012890/standard.do#tab_layer_open
class NationalParkApiService {
  /// 문서: https://api.data.go.kr/... — 실제 응답은 http 엔드포인트에서 확인됨
    static const apiBase =
      'https://api.data.go.kr/openapi/tn_pubr_public_cty_park_info_api';

  static List<NationalParkRecord>? _metroCache;
  static Future<List<NationalParkRecord>>? _loadingCacheFuture;
  static final Map<String, NationalParkRecord?> _nameLookupCache = {};
  static final Map<String, List<NationalParkRecord>> _bboxCache = {};

  static Future<List<NationalParkRecord>> loadMetroCache() async {
    if (_metroCache != null) return _metroCache!;
    if (_loadingCacheFuture != null) return _loadingCacheFuture!;

    _loadingCacheFuture = () async {
      try {
        final raw =
            await rootBundle.loadString('assets/data/national_parks_metro.json');
        final list = json.decode(raw) as List;
        _metroCache = list
            .map((e) => NationalParkRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        debugPrint('로컬 공원 캐시 로드 성공: ${_metroCache!.length}건');
      } catch (e) {
        debugPrint('로컬 공원 캐시 로드 실패: $e');
        _metroCache = [];
      }
      return _metroCache!;
    }();

    final result = await _loadingCacheFuture!;
    _loadingCacheFuture = null; // 완료 후 초기화
    return result;
  }

  static Future<List<NationalParkRecord>> findNear(
    LatLng center, {
    int radiusM = 800,
    int maxResults = 30,
    bool useRemoteApi = true,
  }) async {
    final distance = const Distance();
    final nearby = <NationalParkRecord>[];
    final seen = <String>{};

    void add(NationalParkRecord p) {
      final id = p.manageNo.isNotEmpty ? p.manageNo : p.name;
      if (id.isEmpty || seen.contains(id)) return;
      if (p.latitude == 0 || p.longitude == 0) return;
      final d = distance.as(
        LengthUnit.Meter,
        center,
        LatLng(p.latitude, p.longitude),
      );
      if (d <= radiusM) {
        seen.add(id);
        nearby.add(p);
      }
    }

    for (final p in await loadMetroCache()) {
      add(p);
    }

    if (AppConfig.hasPublicDataApiKey && useRemoteApi) {
      final bbox = _boundingBoxForCenter(center, radiusM);
      final cacheKey = _bboxCacheKey(bbox);
      var regional = _bboxCache[cacheKey];
      regional ??= await _fetchParksInBoundingBox(bbox);
      _bboxCache[cacheKey] = regional;

      debugPrint(
        '🌳 표준데이터 API bbox ${regional.length}건 → 반경 ${radiusM}m 필터',
      );
      for (final p in regional) {
        add(p);
      }
    }

    nearby.sort((a, b) {
      final da =
          distance.as(LengthUnit.Meter, center, LatLng(a.latitude, a.longitude));
      final db =
          distance.as(LengthUnit.Meter, center, LatLng(b.latitude, b.longitude));
      return da.compareTo(db);
    });

    return nearby.take(maxResults).toList();
  }

  static Future<NationalParkRecord?> matchByName(
    String osmName,
    LatLng near, {
    bool useRemoteApi = true,
  }) async {
    final cacheKey = '${osmName}_${near.latitude.toStringAsFixed(3)}';
    if (_nameLookupCache.containsKey(cacheKey)) {
      return _nameLookupCache[cacheKey];
    }

    NationalParkRecord? best;

    for (final p in await loadMetroCache()) {
      if (_namesMatch(osmName, p.name)) {
        best = p;
        break;
      }
    }

    if (best == null && AppConfig.hasPublicDataApiKey && useRemoteApi) {
      final bbox = _boundingBoxForCenter(near, 2000);
      final cacheKey = _bboxCacheKey(bbox);
      var regional = _bboxCache[cacheKey];
      regional ??= await _fetchParksInBoundingBox(bbox);
      _bboxCache[cacheKey] = regional;

      for (final rec in regional) {
        if (_namesMatch(osmName, rec.name)) {
          best = rec;
          debugPrint('🌳 표준데이터 이름 매칭: $osmName → ${rec.name}');
          break;
        }
      }
    } else if (best == null && !useRemoteApi) {
      debugPrint('⚠️ 이름 매칭에서 공개 API 원격 호출 생략: $osmName');
    }

    if (best == null) {
      double minD = double.infinity;
      for (final p in await loadMetroCache()) {
        final d = const Distance().as(
          LengthUnit.Meter,
          near,
          LatLng(p.latitude, p.longitude),
        );
        if (d < 400 && d < minD && _namesPartialMatch(osmName, p.name)) {
          minD = d;
          best = p;
        }
      }
    }

    _nameLookupCache[cacheKey] = best;
    return best;
  }

  /// AI 추천 시 지역명과 공원명으로 로컬 공원 캐시에서 정확한 좌표를 찾습니다.
  static Future<NationalParkRecord?> findByNameOrRegion(String regionName, String parkName) async {
    final parks = await loadMetroCache();
    
    final regionTokens = regionName.split(' ').where((e) => e.isNotEmpty).toList();
    bool matchRegion(NationalParkRecord p) {
      if (regionTokens.isEmpty) return true;
      for (final t in regionTokens) {
        if (p.address.contains(t) || p.institutionName?.contains(t) == true) return true;
      }
      return false;
    }

    // 1. 공원명 정확히 포함 & 지역명 매칭
    for (final p in parks) {
      if (p.name == parkName || p.name.contains(parkName) || parkName.contains(p.name)) {
        if (matchRegion(p)) return p;
      }
    }
    
    // 2. 정규화된 공원명 포함 & 지역명 매칭
    final shortParkName = _normalizeName(parkName);
    if (shortParkName.length >= 2) {
      for (final p in parks) {
        final shortPName = _normalizeName(p.name);
        if (shortPName.isNotEmpty && (shortPName.contains(shortParkName) || shortParkName.contains(shortPName))) {
          if (matchRegion(p)) return p;
        }
      }
    }
    
    // 3. 최후의 보루: 지역 상관없이 이름만 포함 (오탐률 주의)
    for (final p in parks) {
      if (p.name == parkName) return p;
    }

    return null;
  }

  /// Open API 기본 목록 조회 후 위·경도 bbox로 필터 (조회조건 필터는 400 반환 가능)
  static Future<List<NationalParkRecord>> _fetchParksInBoundingBox(
    _GeoBoundingBox bbox,
  ) async {
    final results = <NationalParkRecord>[];
    final seen = <String>{};
    var pageNo = 1;
    const pageSize = 500;
    const maxPages = 40;

    while (pageNo <= maxPages) {
      final page = await _request(NationalParkApiQuery(
        pageNo: pageNo,
        numOfRows: pageSize,
      ));

      if (!page.isSuccess) {
        debugPrint(
          '표준데이터 API page=$pageNo code=${page.resultCode} msg=${page.resultMsg}',
        );
        break;
      }
      if (page.items.isEmpty) break;

      var inBoxThisPage = 0;
      for (final raw in page.items) {
        final rec = NationalParkRecord.fromJson(raw);
        if (rec.name.isEmpty || rec.latitude == 0) continue;
        if (!bbox.contains(rec.latitude, rec.longitude)) continue;

        final id = rec.manageNo.isNotEmpty ? rec.manageNo : rec.name;
        if (seen.add(id)) {
          results.add(rec);
          inBoxThisPage++;
        }
      }

      debugPrint(
        '표준데이터 API page=$pageNo 파싱 ${page.items.length}건, bbox +$inBoxThisPage (누적 ${results.length})',
      );

      if (page.items.length < pageSize) break;
      if (page.totalCount > 0 && pageNo * pageSize >= page.totalCount) break;
      pageNo++;
    }

    return results;
  }

  static Future<NationalParkApiPage> _request(NationalParkApiQuery query) async {
    final uri = Uri.parse(
      query.toRequestUrl(apiBase, AppConfig.publicDataApiKey),
    );

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      final body = utf8.decode(res.bodyBytes);

      if (res.statusCode != 200) {
        debugPrint(
          '표준데이터 API HTTP ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}',
        );
        return NationalParkApiPage(
          items: [],
          totalCount: 0,
          resultCode: 'HTTP_${res.statusCode}',
        );
      }

      return _parsePage(body);
    } catch (e) {
      debugPrint('표준데이터 API 요청 오류: $e');
      return NationalParkApiPage(
        items: [],
        totalCount: 0,
        resultCode: 'NETWORK_ERROR',
        resultMsg: e.toString(),
      );
    }
  }

  static NationalParkApiPage _parsePage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map) {
        return const NationalParkApiPage(
          items: [],
          totalCount: 0,
          resultCode: 'PARSE_ERROR',
        );
      }

      final response = decoded['response'];
      if (response is! Map) {
        return const NationalParkApiPage(
          items: [],
          totalCount: 0,
          resultCode: 'NO_RESPONSE',
        );
      }

      final header = response['header'];
      final resultCode =
          header is Map ? (header['resultCode']?.toString() ?? '') : '';
      final resultMsg =
          header is Map ? header['resultMsg']?.toString() : null;

      if (resultCode != '00' && resultCode.isNotEmpty) {
        debugPrint('표준데이터 API resultCode=$resultCode msg=$resultMsg');
      }

      final bodyNode = response['body'];
      var totalCount = 0;
      final items = <Map<String, dynamic>>[];

      if (bodyNode is Map) {
        totalCount = int.tryParse(bodyNode['totalCount']?.toString() ?? '') ?? 0;
        final rawItems = bodyNode['items'];
        if (rawItems is List) {
          for (final e in rawItems) {
            if (e is Map) items.add(Map<String, dynamic>.from(e));
          }
        } else if (rawItems is Map) {
          final item = rawItems['item'];
          if (item is List) {
            for (final e in item) {
              if (e is Map) items.add(Map<String, dynamic>.from(e));
            }
          } else if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }

      return NationalParkApiPage(
        items: items,
        totalCount: totalCount,
        resultCode: resultCode.isEmpty ? '00' : resultCode,
        resultMsg: resultMsg,
      );
    } catch (e) {
      debugPrint('표준데이터 API JSON 파싱 실패: $e');
      return NationalParkApiPage(
        items: [],
        totalCount: 0,
        resultCode: 'PARSE_ERROR',
        resultMsg: e.toString(),
      );
    }
  }

  static _GeoBoundingBox _boundingBoxForCenter(LatLng center, int radiusM) {
    const metersPerDegLat = 111320.0;
    final latRad = center.latitude * 3.141592653589793 / 180;
    final metersPerDegLng = 111320.0 * math.cos(latRad);
    final dLat = radiusM / metersPerDegLat;
    final dLng = radiusM / metersPerDegLng;

    return _GeoBoundingBox(
      minLat: center.latitude - dLat,
      maxLat: center.latitude + dLat,
      minLng: center.longitude - dLng,
      maxLng: center.longitude + dLng,
    );
  }

  static String _bboxCacheKey(_GeoBoundingBox b) =>
      '${b.minLat.toStringAsFixed(3)}_${b.maxLat.toStringAsFixed(3)}_'
      '${b.minLng.toStringAsFixed(3)}_${b.maxLng.toStringAsFixed(3)}';

  static bool _namesMatch(String a, String b) {
    final na = _normalizeName(a);
    final nb = _normalizeName(b);
    return na.contains(nb) || nb.contains(na);
  }

  static bool _namesPartialMatch(String a, String b) {
    final na = _normalizeName(a);
    final nb = _normalizeName(b);
    if (na.length < 2 || nb.length < 2) return false;
    final shorter = na.length < nb.length ? na : nb;
    final longer = na.length < nb.length ? nb : na;
    return longer.contains(
      shorter.substring(0, shorter.length.clamp(2, shorter.length)),
    );
  }

  static String _normalizeName(String name) {
    return name
        .replaceAll('공원', '')
        .replaceAll('생태', '')
        .replaceAll(' ', '')
        .trim()
        .toLowerCase();
  }

  // =========================================================
  // 정밀 GIS 화장실 & 실시간 주차장 API 매핑 보정 기능 추가
  // =========================================================
  static const parkingApiBase =
      'https://api.data.go.kr/openapi/tn_pubr_public_prkplce_info_api';

  static List<Map<String, dynamic>>? _gisToilets;
  static Future<void>? _loadingGisFuture;
  static final Map<String, List<Map<String, dynamic>>> _parkingBboxCache = {};

  static Future<void> loadGisData() async {
    if (_gisToilets != null) return;
    if (_loadingGisFuture != null) return _loadingGisFuture!;

    _loadingGisFuture = () async {
      try {
        final toiletRaw = await rootBundle.loadString('assets/data/gis_toilets.json');
        final decoded = json.decode(toiletRaw) as List;
        _gisToilets = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        debugPrint('GIS 화장실 정밀 데이터 로드 성공: ${_gisToilets!.length}건');
      } catch (e) {
        debugPrint('GIS 화장실 정밀 데이터 로드 실패: $e');
        _gisToilets = [];
      }
    }();

    await _loadingGisFuture;
    _loadingGisFuture = null;
  }

  /// 주차장 API로부터 지정된 바운딩 박스 내부의 모든 주차장 정보를 비동기 호출
  static Future<List<Map<String, dynamic>>> _fetchParkingsInBoundingBox(
    _GeoBoundingBox bbox,
  ) async {
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};
    var pageNo = 1;
    const pageSize = 500;
    const maxPages = 20; // 과도한 트래픽 호출 방지 마진

    while (pageNo <= maxPages) {
      final query = NationalParkApiQuery(
        pageNo: pageNo,
        numOfRows: pageSize,
      );
      final uri = Uri.parse(
        query.toRequestUrl(parkingApiBase, AppConfig.publicDataApiKey),
      );

      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 15));
        final body = utf8.decode(res.bodyBytes);

        if (res.statusCode != 200) {
          debugPrint('🚗 [주차장 API] HTTP 에러 코드: ${res.statusCode}');
          break;
        }

        final page = _parsePage(body);
        if (page.items.isEmpty) break;

        var inBoxThisPage = 0;
        for (final raw in page.items) {
          final double lat = double.tryParse(raw['latitude']?.toString() ?? '') ?? 0.0;
          final double lng = double.tryParse(raw['longitude']?.toString() ?? '') ?? 0.0;
          final name = raw['prkplceNm']?.toString() ?? '';

          if (name.isEmpty || lat == 0.0 || lng == 0.0) continue;
          if (!bbox.contains(lat, lng)) continue;

          final id = raw['prkplceNo']?.toString() ?? name;
          if (seen.add(id)) {
            results.add({
              'name': name,
              'lat': lat,
              'lng': lng,
            });
            inBoxThisPage++;
          }
        }

        debugPrint(
          '🚗 [주차장 API] page=$pageNo 파싱 ${page.items.length}건, bbox +$inBoxThisPage (누적 ${results.length})',
        );

        if (page.items.length < pageSize) break;
        if (page.totalCount > 0 && pageNo * pageSize >= page.totalCount) break;
        pageNo++;
      } catch (e) {
        debugPrint('🚗 [주차장 API] 요청 예외 발생: $e');
        break;
      }
    }

    return results;
  }

  /// 공원의 위경도 기준 반경 [radiusM] 내에 정밀 GIS 화장실이나 주차장이 있는지 판단하여 보정
  static Future<void> enrichParkFacilities(List<Park> parks, {int radiusM = 300}) async {
    // 화장실 데이터 로딩
    await loadGisData();

    // 1. 공원들이 속한 전체 통합 바운딩 박스를 계산하여 주차장 실시간 API 동적 쿼리 진행
    List<Map<String, dynamic>> parkings = [];
    if (parks.isNotEmpty && AppConfig.hasPublicDataApiKey) {
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      for (final p in parks) {
        final lat = p.location.latitude;
        final lng = p.location.longitude;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }

      // 반경 radiusM 만큼 안전한 바운딩 영역 확장 마진 추가
      final double marginLat = (radiusM + 200) / 111000.0;
      final double marginLng = (radiusM + 200) / (111000.0 * 0.8);

      final bbox = _GeoBoundingBox(
        minLat: minLat - marginLat,
        maxLat: maxLat + marginLat,
        minLng: minLng - marginLng,
        maxLng: maxLng + marginLng,
      );

      final cacheKey = _bboxCacheKey(bbox);
      var cached = _parkingBboxCache[cacheKey];
      if (cached == null) {
        debugPrint('🚗 [주차장 API] 캐시 미스 → 원격 API 호출 (BBOX: $bbox)');
        cached = await _fetchParkingsInBoundingBox(bbox);
        _parkingBboxCache[cacheKey] = cached;
      } else {
        debugPrint('🚗 [주차장 API] 캐시 히트 → 메모리 로드: ${cached.length}건');
      }
      parkings = cached;
    }

    final distance = const Distance();

    for (var i = 0; i < parks.length; i++) {
      final p = parks[i];
      bool hasToilet = p.hasToilet;
      bool hasParking = p.hasParking;

      final double pLat = p.location.latitude;
      final double pLng = p.location.longitude;

      // 300m 반경에 대한 단순 경위도 오차 범위 (1도 ≈ 111km 기준 마진 설정)
      final double latMargin = radiusM / 111000.0;
      final double lngMargin = radiusM / (111000.0 * 0.8); // cos(37도) ≈ 0.8 적용

      // 1. 화장실 보정 (기존 화장실이 false인 경우 더 정밀한 GIS 데이터셋을 검사하여 보정)
      if (!hasToilet && _gisToilets != null) {
        for (final t in _gisToilets!) {
          final double tLat = (t['lat'] as num).toDouble();
          // 1차 고속 필터링 (산술 절대값 차이)
          if ((tLat - pLat).abs() > latMargin) continue;

          final double tLng = (t['lng'] as num).toDouble();
          if ((tLng - pLng).abs() > lngMargin) continue;

          // 오차 범위 안에 들 때만 정밀 구면 삼각거리 연산 수행
          final d = distance.as(
            LengthUnit.Meter,
            p.location,
            LatLng(tLat, tLng),
          );
          if (d <= radiusM) {
            hasToilet = true;
            break;
          }
        }
      }

      // 2. 주차장 보정 (기존 주차장이 false인 경우 실시간 주차장 API 데이터를 검사하여 보정)
      if (!hasParking && parkings.isNotEmpty) {
        for (final pkg in parkings) {
          final double pkgLat = (pkg['lat'] as num).toDouble();
          // 1차 고속 필터링 (산술 절대값 차이)
          if ((pkgLat - pLat).abs() > latMargin) continue;

          final double pkgLng = (pkg['lng'] as num).toDouble();
          if ((pkgLng - pLng).abs() > lngMargin) continue;

          // 오차 범위 안에 들 때만 정밀 구면 삼각거리 연산 수행
          final d = distance.as(
            LengthUnit.Meter,
            p.location,
            LatLng(pkgLat, pkgLng),
          );
          if (d <= radiusM) {
            hasParking = true;
            break;
          }
        }
      }

      // 보정된 데이터가 기존 데이터와 다른 경우 copyWith를 통해 업데이트
      if (hasToilet != p.hasToilet || hasParking != p.hasParking) {
        parks[i] = p.copyWith(
          hasToilet: hasToilet,
          hasParking: hasParking,
        );
      }
    }
  }
}

class _GeoBoundingBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const _GeoBoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  @override
  String toString() {
    return '${minLat.toStringAsFixed(3)},${minLng.toStringAsFixed(3)} to ${maxLat.toStringAsFixed(3)},${maxLng.toStringAsFixed(3)}';
  }
}
