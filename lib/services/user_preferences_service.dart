import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_preferences.dart';

/// 사용자 성향 전체를 로드·저장하는 서비스
class UserPreferencesService {
  static Future<UserPreferences> load() async {
    final user = Supabase.instance.client.auth.currentUser;

    String? purpose;
    String? intensity;
    if (user != null) {
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('purpose, intensity')
            .eq('id', user.id)
            .maybeSingle();
        if (row != null) {
          purpose = row['purpose'] as String?;
          intensity = row['intensity'] as String?;
        }
      } catch (e) {
        debugPrint('프로필 선호 로드 실패: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final prefix = user != null ? 'pref_${user.id}_' : 'pref_guest_';

    // 확장 성향 데이터를 JSON 문자열로 저장
    final detailJson = prefs.getString('${prefix}detail');
    UserPreferences detail = UserPreferences.defaults;
    if (detailJson != null) {
      try {
        detail = UserPreferences.fromJson(json.decode(detailJson));
      } catch (e) {
        debugPrint('성향 JSON 파싱 실패: $e');
      }
    }

    return UserPreferences(
      purpose: purpose ?? detail.purpose,
      intensity: intensity ?? detail.intensity,
      prefersToilet: prefs.getBool('${prefix}toilet') ?? detail.prefersToilet,
      prefersBench: prefs.getBool('${prefix}bench') ?? detail.prefersBench,
      prefersLighting: prefs.getBool('${prefix}lighting') ?? detail.prefersLighting,
      maxWalkDistanceKm: prefs.getDouble('${prefix}max_km') ?? detail.maxWalkDistanceKm,
      staticActivities: detail.staticActivities,
      dynamicActivities: detail.dynamicActivities,
      companion: detail.companion,
      preferredFacilities: detail.preferredFacilities,
      culturalFacilities: detail.culturalFacilities,
      preferredAtmosphere: detail.preferredAtmosphere,
      naturalStyle: detail.naturalStyle,
      visitTime: detail.visitTime,
      transportType: detail.transportType,
      accessibilityNeeds: detail.accessibilityNeeds,
    );
  }

  static Future<void> saveAll(UserPreferences preferences) async {
    final user = Supabase.instance.client.auth.currentUser;
    final prefix = user != null ? 'pref_${user.id}_' : 'pref_guest_';
    final prefs = await SharedPreferences.getInstance();

    // 기본 항목은 기존 키에 저장
    await prefs.setBool('${prefix}toilet', preferences.prefersToilet);
    await prefs.setBool('${prefix}bench', preferences.prefersBench);
    await prefs.setBool('${prefix}lighting', preferences.prefersLighting);
    await prefs.setDouble('${prefix}max_km', preferences.maxWalkDistanceKm);

    // 확장 항목은 JSON으로 통합 저장
    await prefs.setString('${prefix}detail', json.encode(preferences.toJson()));

    // 성향 테스트 완료 마커 저장 (홈 화면 체크 & 프로필 표시용)
    await prefs.setString('${prefix}personality', _purposeToLabel(preferences.purpose));

    // Supabase에 기본 성향 업데이트
    if (user != null) {
      try {
        await Supabase.instance.client.from('profiles').update({
          'purpose': preferences.purpose,
          'intensity': preferences.intensity,
        }).eq('id', user.id);
      } catch (e) {
        debugPrint('Supabase 성향 업데이트 실패: $e');
      }
    }
  }

  static Future<void> saveLocalFacilities({
    required bool prefersToilet,
    required bool prefersBench,
    required bool prefersLighting,
    double? maxWalkDistanceKm,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'pref_${user.id}_';
    await prefs.setBool('${prefix}toilet', prefersToilet);
    await prefs.setBool('${prefix}bench', prefersBench);
    await prefs.setBool('${prefix}lighting', prefersLighting);
    if (maxWalkDistanceKm != null) {
      await prefs.setDouble('${prefix}max_km', maxWalkDistanceKm);
    }
  }

  /// purpose 값을 사람이 읽기 쉬운 성향 라벨로 변환
  static String _purposeToLabel(String? purpose) {
    switch (purpose) {
      case 'walking':
        return '🌿 힐링 산책형';
      case 'exercise':
        return '🏃 운동형';
      default:
        return '맞춤 산책형';
    }
  }
}

