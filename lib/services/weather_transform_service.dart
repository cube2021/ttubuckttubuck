import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather_context.dart';
import 'config.dart';

/// 날씨 API 응답을 추천 엔진용 WeatherContext로 변환합니다.
class WeatherTransformService {
  static Future<WeatherContext> fetch(double lat, double lon) async {
    try {
      final weatherUrl =
          'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=${AppConfig.weatherApiKey}&units=metric&lang=kr';
      final airUrl =
          'https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=${AppConfig.weatherApiKey}';

      final results = await Future.wait([
        http.get(Uri.parse(weatherUrl)),
        http.get(Uri.parse(airUrl)),
      ]);

      String description = '맑음';
      double? temp;
      double? humidity;
      double? pop;
      double? pm10;
      double? pm25;
      String weatherMain = 'clear';

      if (results[0].statusCode == 200) {
        final data = json.decode(results[0].body);
        description = data['weather']?[0]?['description'] ?? description;
        temp = (data['main']?['temp'] as num?)?.toDouble();
        humidity = (data['main']?['humidity'] as num?)?.toDouble(); // 0~100 (%)
        weatherMain = (data['weather']?[0]?['main'] as String? ?? 'clear').toLowerCase();
        pop = (data['rain'] != null || data['snow'] != null) ? 0.8 : 0.0;
      }

      if (results[1].statusCode == 200) {
        final air = json.decode(results[1].body);
        final components = air['list']?[0]?['components'];
        if (components != null) {
          pm10 = (components['pm10'] as num?)?.toDouble();
          pm25 = (components['pm2_5'] as num?)?.toDouble();
        }
      }

      final rainy = ['rain', 'drizzle', 'thunderstorm', 'snow'].contains(weatherMain) ||
          (description.contains('비') || description.contains('눈'));
      final hot = temp != null && temp >= 30;
      final cold = temp != null && temp <= 5;
      final poorAir = (pm10 != null && pm10 > 80) || (pm25 != null && pm25 > 35);

      return WeatherContext(
        description: description,
        temperatureC: temp,
        humidity: humidity,
        precipitationProbability: pop,
        pm10: pm10,
        pm25: pm25,
        isRainy: rainy,
        isHot: hot,
        isCold: cold,
        isPoorAir: poorAir,
      );
    } catch (_) {
      return WeatherContext.fallback;
    }
  }

}
