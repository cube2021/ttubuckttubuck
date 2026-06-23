import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class RegionCode {
  final String code;
  final String name;
  
  RegionCode({required this.code, required this.name});
  
  factory RegionCode.fromJson(Map<String, dynamic> json) {
    return RegionCode(
      code: json['code'],
      name: json['name'],
    );
  }
}

class RegionService {
  static const String baseUrl = 'https://grpc-proxy-server-mkvo6j4wsq-du.a.run.app/v1/regcodes';

  // 시/도 가져오기 (*00000000)
  static Future<List<RegionCode>> getSido() async {
    return _fetchRegCodes('*00000000');
  }

  // 시/군/구 가져오기 (시도코드 앞 2자리 + *00000)
  static Future<List<RegionCode>> getSigungu(String sidoCode) async {
    final prefix = sidoCode.substring(0, 2);
    final codes = await _fetchRegCodes('$prefix*00000');
    // 자기 자신(시도) 제외
    return codes.where((c) => c.code != sidoCode).toList();
  }

  // 읍/면/동 가져오기 (시군구코드 앞 5자리 + *)
  static Future<List<RegionCode>> getEupmyeondong(String sigunguCode) async {
    final prefix = sigunguCode.substring(0, 5);
    final codes = await _fetchRegCodes('$prefix*');
    // 자기 자신(시군구) 제외 및 이름에 시군구까지만 있는 것 제외
    return codes.where((c) => c.code != sigunguCode && c.name.split(' ').length > 2).toList();
  }

  static Future<List<RegionCode>> _fetchRegCodes(String pattern) async {
    try {
      final url = Uri.parse('$baseUrl?regcode_pattern=$pattern&is_ignore_zero=true');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['regcodes'] != null) {
          final list = (data['regcodes'] as List)
              .map((e) => RegionCode.fromJson(e))
              .toList();
          return list;
        }
      }
    } catch (e) {
      debugPrint('법정동 코드 조회 실패: $e');
    }
    return [];
  }

  // 주소를 위경도로 변환 (Nominatim 이용)
  static Future<LatLng?> geocodeAddress(String query) async {
    try {
      // Nominatim은 과도한 요청 시 차단될 수 있으므로 User-Agent를 명확히 지정
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1');
      final response = await http.get(url, headers: {
        'User-Agent': 'ttubuk_ttubuk_app'
      }).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as List;
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat'].toString());
          final lon = double.parse(data[0]['lon'].toString());
          return LatLng(lat, lon);
        }
      }
    } catch (e) {
      debugPrint('주소 지오코딩 실패: $e');
    }
    return null;
  }

  // 좌표를 주소(도/시, 시/군/구, 읍/면/동)로 변환 (Nominatim 이용)
  static Future<Map<String, String>?> reverseGeocode(LatLng location) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${location.latitude}&lon=${location.longitude}&format=json');
      final response = await http.get(url, headers: {
        'User-Agent': 'ttubuk_ttubuk_app'
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['address'] != null) {
          final addr = data['address'] as Map<String, dynamic>;
          String doName = addr['province'] ?? addr['city'] ?? '';
          String guName = addr['borough'] ?? addr['county'] ?? addr['city'] ?? '';
          String dongName = addr['suburb'] ?? addr['quarter'] ?? addr['town'] ?? addr['village'] ?? '';

          // 시/도와 시/군/구가 같은 경우 (예: 서울특별시) 처리
          if (doName == guName) {
            guName = addr['borough'] ?? '';
          }

          return {
            'do': doName,
            'gu': guName,
            'dong': dongName,
          };
        }
      }
    } catch (e) {
      debugPrint('주소 리버스 지오코딩 실패: $e');
    }
    return null;
  }
}
