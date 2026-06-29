import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';
import '../env/env.dart';
import 'package:latlong2/latlong.dart';

import '../models/park.dart';
import '../models/user_preferences.dart';
import '../models/weather_context.dart';
import '../models/weather_context.dart';
import 'national_park_api_service.dart';
import 'region_service.dart';

// -----------------------------------------------------------------------------
// AI 프롬프트 템플릿 관리 (이곳에서 프롬프트를 쉽게 수정하세요)
// -----------------------------------------------------------------------------
class PromptTemplates {
  // 1. 공원 추천 - 시스템 지시문
  static String get parkRecommendationSystemInstruction => '''
당신은 개인 맞춤형 산책 서비스인 '뚜벅뚜벅'의 다정하고 감성적인 AI 산책 가이드입니다.
사용자에게 가장 잘 어울리는 공원과 그 공원 안에서 걸을 수 있는 최적의 '추천 코스(내부 경로)'를 안내하는 임무를 맡고 있습니다.

[안내 지침]
1. 제안하는 추천 답변은 반드시 친절하고 다정한 톤앤매너(존댓말)로 한국어로 작성해 주세요.
2. 기상 정보와 사용자의 현재 감정 상태(기분)를 충분히 반영하여, 왜 이 장소와 특정 코스가 적합한지 상세한 이유를 3~4문장 내외로 서술해 주세요.
3. 주변 공원 리스트 정보와 그 내부 경로 목록이 전달되면, 단순히 공원 이름만 나열하지 말고, **공원 이름과 추천 코스의 이름 및 난이도, 소요 시간, 거리**를 명확히 짚어 추천해 주세요.
4. 추천 시 반드시 해당 코스를 선택한 이유를 사용자의 현재 기분, 산책 목적, 선호 강도와 연결하여 자연스럽게 설명해 주세요.

[공원 내 코스 선정 규칙]
공원에 여러 코스가 존재할 경우, 아래 기준에 따라 사용자에게 가장 적합한 코스 하나를 선택하여 추천하세요.

▶ 기분 기반 선택
- 우울함·무기력함·지침 → 짧고 난이도가 낮은 코스. 조용한 숲길, 그늘길, 휴식 공간이 많은 코스 우선.
- 스트레스·답답함·분노 → 수변길, 호수길, 강변길, 시야가 탁 트인 넓은 순환형 코스 우선.
- 기분 좋음·활력 넘침 → 중~장거리 코스 또는 다양한 풍경을 경험할 수 있는 코스.
- 생각 정리·혼자만의 시간 → 이용객이 비교적 적고 자연 경관이 풍부한 코스.

▶ 산책 목적 기반 선택
- 힐링 및 휴식 → 난이도가 낮고 풍경 감상이 가능한 코스 우선.
- 운동 및 체력 관리 → 공원 내 가장 긴 코스 또는 중·고강도 코스 우선.
- 사진 촬영 → 전망대, 수변 공간, 꽃길, 포토존이 포함된 코스.
- 가족 나들이 → 놀이터, 잔디광장, 편의시설 접근성이 좋은 코스.

▶ 동행자 기반 선택
- 혼자 → 조용하고 사색하기 좋은 코스 우선.
- 연인 → 경관이 아름답고 분위기 있는 코스.
- 친구 → 대화를 나누며 걷기 좋은 순환형 코스.
- 아이 동반 → 안전하고 이동 거리가 짧은 코스.
- 반려동물 동반 → 넓은 산책로와 개방감 있는 코스 우선.

▶ 선호 강도 기반 선택
- 가벼운 산책 → 1~3km / 30~60분 코스.
- 보통 강도 → 3~5km / 1시간 전후 코스.
- 활동적인 산책 → 5km 이상 또는 공원 내 최장 코스.

▶ 접근성 고려
- 유모차·휠체어·노약자 관련 요구사항이 있는 경우 → 경사가 완만하고 포장 상태가 좋은 코스 우선.
''';

