import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../env/env.dart';

class ParkReview {
  final String id;
  final String userId;
  final String? userName;
  final String parkName;
  final int rating;
  final String? content;
  final DateTime createdAt;

  ParkReview({
    required this.id,
    required this.userId,
    this.userName,
    required this.parkName,
    required this.rating,
    this.content,
    required this.createdAt,
  });

  factory ParkReview.fromMap(Map<String, dynamic> m) {
    return ParkReview(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      userName: m['profiles'] is Map ? m['profiles']['full_name'] as String? : null,
      parkName: m['park_name'] as String,
      rating: m['rating'] as int,
      content: m['content'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}

class ParkReviewSummary {
  final double averageRating;
  final int count;
  final bool isGoogleRating;

  const ParkReviewSummary({
    this.averageRating = 0,
    this.count = 0,
    this.isGoogleRating = false,
  });
}

class ParkReviewService {
  static Future<ParkReviewSummary> getSummary(String parkName) async {
    try {
      final data = await Supabase.instance.client
          .from('park_reviews')
          .select('rating')
          .eq('park_name', parkName);

      final list = List<Map<String, dynamic>>.from(data);
      
      // 자체 평점이 5개 이상이면 자체 평점 반환
      if (list.length >= 5) {
        final sum = list.fold<int>(0, (s, r) => s + (r['rating'] as int));
        return ParkReviewSummary(
          averageRating: sum / list.length,
          count: list.length,
        );
      }

      // 평점이 5개 미만인 경우 구글 플레이스 API 호출 (키가 있는 경우)
      final googleKey = Env.googleMapsApiKey;
      if (googleKey != null && googleKey.isNotEmpty) {
        try {
          final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
          final response = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': googleKey,
              'X-Goog-FieldMask': 'places.displayName,places.rating,places.userRatingCount',
              'X-Android-Package': 'com.ttubuk.ttubuk_ttubuk',
              'X-Android-Cert': '27A4CEE4E50750CA8986925A8E406734BC1E79BD',
            },
            body: jsonEncode({
              'textQuery': parkName,
              'languageCode': 'ko',
            }),
          ).timeout(const Duration(seconds: 5));
          
          if (response.statusCode == 200) {
            final json = jsonDecode(response.body);
            final places = json['places'] as List?;
            if (places != null && places.isNotEmpty) {
              final firstResult = places.first;
              if (firstResult.containsKey('rating')) {
                final rating = (firstResult['rating'] as num).toDouble();
                final count = firstResult['userRatingCount'] as int? ?? 0;
                
                return ParkReviewSummary(
                  averageRating: rating,
                  count: count,
                  isGoogleRating: true,
                );
              }
            }
          } else {
            debugPrint('구글 맵 신형 API 오류: ${response.statusCode} - ${response.body}');
          }
        } catch (e) {
          debugPrint('구글 맵 평점 조회 실패: $e');
        }
      }

      // 구글 평점을 못 가져왔거나 키가 없으면 그냥 자체 평점(있는 만큼만) 반환
      if (list.isEmpty) return const ParkReviewSummary();
      final sum = list.fold<int>(0, (s, r) => s + (r['rating'] as int));
      return ParkReviewSummary(
        averageRating: sum / list.length,
        count: list.length,
      );

    } catch (e) {
      debugPrint('후기 요약 조회 실패: \$e');
      return const ParkReviewSummary();
    }
  }

  static Future<List<ParkReview>> getReviews(String parkName, {int limit = 20}) async {
    try {
      final data = await Supabase.instance.client
          .from('park_reviews')
          .select('*, profiles(full_name)')
          .eq('park_name', parkName)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(data)
          .map(ParkReview.fromMap)
          .toList();
    } catch (e) {
      debugPrint('후기 목록 조회 실패: $e');
      return [];
    }
  }

  static Future<void> submitReview({
    required String parkName,
    required int rating,
    String? content,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');

    await Supabase.instance.client.from('park_reviews').insert({
      'user_id': user.id,
      'park_name': parkName,
      'rating': rating.clamp(1, 5),
      'content': content?.trim().isEmpty == true ? null : content?.trim(),
    });
  }
}
