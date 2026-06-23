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

  String get comfortSummary {
    final parts = <String>[description];
    if (temperatureC != null) parts.add('${temperatureC!.toStringAsFixed(1)}°C');
    if (humidity != null) parts.add('습도 ${humidity!.toInt()}%');
    if (heatIndex != null && heatDangerLevel >= 1) {
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
    if (isRainy) score -= 50; // 비/눈 오면 큰 폭의 패널티
    if (isHot) score -= 25;   // 폭염 패널티
    if (isCold) score -= 25;  // 한파 패널티
    if (isPoorAir) score -= 20; // 미세먼지 나쁨 패널티

    // 체감온도 추가 패널티
    final level = heatDangerLevel;
    if (level == 1) score -= 10;
    if (level == 2) score -= 25;
    if (level >= 3) score -= 40;

    // 추가적인 대기오염 디테일 패널티
    if (pm10 != null && pm10! > 150) score -= 20;
    if (pm25 != null && pm25! > 75)  score -= 20;

    return score.clamp(0, 100);
  }

  /// 산책 적합성에 대한 직관적인 3단계 텍스트 라벨
  String get walkingEvaluation {
    final score = walkingScore;
    if (score >= 85) return '산책하기 아주 좋은 날씨예요! ☀️';
    if (score >= 60) return '산책하기 무난한 날씨예요 ⛅';
    return '오늘은 실내 걷기를 추천해요 ⚠️';
  }

  /// 상태별 맞춤형 코치 팁 메시지
  String get walkingTip {
    if (isRainy) return '비나 눈 소식이 있으니 안전에 주의하시고, 우산을 꼭 챙기세요. ☔';
    if (shouldShowHeatWarning) return '체감온도가 매우 높습니다! 야외 산책은 자제하고 꼭 나가야 한다면 수분을 충분히 챙기세요. 🥵';
    if (isPoorAir) return '미세먼지 수치가 높습니다! 야외 산책 시 KF 마스크를 착용하세요. 😷';
    if (isHot) return '기온이 다소 높으니 선크림을 바르고 시원한 물을 소지하세요. 🥵';
    if (isCold) return '날씨가 매우 춥습니다. 장갑과 머플러를 하고 보온에 유의하세요. 🥶';
    return '바람도 선선하고 대기 상태도 양호하여 산책하기에 최적입니다. 즐거운 뚜벅이 시간 되세요! 🌱';
  }

  String get walkingScoreMessage {
    return '$walkingEvaluation (산책 지수 $walkingScore점)';
  }
}
