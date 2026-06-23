import 'package:latlong2/latlong.dart';
import 'park_route.dart';

class Park {
  final String name;
  final LatLng location;
  final String typeLabel;
  double distanceFromRoute; // 실제 최단 거리 (m)

  // AI 모델 구성도 상의 풍부한 데이터 필드
  final double rating;       // 평점 (예: 4.5)
  final String congestion;   // 혼잡도 ('여유로움', '보통', '혼잡')
  final bool hasToilet;      // 화장실 유무
  final bool hasBench;       // 벤치 유무
  final bool hasLighting;    // 조명 유무
  final bool hasParking;     // 주차장 유무
  final bool hasExerciseEquipment; // 운동기구 유무
  final double area;         // 공원 면적 (m²)
  final String openDate;     // 개원일 (예: '2005-06-18')
  final String? manageNo;    // 전국도시공원 표준 관리번호
  final String dataSource;   // 'osm' | 'national'
  final List<ParkRoute> routes; // 내부 경로 목록
  double moodScore;          // 무드 점수 (가중치 계산용)
  double sortDistance;       // 정렬용 가중치 반영 거리 (m)
  double recommendationScore; // 추천 엔진 최종 스코어 (낮을수록 우선)
  double vectorSimilarity;   // 사용자 컨텍스트와의 벡터 유사도 (0~1)
  List<String> enrichedTags; // 특성 공학 태그

  Park({
    required this.name,
    required this.location,
    required this.typeLabel,
    required this.distanceFromRoute,
    required this.rating,
    required this.congestion,
    required this.hasToilet,
    required this.hasBench,
    required this.hasLighting,
    required this.hasParking,
    required this.hasExerciseEquipment,
    required this.area,
    required this.openDate,
    this.manageNo,
    this.dataSource = 'osm',
    required this.routes,
    this.moodScore = 0.0,
    required this.sortDistance,
    this.recommendationScore = 0.0,
    this.vectorSimilarity = 0.0,
    this.enrichedTags = const [],
  });

  Park copyWith({
    String? name,
    LatLng? location,
    String? typeLabel,
    double? distanceFromRoute,
    double? rating,
    String? congestion,
    bool? hasToilet,
    bool? hasBench,
    bool? hasLighting,
    bool? hasParking,
    bool? hasExerciseEquipment,
    double? area,
    String? openDate,
    String? manageNo,
    String? dataSource,
    List<ParkRoute>? routes,
    double? moodScore,
    double? sortDistance,
    double? recommendationScore,
    double? vectorSimilarity,
    List<String>? enrichedTags,
  }) {
    return Park(
      name: name ?? this.name,
      location: location ?? this.location,
      typeLabel: typeLabel ?? this.typeLabel,
      distanceFromRoute: distanceFromRoute ?? this.distanceFromRoute,
      rating: rating ?? this.rating,
      congestion: congestion ?? this.congestion,
      hasToilet: hasToilet ?? this.hasToilet,
      hasBench: hasBench ?? this.hasBench,
      hasLighting: hasLighting ?? this.hasLighting,
      hasParking: hasParking ?? this.hasParking,
      hasExerciseEquipment: hasExerciseEquipment ?? this.hasExerciseEquipment,
      area: area ?? this.area,
      openDate: openDate ?? this.openDate,
      manageNo: manageNo ?? this.manageNo,
      dataSource: dataSource ?? this.dataSource,
      routes: routes ?? this.routes,
      moodScore: moodScore ?? this.moodScore,
      sortDistance: sortDistance ?? this.sortDistance,
      recommendationScore: recommendationScore ?? this.recommendationScore,
      vectorSimilarity: vectorSimilarity ?? this.vectorSimilarity,
      enrichedTags: enrichedTags ?? this.enrichedTags,
    );
  }
}

