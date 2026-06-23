import 'dart:async';
import 'package:flutter/foundation.dart';

class LogService {
  static final LogService instance = LogService._internal();
  LogService._internal();

  final _logs = <String>[];
  final _controller = StreamController<List<String>>.broadcast();
  final int maxEntries = 2000;

  void add(String? msg) {
    if (msg == null) return;
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $msg';
    _logs.add(line);
    if (_logs.length > maxEntries) _logs.removeRange(0, _logs.length - maxEntries);
    _controller.add(List.unmodifiable(_logs));
  }

  List<String> getAll() => List.unmodifiable(_logs);

  Stream<List<String>> get stream => _controller.stream;

  void clear() {
    _logs.clear();
    _controller.add(List.unmodifiable(_logs));
  }

  String exportText() => _logs.join('\n');

  /// Capture Flutter's debugPrint into this service.
  void captureDebugPrint() {
    final orig = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      try {
        add(message);
      } catch (_) {}
      try {
        orig(message, wrapWidth: wrapWidth);
      } catch (_) {}
    };
  }
}
