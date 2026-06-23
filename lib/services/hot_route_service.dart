import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotWalkRoute {
  final String title;
  final String displayTitle;
  final int shareCount;
  final double avgDistanceKm;
  final int avgDurationSeconds;
  final DateTime? lastSharedAt;
  final List<Map<String, dynamic>>? sampleRoute;

  HotWalkRoute({
    required this.title,
    required this.displayTitle,
    required this.shareCount,
    required this.avgDistanceKm,
    required this.avgDurationSeconds,
    this.lastSharedAt,
    this.sampleRoute,
  });
}

/// 공유 산책로 인기 순위 (기획서: 실시간 핫 코스)
class HotRouteService {
  static List<HotWalkRoute> _mockHotRoutes() {
    return [
      HotWalkRoute(
        title: '[공유] 남산 둘레길 밤공기 산책로 🌙',
        displayTitle: '남산 둘레길 밤공기 산책로 🌙',
        shareCount: 128,
        avgDistanceKm: 4.2,
        avgDurationSeconds: 3600,
        lastSharedAt: DateTime.now().subtract(const Duration(hours: 2)),
        sampleRoute: [
          {'lat': 37.5556, 'lng': 126.9882},
          {'lat': 37.5536, 'lng': 126.9902},
          {'lat': 37.5516, 'lng': 126.9892},
          {'lat': 37.5526, 'lng': 126.9852},
        ],
      ),
      HotWalkRoute(
        title: '[공유] 아차산 생태 둘레길 🌳',
        displayTitle: '아차산 생태 둘레길 🌳',
        shareCount: 96,
        avgDistanceKm: 3.5,
        avgDurationSeconds: 3200,
        lastSharedAt: DateTime.now().subtract(const Duration(hours: 5)),
        sampleRoute: [
          {'lat': 37.5532, 'lng': 127.0985},
          {'lat': 37.5550, 'lng': 127.1000},
          {'lat': 37.5565, 'lng': 127.0970},
        ],
      ),
      HotWalkRoute(
        title: '[공유] 서울숲 메타세쿼이아길 🌸',
        displayTitle: '서울숲 메타세쿼이아길 🌸',
        shareCount: 84,
        avgDistanceKm: 2.8,
        avgDurationSeconds: 2400,
        lastSharedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      HotWalkRoute(
        title: '[공유] 한강 망원 노을 산책길 🌅',
        displayTitle: '한강 망원 노을 산책길 🌅',
        shareCount: 71,
        avgDistanceKm: 5.5,
        avgDurationSeconds: 4500,
        lastSharedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
  }

  static Future<List<HotWalkRoute>> fetchHotRoutes({int limit = 15}) async {
    try {
      final data = await Supabase.instance.client
          .from('walk_records')
          .select('title, distance_km, duration_seconds, route, created_at')
          .like('title', '[공유]%')
          .order('created_at', ascending: false)
          .limit(200);

      final records = List<Map<String, dynamic>>.from(data);
      if (records.isEmpty) return _mockHotRoutes();

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final r in records) {
        final title = r['title'] as String? ?? '';
        if (!title.startsWith('[공유]')) continue;
        grouped.putIfAbsent(title, () => []).add(r);
      }

      final hot = grouped.entries.map((e) {
        final list = e.value;
        final distSum = list.fold<double>(
          0,
          (s, r) => s + ((r['distance_km'] as num?)?.toDouble() ?? 0),
        );
        final durSum = list.fold<int>(
          0,
          (s, r) => s + ((r['duration_seconds'] as int?) ?? 0),
        );
        final latest = list.first;
        return HotWalkRoute(
          title: e.key,
          displayTitle: e.key.replaceFirst('[공유] ', ''),
          shareCount: list.length,
          avgDistanceKm: distSum / list.length,
          avgDurationSeconds: (durSum / list.length).round(),
          lastSharedAt: DateTime.tryParse(latest['created_at'] as String? ?? ''),
          sampleRoute: latest['route'] is List
              ? List<Map<String, dynamic>>.from(latest['route'] as List)
              : null,
        );
      }).toList();

      hot.sort((a, b) => b.shareCount.compareTo(a.shareCount));
      return hot.take(limit).toList();
    } catch (e) {
      debugPrint('핫 코스 조회 실패, 목업 사용: $e');
      return _mockHotRoutes();
    }
  }
}