  // 2. 공원 추천 - 사용자 데이터 프롬프트
  static String buildParkRecommendationPrompt({
    required String mood,
    required String weather,
    required String comfortSummary,
    required String purposeLabel,
    required String intensityLabel,
    required String parksData,
    String companionLabel = '',
    String atmosphereLabel = '',
    String naturalStyleLabel = '',
    String visitTimeLabel = '',
    String transportLabel = '',
    List<String> staticActivities = const [],
    List<String> dynamicActivities = const [],
    List<String> preferredFacilities = const [],
    List<String> culturalFacilities = const [],
    List<String> accessibilityNeeds = const [],
  }) {
    final staticStr = staticActivities.map(UserPreferences.staticActivityLabel).join(', ');
    final dynamicStr = dynamicActivities.map(UserPreferences.dynamicActivityLabel).join(', ');
    final facilityStr = preferredFacilities.map(UserPreferences.facilityLabel).join(', ');
    final culturalStr = culturalFacilities.map(UserPreferences.culturalFacilityLabel).join(', ');
    final accessStr = accessibilityNeeds.map(UserPreferences.accessibilityLabel).join(', ');

    return '''
[사용자 정보]
- 현재 기분: $mood
- 현재 날씨: $weather
- 날씨 상세: $comfortSummary
- 산책 목적: $purposeLabel
- 선호 강도: $intensityLabel
${companionLabel.isNotEmpty ? '- 동행자: $companionLabel' : ''}
${staticStr.isNotEmpty ? '- 정적 활동 선호: $staticStr' : ''}
${dynamicStr.isNotEmpty ? '- 동적 활동 선호: $dynamicStr' : ''}
${facilityStr.isNotEmpty ? '- 원하는 공원 시설: $facilityStr' : ''}
${culturalStr.isNotEmpty ? '- 관심 문화/체험 시설: $culturalStr' : ''}
${atmosphereLabel.isNotEmpty ? '- 선호 공원 분위기: $atmosphereLabel' : ''}
${naturalStyleLabel.isNotEmpty ? '- 선호 자연 환경: $naturalStyleLabel' : ''}
${visitTimeLabel.isNotEmpty ? '- 방문 시간대: $visitTimeLabel' : ''}
${transportLabel.isNotEmpty ? '- 이동 수단: $transportLabel' : ''}
${accessStr.isNotEmpty ? '- 접근성 요구사항: $accessStr' : ''}

[주변 공원 및 세부 경로 데이터]
$parksData

위 사용자 정보(기분, 날씨, 동행자, 활동 성향, 시설 선호, 분위기, 시간대 등)와 [공원 내 코스 선정 규칙]을 종합적으로 고려하여 최적의 공원 1~2개와 구체적 코스를 추천해 주세요.
공원의 편의시설·분위기·자연 환경이 사용자의 성향과 어떻게 잘 맞는지, 그리고 왜 이 특정 코스를 선택했는지 이유를 사용자의 현재 기분, 산책 목적, 선호 강도와 연결하여 다정하게 한국어로 설명해 주세요.
''';
  }

  // 3. 공원 없음 - 시스템 지시문
  static String get noParkSystemInstruction => "당신은 개인 맞춤형 산책 서비스인 '뚜벅뚜벅'의 다정하고 감성적인 AI 산책 가이드입니다. 반드시 한국어로 답변하세요.";

  // 4. 공원 없음 - 사용자 프롬프트
  static String buildNoParkPrompt(String mood, String weather) {
    return "사용자가 현재 기분 '\$mood', 날씨 '\$weather'에서 산책을 하고 싶어하지만 주변에 적절한 공원을 찾지 못했습니다. 위로의 말과 함께 다른 동네로 가보거나 조금 더 멀리 걸어보라는 조언을 다정하게 3문장 이내로 해주세요.";
  }

  // 5. 지역 기반 AI 추천 프롬프트
  static String buildRegionJsonPrompt({
    required String regionName,
    required UserPreferences prefs,
  }) {
    final staticStr = prefs.staticActivities.map(UserPreferences.staticActivityLabel).join(', ');
    final dynamicStr = prefs.dynamicActivities.map(UserPreferences.dynamicActivityLabel).join(', ');
    final facilityStr = prefs.preferredFacilities.map(UserPreferences.facilityLabel).join(', ');
    final culturalStr = prefs.culturalFacilities.map(UserPreferences.culturalFacilityLabel).join(', ');
    final accessStr = prefs.accessibilityNeeds.map(UserPreferences.accessibilityLabel).join(', ');

    return '''
당신은 대한민국 공원 전문 AI 가이드입니다.
"$regionName" 지역에서 위 사용자 성향에 가장 잘 맞는 실제 공원 3~5개를 추천해 주세요.

[사용자 성향 정보]
- 산책 목적: ${prefs.purposeLabel}
- 선호 강도: ${prefs.intensityLabel}
${prefs.companionLabel.isNotEmpty ? '- 동행자: ${prefs.companionLabel}' : ''}
${staticStr.isNotEmpty ? '- 정적 활동 선호: $staticStr' : ''}
${dynamicStr.isNotEmpty ? '- 동적 활동 선호: $dynamicStr' : ''}
${facilityStr.isNotEmpty ? '- 원하는 시설: $facilityStr' : ''}
${culturalStr.isNotEmpty ? '- 관심 문화시설: $culturalStr' : ''}
${prefs.atmosphereLabel.isNotEmpty ? '- 선호 분위기: ${prefs.atmosphereLabel}' : ''}
${prefs.naturalStyleLabel.isNotEmpty ? '- 선호 자연 환경: ${prefs.naturalStyleLabel}' : ''}

[중요 요청]
결과는 반드시 아래의 JSON 형식으로만 응답해야 합니다. 마크다운 블록(```json)이나 다른 설명은 절대 추가하지 마세요.
[
  {
    "name": "공원 이름 (예: OO시민공원)",
    "lat": 37.5855,
    "lng": 127.1444,
    "reason": "사용자 성향과 맞는 구체적이고 다정한 추천 이유 (2문장 이내)"
  }
]
''';
  }
}
// -----------------------------------------------------------------------------

