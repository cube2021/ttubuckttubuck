import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env', obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'SUPABASE_URL')
  static final String supabaseUrl = _Env.supabaseUrl;

  @EnviedField(varName: 'SUPABASE_ANON_KEY')
  static final String supabaseAnonKey = _Env.supabaseAnonKey;

  @EnviedField(varName: 'WEATHER_API_KEY')
  static final String weatherApiKey = _Env.weatherApiKey;

  @EnviedField(varName: 'GEMINI_API_KEY')
  static final String geminiApiKey = _Env.geminiApiKey;

  @EnviedField(varName: 'PUBLIC_DATA_API_KEY')
  static final String publicDataApiKey = _Env.publicDataApiKey;

  @EnviedField(varName: 'GROQ_API_KEY')
  static final String groqApiKey = _Env.groqApiKey;

  @EnviedField(varName: 'GOOGLE_MAPS_API_KEY')
  static final String googleMapsApiKey = _Env.googleMapsApiKey;
}
