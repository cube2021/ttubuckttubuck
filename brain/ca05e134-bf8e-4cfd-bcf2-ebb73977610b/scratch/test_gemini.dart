import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

void main() async {
  // Manual load of .env since we are running as a script
  final file = File('.env');
  final lines = await file.readAsLines();
  final env = <String, String>{};
  for (var line in lines) {
    if (line.contains('=')) {
      final parts = line.split('=');
      env[parts[0]] = parts.sublist(1).join('=');
    }
  }

  final apiKey = env['GEMINI_API_KEY'];
  print('Testing Gemini API with key: ${apiKey?.substring(0, 5)}...');

  if (apiKey == null || apiKey.isEmpty) {
    print('Error: API Key is missing');
    return;
  }

  try {
    final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
    final content = [Content.text('안녕? 너는 누구니? 다정하게 대답해줘.')];
    final response = await model.generateContent(content);
    print('Response: ${response.text}');
  } catch (e) {
    print('Error: $e');
  }
}
