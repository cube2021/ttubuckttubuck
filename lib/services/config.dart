import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get supabaseUrl => dotenv.get('SUPABASE_URL');
  static String get supabaseAnonKey => dotenv.get('SUPABASE_ANON_KEY');
  static String get weatherApiKey => dotenv.get('WEATHER_API_KEY');

  /// 공공데이터포털 전국도시공원정보표준데이터 API 키 (선택)
  static String get publicDataApiKey =>
      dotenv.env['PUBLIC_DATA_API_KEY']?.trim() ?? '';

  static bool get hasPublicDataApiKey =>
      publicDataApiKey.isNotEmpty &&
      !publicDataApiKey.contains('여기에');
}
