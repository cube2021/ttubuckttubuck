import '../env/env.dart';

class AppConfig {
  static String get supabaseUrl => Env.supabaseUrl;
  static String get supabaseAnonKey => Env.supabaseAnonKey;
  static String get weatherApiKey => Env.weatherApiKey;

  /// 공공데이터포털 전국도시공원정보표준데이터 API 키 (선택)
  static String get publicDataApiKey => Env.publicDataApiKey.trim();

  static bool get hasPublicDataApiKey =>
      publicDataApiKey.isNotEmpty &&
      !publicDataApiKey.contains('여기에');
}