class GeminiService {
  static Future<String> getParkRecommendation({
    required List<Park> parks,
    required String mood,
    required String weather,
    UserPreferences? preferences,
    WeatherContext? weatherContext,
  }) async {
    final geminiKey = Env.geminiApiKey;
    final groqKey = Env.groqApiKey;

    if (geminiKey.isEmpty && groqKey.isEmpty) {
      debugPrint("Dotenv 오류: 환경 변수가 로드되지 않았습니다.");
      return "설정 파일을 불러오지 못했습니다. 앱을 다시 시작해주세요.";
    }

    final prefs = preferences ?? UserPreferences.defaults;
    final wx = weatherContext ?? WeatherContext.fromDescription(weather);

    final systemInstruction = PromptTemplates.parkRecommendationSystemInstruction;

    final buffer = StringBuffer();
    for (var p in parks) {
      buffer.writeln('### 공원: ${p.name}');
      buffer.writeln('- 종류: ${p.typeLabel}');
      buffer.writeln('- 최단 거리: ${p.distanceFromRoute.toInt()}m');
      buffer.writeln('- AI 매칭 점수: ${(p.vectorSimilarity * 100).toInt()}%');
      if (p.enrichedTags.isNotEmpty) {
        buffer.writeln('- 맞춤 태그: ${p.enrichedTags.join(", ")}');
      }
      buffer.writeln('- 평점: ${p.rating} / 5.0');
      buffer.writeln('- 편의시설: 화장실(${p.hasToilet ? "O" : "X"}), 벤치(${p.hasBench ? "O" : "X"}), 조명(${p.hasLighting ? "O" : "X"})');
      buffer.writeln('- 면적: ${p.area.toInt()}m²');
      buffer.writeln('- 추천 내부 경로 목록:');
      if (p.routes.isEmpty) {
        buffer.writeln('  * 추천 내부 경로가 없습니다.');
      } else {
        for (var r in p.routes) {
          buffer.writeln('  * 코스명: ${r.name} (길이: ${r.distanceKm}km, 소요시간: ${r.durationMinutes}분, 난이도: ${r.difficulty})');
          buffer.writeln('    - 설명: ${r.description}');
        }
      }
      buffer.writeln();
    }

    final prompt = PromptTemplates.buildParkRecommendationPrompt(
      mood: mood,
      weather: weather,
      comfortSummary: wx.comfortSummary,
      purposeLabel: prefs.purposeLabel,
      intensityLabel: prefs.intensityLabel,
      parksData: buffer.toString(),
      companionLabel: prefs.companionLabel,
      atmosphereLabel: prefs.atmosphereLabel,
      naturalStyleLabel: prefs.naturalStyleLabel,
      visitTimeLabel: prefs.visitTimeLabel,
      transportLabel: prefs.transportLabel,
      staticActivities: prefs.staticActivities,
      dynamicActivities: prefs.dynamicActivities,
      preferredFacilities: prefs.preferredFacilities,
      culturalFacilities: prefs.culturalFacilities,
      accessibilityNeeds: prefs.accessibilityNeeds,
    );

    // 1. Gemini API 우선 시도
    if (geminiKey != null && geminiKey.isNotEmpty && !geminiKey.contains('여기에')) {
      try {
        debugPrint('[AiService] 1순위: Gemini 모델 호출 시도');
        final model = GenerativeModel(
          model: 'gemini-2.5-flash-lite',
          apiKey: geminiKey,
          systemInstruction: Content.system(systemInstruction),
        );
        final response = await model.generateContent([Content.text(prompt)]);
        if (response.text != null && response.text!.isNotEmpty) {
          return response.text!;
        }
      } catch (e) {
        debugPrint("Gemini 에러 발생: $e -> 2순위 Groq API로 전환합니다.");
      }
    }

    // 2. Groq API (대체재) 시도
    if (groqKey != null && groqKey.isNotEmpty && !groqKey.contains('여기에')) {
      try {
        debugPrint("[AiService] 2순위: Groq API(Llama 3) 모델 호출 시도");
        final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $groqKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'system', 'content': systemInstruction},
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.7,
            'max_tokens': 800,
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final responseText = data['choices'][0]['message']['content'] as String?;
          if (responseText != null && responseText.isNotEmpty) {
            return responseText;
          }
        } else {
          debugPrint("[AiService] Groq 에러 응답: ${response.statusCode} - ${response.body}");
        }
      } catch (e) {
        debugPrint("Groq 에러 발생: $e -> 3순위 로컬 폴백으로 전환합니다.");
      }
    }

    // 3. 모두 실패 시 로컬 폴백
    debugPrint("[AiService] 모든 AI 호출 실패. 자체 로컬 폴백 텍스트 생성.");
    return _generateLocalFallback(parks, mood, weather, prefs, wx);
  }

  static Future<String> getNoParkRecommendation(String mood, String weather) async {
    final geminiKey = Env.geminiApiKey;
    final groqKey = Env.groqApiKey;

    final systemInstruction = PromptTemplates.noParkSystemInstruction;
    final prompt = PromptTemplates.buildNoParkPrompt(mood, weather);

    // 1. Gemini API 시도
    if (geminiKey != null && geminiKey.isNotEmpty && !geminiKey.contains('여기에')) {
      try {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash-lite', 
          apiKey: geminiKey,
          systemInstruction: Content.system(systemInstruction),
        );
        final response = await model.generateContent([Content.text(prompt)]);
        if (response.text != null && response.text!.isNotEmpty) return response.text!;
      } catch (e) {
        debugPrint("Gemini 에러 (공원없음): $e -> Groq API로 전환합니다.");
      }
    }

    // 2. Groq API 시도
    if (groqKey != null && groqKey.isNotEmpty && !groqKey.contains('여기에')) {
      try {
        final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $groqKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'system', 'content': systemInstruction},
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.7,
            'max_tokens': 300,
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final responseText = data['choices'][0]['message']['content'] as String?;
          if (responseText != null && responseText.isNotEmpty) return responseText;
        }
      } catch (e) {
        debugPrint("Groq 에러 (공원없음): $e");
      }
    }

    // 3. 로컬 폴백
    return "현재 주변에 적합한 공원이 보이지 않네요. 기분 좋은 산책을 위해 다른 지역을 찾아보시는 건 어떨까요?";
  }

  /// 지역 기반 AI 공원 추천 (JSON 리스트 반환)
  static Future<List<Park>> getRegionParksAsList({
    required String regionName,
    required UserPreferences preferences,
  }) async {
    final geminiKey = Env.geminiApiKey;
    final groqKey = Env.groqApiKey;
    const systemInstruction = "당신은 대한민국 공원 전문 AI 가이드입니다. 오직 JSON 형식으로만 응답하세요.";
    final prompt = PromptTemplates.buildRegionJsonPrompt(
      regionName: regionName,
      prefs: preferences,
    );

    String? responseText;

    // 1. Gemini
    if (geminiKey != null && geminiKey.isNotEmpty && !geminiKey.contains('여기에')) {
      try {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash-lite',
          apiKey: geminiKey,
          systemInstruction: Content.system(systemInstruction),
        );
        final response = await model.generateContent([Content.text(prompt)]);
        responseText = response.text;
      } catch (e) {
        debugPrint('Gemini 지역 JSON 에러: $e -> Groq 전환');
      }
    }

    // 2. Groq
    if ((responseText == null || responseText.isEmpty) && groqKey != null && groqKey.isNotEmpty && !groqKey.contains('여기에')) {
      try {
        final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
        final response = await http.post(url,
          headers: {'Authorization': 'Bearer $groqKey', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'llama-3.3-70b-versatile',
            'messages': [
              {'role': 'system', 'content': systemInstruction},
              {'role': 'user', 'content': prompt},
            ],
            'temperature': 0.5,
            'max_tokens': 800,
          }),
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          responseText = data['choices'][0]['message']['content'] as String?;
        }
      } catch (e) {
        debugPrint('Groq 지역 JSON 에러: $e');
      }
    }

    if (responseText != null && responseText.isNotEmpty) {
      try {
        String cleanJson = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
        int startIndex = cleanJson.indexOf('[');
        int endIndex = cleanJson.lastIndexOf(']');
        if (startIndex != -1 && endIndex != -1) {
          cleanJson = cleanJson.substring(startIndex, endIndex + 1);
        }

        final List<dynamic> list = jsonDecode(cleanJson);

        // 공원별 좌표 조회 함수 (단일 공원)
        Future<Park?> resolvePark(dynamic item) async {
          final parkName = item['name']?.toString() ?? '이름 없는 공원';
          double lat = double.tryParse(item['lat'].toString()) ?? 37.5665;
          double lng = double.tryParse(item['lng'].toString()) ?? 126.9780;

          // 1. 공공데이터 로컬 캐시 검색 (빠름, 네트워크 불필요)
          try {
            final nationalMatch = await NationalParkApiService.findByNameOrRegion(regionName, parkName);
            if (nationalMatch != null && nationalMatch.latitude != 0.0) {
              lat = nationalMatch.latitude;
              lng = nationalMatch.longitude;
            } else {
              // 2. 로컬에 없을 때만 Nominatim 1회 호출 (딜레이 없음)
              final realLocation = await RegionService.geocodeAddress('$regionName $parkName');
              if (realLocation != null) {
                lat = realLocation.latitude;
                lng = realLocation.longitude;
              }
            }
          } catch (_) {}

          return Park(
            name: parkName,
            location: LatLng(lat, lng),
            typeLabel: '✨ AI 추천 공원',
            distanceFromRoute: 0,
            rating: 4.8,
            congestion: '여유',
            hasToilet: false,
            hasBench: false,
            hasLighting: false,
            hasParking: false,
            hasExerciseEquipment: false,
            area: 10000,
            openDate: item['reason']?.toString() ?? '',
            manageNo: 'ai_${DateTime.now().millisecondsSinceEpoch}',
            dataSource: 'ai_curation',
            routes: const [],
            moodScore: 100,
            sortDistance: 0,
          );
        }

        // 최대 5개 공원 좌표를 병렬로 처리 (순차 대비 최대 5배 빠름)
        final resolved = await Future.wait(list.take(5).map(resolvePark));
        final List<Park> parks = resolved.whereType<Park>().toList();

        // 시설 정보 보강
        try {
          await NationalParkApiService.enrichParkFacilities(parks, radiusM: 500);
        } catch (e) {
          debugPrint('AI 추천 공원 시설 매칭 실패: $e');
        }

        return parks;
      } catch (e) {
        debugPrint('JSON Parsing error: $e\nText: $responseText');
      }
    }
    return [];
  }

  static String _generateLocalFallback(
    List<Park> parks,
    String mood,
    String weather,
    UserPreferences prefs,
    WeatherContext wx,
  ) {
    if (parks.isEmpty) return "현재 주변에 적합한 공원이 보이지 않네요. 기분 좋은 산책을 위해 다른 지역을 찾아보시는 건 어떨까요?";

    final topPark = parks.first;
    final topRoute = topPark.routes.isNotEmpty ? topPark.routes.first : null;

    final buffer = StringBuffer();
    buffer.writeln("안녕하세요! 뚜벅뚜벅 AI 가이드입니다. 🐾");
    buffer.writeln("현재 AI 서버가 혼잡하여 **기본 맞춤 코스**를 즉시 안내해 드립니다.\n");
    
    buffer.writeln("지금 같은 **$weather**, 기분이 **$mood**일 때에는 **${topPark.name}**을(를) 추천해 드려요!");
    if (topPark.hasBench || topPark.hasToilet) {
      final features = [];
      if (topPark.hasBench) features.add("벤치");
      if (topPark.hasToilet) features.add("화장실");
      buffer.writeln("이곳은 ${features.join(', ')} 등의 편의시설이 마련되어 있어 더욱 쾌적하게 산책할 수 있습니다.\n");
    }

    if (topRoute != null) {
      buffer.writeln("### 추천 코스: ${topRoute.name}");
      buffer.writeln("- **거리/시간**: ${topRoute.distanceKm}km / 약 ${topRoute.durationMinutes}분");
      buffer.writeln("- **난이도**: ${topRoute.difficulty}");
      buffer.writeln("\n이 코스는 ${topRoute.description}");
    } else {
      buffer.writeln("\n이 공원에서 **${prefs.purposeLabel}**을(를) 목적으로 여유로운 시간을 보내보세요.");
    }
    
    buffer.writeln("\n가벼운 마음으로 걷기 딱 좋습니다. 안전하고 즐거운 산책 되세요! 😊");

    return buffer.toString();
  }
}
