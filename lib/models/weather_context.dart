import 'dart:math' as math;

/// OpenWeatherMap 원시 데이터를 추천 파이프라인용으로 변환 (구성도: Data Transformation)
class WeatherContext {
  final String description;
  final double? temperatureC;
  final double? humidity; // 0~100 (%)
  final double? precipitationProbability; // 0~1
  final double? pm10;
  final double? pm25;
  final bool isRainy;
  final bool isHot;
  final bool isCold;
  final bool isPoorAir;

  const WeatherContext({
    required this.description,
    this.temperatureC,
    this.humidity,
    this.precipitationProbability,
    this.pm10,
    this.pm25,
    this.isRainy = false,
    this.isHot = false,
    this.isCold = false,
    this.isPoorAir = false,
  });

  static const WeatherContext fallback = WeatherContext(description: '맑음');

  factory WeatherContext.fromDescription(String description) {
    final rainy = description.contains('비') || description.contains('눈');
    return WeatherContext(description: description, isRainy: rainy);
  }

  /// 미국 NOAA 공식 Heat Index 공식 (°C 기준 변환 포함)
  /// 기온 27°C 이상, 습도 40% 이상일 때 의미 있는 수치를 산출합니다.
  double? get heatIndex {
    final t = temperatureC;
    final h = humidity;
    if (t == null || h == null) return null;
    if (t < 27) return t; // 27°C 미만은 체감온도 ≈ 실제기온

    // NOAA 공식은 화씨 기준 → 화씨로 변환 후 계산 후 다시 섭씨로
    final tf = t * 9 / 5 + 32; // °F
    final hi = -42.379
        + 2.04901523 * tf
        + 10.14333127 * h
        - 0.22475541 * tf * h
        - 0.00683783 * tf * tf
        - 0.05391555 * h * h
        + 0.00122874 * tf * tf * h
        + 0.00085282 * tf * h * h
        - 0.00000199 * tf * tf * h * h;

    // 저습도(< 13%) & 고온(80~112°F) 보정
    if (h < 13 && tf >= 80 && tf <= 112) {
      final adj = ((13 - h) / 4) * math.sqrt((17 - (tf - 95).abs()) / 17);
      return (hi - adj - 32) * 5 / 9;
    }

    // 고습도(> 85%) & 중온(80~87°F) 보정
    if (h > 85 && tf >= 80 && tf <= 87) {
      final adj = ((h - 85) / 10) * ((87 - tf) / 5);
      return (hi + adj - 32) * 5 / 9;
    }

    return (hi - 32) * 5 / 9;
  }

  /// 체감온도(Heat Index) 기반 위험 등급
  /// - 0: 안전
  /// - 1: 주의 (32~41°C)
  /// - 2: 위험 (41~54°C)
  /// - 3: 매우 위험 (54°C 이상)
  int get heatDangerLevel {
    final hi = heatIndex;
    if (hi == null) return 0;
    if (hi >= 54) return 3; // 매우 위험: 열사병 가능
    if (hi >= 41) return 2; // 위험: 열사병·열경련 가능
    if (hi >= 32) return 1; // 주의: 장시간 노출 시 피로
    return 0;
  }

  /// 경고 다이얼로그를 띄워야 하는가? (위험 수준 2 이상)
  bool get shouldShowHeatWarning => heatDangerLevel >= 2;

  /// 위험 등급별 경고 제목
  String get heatWarningTitle {
    switch (heatDangerLevel) {
      case 3: return '🔴 매우 위험한 폭염 경보!';
      case 2: return '🟠 위험한 폭염 주의보!';
      case 1: return '🟡 폭염 주의';
      default: return '';
    }
  }

  /// 위험 등급별 경고 본문 메시지
  String get heatWarningBody {
    final hi = heatIndex?.toStringAsFixed(1) ?? '-';
    final t  = temperatureC?.toStringAsFixed(1) ?? '-';
    final hu = humidity?.toInt().toString() ?? '-';

    switch (heatDangerLevel) {
      case 3:
        return '현재 기온 $t°C · 습도 $hu% → 체감온도 $hi°C\n\n'
            '열사병·열경련 등 온열질환 위험이 매우 높습니다.\n'
            '야외 산책을 즉시 중단하고 시원한 곳으로 이동하세요.\n\n'
            '• 수분을 자주 섭취하고 직사광선을 피하세요\n'
            '• 어지럼증·구역질 발생 시 즉시 119에 신고하세요';
      case 2:
        return '현재 기온 $t°C · 습도 $hu% → 체감온도 $hi°C\n\n'
            '장시간 야외 활동 시 열사병 위험이 있습니다.\n'
            '짧은 거리 산책 후 반드시 실내에서 휴식하세요.\n\n'
            '• 넉넉한 물과 전해질 음료를 준비하세요\n'
            '• 모자·양산 등 햇빛 차단 용품을 착용하세요\n'
            '• 쿨타올 및 휴대용 선풍기를 지참하세요';
      default:
        return '체감온도가 높습니다. 충분한 수분 섭취를 권장합니다.';
    }
  }

  /// 불쾌지수 (THI: Temperature-Humidity Index)
  double? get discomfortIndex {
    final t = temperatureC;
    final h = humidity;
    if (t == null || h == null) return null;
    return 1.8 * t - 0.55 * (1 - h / 100.0) * (1.8 * t - 26) + 32;
  }

