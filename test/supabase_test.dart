import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EmptyLocalStorage extends LocalStorage {
  const EmptyLocalStorage();
  @override Future<void> initialize() async {}
  @override Future<String?> accessToken() async => null;
  @override Future<bool> hasAccessToken() async => false;
  @override Future<void> persistSession(String session) async {}
  @override Future<void> removePersistedSession() async {}
}

void main() {
  test('Inspect profiles table columns', () async {
    try {
      await dotenv.load(fileName: ".env");
      await Supabase.initialize(
        url: dotenv.get('SUPABASE_URL'),
        anonKey: dotenv.get('SUPABASE_ANON_KEY'),
        authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
      );
      final client = Supabase.instance.client;
      print('Supabase client initialized successfully.');

      try {
        final res = await client.from('profiles').select().limit(1);
        print('PROFILES SUCCESS! Result: $res');
      } catch (e) {
        print('PROFILES FAILED: $e');
      }
    } catch (e) {
      print('FAILED: $e');
    }
  });
}
