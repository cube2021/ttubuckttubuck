/// 사용자의 공원·산책 성향 전체 데이터 모델
class UserPreferences {
  // ─── 기존 항목 ─────────────────────────────────────────────────────────────
  final String? purpose;   // walking | exercise
  final String? intensity; // low | medium | high
  final bool prefersToilet;
  final bool prefersBench;
  final bool prefersLighting;
  final double maxWalkDistanceKm;

  // ─── 방문 목적 (정적) ────────────────────────────────────────────────────────
  final List<String> staticActivities;
  // 예: ['rest', 'picnic', 'reading', 'watergazing', 'meditation', 'sunbathing']

  // ─── 방문 목적 (동적) ────────────────────────────────────────────────────────
  final List<String> dynamicActivities;
  // 예: ['light_walk', 'jogging', 'running', 'cycling', 'hiking', 'inline', 'exercise_equipment']

  // ─── 동행자 유형 ─────────────────────────────────────────────────────────────
  final String? companion;
  // 예: 'alone' | 'couple' | 'friends' | 'family_parents' | 'family_kids' | 'pet'

  // ─── 공원 내 선호 시설 ────────────────────────────────────────────────────────
  final List<String> preferredFacilities;
  // 예: ['lawn', 'pond', 'playground', 'floor_fountain', 'dog_park', 'outdoor_stage', 'sports_court']

  // ─── 문화 및 체험 시설 ────────────────────────────────────────────────────────
  final List<String> culturalFacilities;
  // 예: ['museum', 'botanical_garden', 'zoo', 'heritage', 'camping', 'water_leisure']

  // ─── 공원 분위기 ─────────────────────────────────────────────────────────────
  final String? preferredAtmosphere;
  // 예: 'quiet' | 'lively' | 'local' | 'landmark'

  // ─── 자연 환경 스타일 ─────────────────────────────────────────────────────────
  final String? naturalStyle;
  // 예: 'forest' | 'riverside' | 'garden' | 'scenic_trail'

  // ─── 방문 시간대 ─────────────────────────────────────────────────────────────
  final String? visitTime;
  // 예: 'early_morning' | 'afternoon' | 'sunset' | 'night'

  // ─── 물리적 이동 수단 ─────────────────────────────────────────────────────────
  final String? transportType;
  // 예: 'walk' | 'transit' | 'car'

  // ─── 접근성 및 편의 조건 ─────────────────────────────────────────────────────
  final List<String> accessibilityNeeds;
  // 예: ['flat_ground', 'shade_area', 'clean_restroom', 'nearby_cafe']

  const UserPreferences({
    this.purpose,
    this.intensity,
    this.prefersToilet = true,
    this.prefersBench = true,
    this.prefersLighting = false,
    this.maxWalkDistanceKm = 3.0,
    this.staticActivities = const [],
    this.dynamicActivities = const [],
    this.companion,
    this.preferredFacilities = const [],
    this.culturalFacilities = const [],
    this.preferredAtmosphere,
    this.naturalStyle,
    this.visitTime,
    this.transportType,
    this.accessibilityNeeds = const [],
  });

  static const UserPreferences defaults = UserPreferences();

  // ─── 레이블 변환 ─────────────────────────────────────────────────────────────
  String get purposeLabel {
    switch (purpose) {
      case 'exercise': return '운동';
      case 'walking':  return '산책';
      default:         return '산책';
    }
  }

  String get intensityLabel {
    switch (intensity) {
      case 'low':    return '여유롭게 (저강도)';
      case 'high':   return '활발하게 (고강도)';
      case 'medium': return '적당하게 (중강도)';
      default:       return '적당하게 (중강도)';
    }
  }

  String get companionLabel {
    switch (companion) {
      case 'alone':          return '혼자';
      case 'couple':         return '연인(데이트)';
      case 'friends':        return '친구';
      case 'family_parents': return '가족(부모님)';
      case 'family_kids':    return '가족(아이 동반)';
      case 'pet':            return '반려동물';
      default:               return '';
    }
  }

  String get atmosphereLabel {
    switch (preferredAtmosphere) {
      case 'quiet':    return '한적하고 조용한 곳';
      case 'lively':   return '활기차고 사람 많은 곳';
      case 'local':    return '로컬 느낌의 동네 공원';
      case 'landmark': return '랜드마크형 대형 공원';
      default:         return '';
    }
  }