  String get comfortSummary {
    final parts = <String>[description];
    if (temperatureC != null) parts.add('${temperatureC!.toStringAsFixed(1)}°C');
    if (humidity != null) parts.add('습도 ${humidity!.toInt()}%');
    
    final thi = discomfortIndex;
    if (thi != null && thi >= 75) {
      parts.add('불쾌지수 높음');
    } else if (heatIndex != null && heatDangerLevel >= 1) {
      parts.add('체감 ${heatIndex!.toStringAsFixed(1)}°C');
    }
    
    if (precipitationProbability != null && precipitationProbability! > 0.3) {
      parts.add('강수확률 ${(precipitationProbability! * 100).toInt()}%');
    }
    if (isPoorAir) parts.add('미세먼지 주의');
    return parts.join(' · ');
  }

  /// 종합 날씨 요소를 바탕으로 산책 적합도를 100점 만점으로 수치화
  int get walkingScore {
    int score = 100;
    
    // 1. 강수 패널티 (눈/비)
    if (isRainy) score -= 60;
    if (precipitationProbability != null) {
      if (precipitationProbability! >= 0.8) score -= 40;
      else if (precipitationProbability! >= 0.5) score -= 20;
      else if (precipitationProbability! >= 0.3) score -= 10;
    }

    // 2. 기온 패널티 (최적: 15~22도)
    if (temperatureC != null) {
      final t = temperatureC!;
      if (t >= 33) score -= 30; // 폭염 경보급
      else if (t >= 28) score -= 15; // 폭염 주의보급
      else if (t >= 23) score -= 5; // 약간 더움
      else if (t < 5) score -= 30; // 한파
      else if (t < 10) score -= 15; // 추움
      else if (t < 15) score -= 5; // 쌀쌀함
    } else {
      if (isHot) score -= 25;
      if (isCold) score -= 25;
    }

    // 3. 체감온도(Heat Index) 추가 패널티 (열사병 위험)
    final level = heatDangerLevel;
    if (level == 1) score -= 10;
    if (level == 2) score -= 25;
    if (level >= 3) score -= 40;

    // 4. 불쾌지수(THI) 패널티 (기온/습도 복합)
    final thi = discomfortIndex;
    if (thi != null) {
      if (thi >= 80) score -= 30; // 80 이상: 매우 불쾌 (대부분 불쾌감)
      else if (thi >= 75) score -= 15; // 75 이상: 50% 정도 불쾌감
      else if (thi >= 68) score -= 5; // 68 이상: 일부 불쾌감
    } else if (humidity != null) {
      if (humidity! >= 90) score -= 20;
      else if (humidity! >= 80) score -= 10;
    }

    // 5. 대기질(미세먼지) 패널티 및 보너스
    if (pm10 != null || pm25 != null) {
      if (pm10 != null) {
        if (pm10! > 150) score -= 30; // 매우 나쁨
        else if (pm10! > 80) score -= 15; // 나쁨
        else if (pm10! <= 30) score += 5; // 좋음 가산점
      }
      if (pm25 != null) {
        if (pm25! > 75) score -= 40; // 초미세 매우 나쁨
        else if (pm25! > 35) score -= 20; // 초미세 나쁨
        else if (pm25! <= 15) score += 5; // 초미세 좋음 가산점
      }
    } else {
      if (isPoorAir) score -= 20;
    }

    return score.clamp(0, 100);
  }

  /// 산책 적합성에 대한 직관적인 5단계 텍스트 라벨
  String get walkingEvaluation {
    final score = walkingScore;
    if (score >= 90) return '완벽한 산책 날씨예요! 🌿';
    if (score >= 75) return '산책하기 좋은 날씨예요 ☀️';
    if (score >= 50) return '산책하기 무난한 날씨예요 ⛅';
    if (score >= 30) return '야외 활동에 주의가 필요해요 ⚠️';
    return '오늘은 실내 활동을 추천해요 🚫';
  }

  /// 상태별 맞춤형 정밀 코치 팁 메시지
  String get walkingTip {
    if (isRainy || (precipitationProbability != null && precipitationProbability! >= 0.8)) {
      return '비나 눈이 강하게 예상됩니다. 실내에서 휴식하는 것을 추천드려요. ☔';
    }
    if (shouldShowHeatWarning || (temperatureC != null && temperatureC! >= 33)) {
      return '폭염으로 온열질환 위험이 큽니다. 외출을 자제하고 수분을 충분히 섭취하세요! 🥵';
    }
    if ((pm25 != null && pm25! > 75) || (pm10 != null && pm10! > 150)) {
      return '대기질이 매우 나쁩니다. 가급적 야외 활동을 피하고 실내에 머무르세요. 😷';
    }
    final thi = discomfortIndex;
    if (thi != null && thi >= 80) {
      return '불쾌지수가 매우 높습니다! 땀이 많이 나고 쉽게 지칠 수 있으니 무리한 산책은 피하세요. 💦';
    }
    if (temperatureC != null && temperatureC! < 5) {
      return '날씨가 몹시 춥습니다. 빙판길 미끄럼에 주의하시고 방한에 신경 쓰세요. 🥶';
    }
    if (walkingScore >= 90) {
      return '모든 조건이 최적인 날입니다! 지금 당장 나가서 상쾌한 공기를 마셔보세요! ✨';
    }
    if (walkingScore >= 75) {
      return '기분 전환하기 좋은 날씨입니다. 가벼운 발걸음으로 산책을 즐겨보세요! 🚶‍♂️';
    }
    if (walkingScore < 50 && pm25 != null && pm25! > 35) {
      return '초미세먼지 농도가 짙습니다. 마스크를 챙기시고 짧게 다녀오세요. 🤧';
    }
    return '날씨 변화를 확인하며 적당한 속도로 산책을 즐겨보세요. ☁️';
  }

  String get walkingScoreMessage {
    return '$walkingEvaluation (산책 지수 $walkingScore점)';
  }
}
