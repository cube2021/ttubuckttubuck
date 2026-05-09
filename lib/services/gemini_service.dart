import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../models/park.dart';

class GeminiService {
  static Future<String> getParkRecommendation({
    required List<Park> parks,
    required String mood,
    required String weather,
  }) async {
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey.contains('여기에_사용자님의_제미나이_API_키를_붙여넣으세요')) {
      debugPrint("Gemini API 키 오류: 키가 없거나 플레이스홀더 상태입니다.");
      return "AI 분석을 위해 .env 파일에 유효한 Gemini API 키를 설정해주세요.";
    }
    
    if (dotenv.env.isEmpty) {
      debugPrint("Dotenv 오류: 환경 변수가 로드되지 않았습니다.");
      return "설정 파일을 불러오지 못했습니다. 앱을 다시 시작해주세요.";
    }

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash-lite', apiKey: apiKey);
      
      String parkListText = parks.map((p) => '- ${p.name} (${p.typeLabel}, ${p.distanceFromRoute.toInt()}m)').join('\n');
      
      final prompt = '''
당신은 '뚜벅뚜벅' 이라는 산책 앱의 친절한 AI 가이드입니다.
사용자의 현재 기분은 "$mood"이며, 날씨는 "$weather"입니다.

아래는 사용자 산책 경로 주변에서 찾은 공원 목록입니다:
$parkListText

위 공원들 중에서 기분과 날씨에 가장 잘 어울리는 공원을 1~2개 골라서 추천해주세요.
왜 이 공원이 현재 기분과 날씨에 적합한지 3~4문장으로 다정하게 설명해주세요.
너무 길지 않게, 모바일 앱에서 읽기 좋게 요약해주세요.
''';

      debugPrint("Gemini 요청 프롬프트:\n$prompt");
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      debugPrint("Gemini 응답 결과: ${response.text}");
      return response.text ?? "AI 추천을 생성하지 못했습니다.";
    } catch (e) {
      debugPrint("Gemini 에러: $e");
      if (e.toString().contains('quota')) {
        return "AI 요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요.";
      }
      return "AI 분석 중 오류 발생: ${e.toString()}";
    }
  }

  static Future<String> getNoParkRecommendation(String mood, String weather) async {
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey.contains('여기에_사용자님의_제미나이_API_키를_붙여넣으세요')) {
      return "설정된 AI API 키가 없거나 주변 공원을 찾지 못했습니다.";
    }

    try {
      final model = GenerativeModel(model: 'gemini-2.0-flash-lite', apiKey: apiKey);
      final prompt = "사용자가 현재 기분 '$mood', 날씨 '$weather'에서 산책을 하고 싶어하지만 주변에 적절한 공원을 찾지 못했습니다. 위로의 말과 함께 다른 동네로 가보거나 조금 더 멀리 걸어보라는 조언을 다정하게 3문장 이내로 해주세요.";
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "주변에 공원이 없네요. 조금 더 멀리 산책을 떠나보는 건 어떨까요?";
    } catch (e) {
      debugPrint("Gemini 에러 (공원없음): $e");
      return "AI 분석 중 오류 발생: ${e.toString()}";
    }
  }
}