  String get naturalStyleLabel {
    switch (naturalStyle) {
      case 'forest':        return '나무가 우거진 숲길';
      case 'riverside':     return '탁 트인 강변/호수뷰';
      case 'garden':        return '잘 가꾸어진 평지 정원';
      case 'scenic_trail':  return '경치가 좋은 산책로';
      default:              return '';
    }
  }

  String get visitTimeLabel {
    switch (visitTime) {
      case 'early_morning': return '이른 아침';
      case 'afternoon':     return '낮/오후';
      case 'sunset':        return '일몰/노을 시간대';
      case 'night':         return '밤(야경/조명)';
      default:              return '';
    }
  }

  String get transportLabel {
    switch (transportType) {
      case 'walk':    return '도보 가능 거리';
      case 'transit': return '대중교통 30분 이내';
      case 'car':     return '자차 이동(주차장 필수)';
      default:        return '';
    }
  }

  static String staticActivityLabel(String v) {
    const m = {
      'rest': '휴식', 'picnic': '피크닉(돗자리)', 'reading': '독서',
      'watergazing': '물멍', 'meditation': '사색', 'sunbathing': '일광욕',
    };
    return m[v] ?? v;
  }

  static String dynamicActivityLabel(String v) {
    const m = {
      'light_walk': '가벼운 산책', 'jogging': '조깅', 'running': '러닝',
      'cycling': '자전거 라이딩', 'hiking': '등산', 'inline': '인라인/보드',
      'exercise_equipment': '야외 운동기구 사용',
    };
    return m[v] ?? v;
  }

  static String facilityLabel(String v) {
    const m = {
      'lawn': '잔디광장', 'pond': '연못/분수대', 'playground': '어린이 놀이터',
      'floor_fountain': '바닥분수', 'dog_park': '반려견 놀이터',
      'outdoor_stage': '야외 무대', 'sports_court': '운동장/테니스장',
    };
    return m[v] ?? v;
  }

  static String culturalFacilityLabel(String v) {
    const m = {
      'museum': '미술관/박물관', 'botanical_garden': '식물원/온실',
      'zoo': '동물원', 'heritage': '유적지',
      'camping': '캠핑장/취사구역', 'water_leisure': '오리배 등 수상 레저',
    };
    return m[v] ?? v;
  }

  static String accessibilityLabel(String v) {
    const m = {
      'flat_ground': '계단 없는 평지(유모차/휠체어)',
      'shade_area': '그늘막 설치 가능 구역',
      'clean_restroom': '공공 화장실 위생 상태',
      'nearby_cafe': '주변 맛집/카페 연계성',
    };
    return m[v] ?? v;
  }

  /// SharedPreferences에 JSON으로 직렬화
  Map<String, dynamic> toJson() => {
    'purpose': purpose,
    'intensity': intensity,
    'prefersToilet': prefersToilet,
    'prefersBench': prefersBench,
    'prefersLighting': prefersLighting,
    'maxWalkDistanceKm': maxWalkDistanceKm,
    'staticActivities': staticActivities,
    'dynamicActivities': dynamicActivities,
    'companion': companion,
    'preferredFacilities': preferredFacilities,
    'culturalFacilities': culturalFacilities,
    'preferredAtmosphere': preferredAtmosphere,
    'naturalStyle': naturalStyle,
    'visitTime': visitTime,
    'transportType': transportType,
    'accessibilityNeeds': accessibilityNeeds,
  };

  static UserPreferences fromJson(Map<String, dynamic> json) => UserPreferences(
    purpose: json['purpose'],
    intensity: json['intensity'],
    prefersToilet: json['prefersToilet'] ?? true,
    prefersBench: json['prefersBench'] ?? true,
    prefersLighting: json['prefersLighting'] ?? false,
    maxWalkDistanceKm: (json['maxWalkDistanceKm'] ?? 3.0).toDouble(),
    staticActivities: List<String>.from(json['staticActivities'] ?? []),
    dynamicActivities: List<String>.from(json['dynamicActivities'] ?? []),
    companion: json['companion'],
    preferredFacilities: List<String>.from(json['preferredFacilities'] ?? []),
    culturalFacilities: List<String>.from(json['culturalFacilities'] ?? []),
    preferredAtmosphere: json['preferredAtmosphere'],
    naturalStyle: json['naturalStyle'],
    visitTime: json['visitTime'],
    transportType: json['transportType'],
    accessibilityNeeds: List<String>.from(json['accessibilityNeeds'] ?? []),
  );
}
