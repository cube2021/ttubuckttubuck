import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 추천 결과에 대한 피드백을 저장하고 모델 학습 가중치에 반영합니다.
/// (구성도: Model Training 피드백 루프)
class RecommendationFeedbackService {
  static const _localKeyPrefix = 'rec_feedback_';

  static Future<Map<String, double>> loadParkBiasMap() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return {};

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_localKeyPrefix${user.id}');
    if (raw == null) return {};

    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0));
    } catch (e) {
      debugPrint('피드백 맵 파싱 실패: $e');
      return {};
    }
  }

  static Future<void> recordFeedback({
    required String parkName,
    required bool isPositive,
    String? moodId,
    String? routeName,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final delta = isPositive ? 0.15 : -0.12;
    final biasMap = await loadParkBiasMap();
    biasMap[parkName] = ((biasMap[parkName] ?? 0) + delta).clamp(-1.0, 1.0);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_localKeyPrefix${user.id}',
      json.encode(biasMap),
    );

    try {
      await Supabase.instance.client.from('recommendation_feedback').insert({
        'user_id': user.id,
        'park_name': parkName,
        'is_positive': isPositive,
        'mood_id': moodId,
        'route_name': routeName,
      });
    } catch (e) {
      debugPrint('Supabase 피드백 저장 스킵(테이블 없을 수 있음): $e');
    }
  }
}
