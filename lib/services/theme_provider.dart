import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isColorBlindMode = false;
  double _textScaleFactor = 1.0;

  ThemeMode get themeMode => _themeMode;
  bool get isColorBlindMode => _isColorBlindMode;
  double get textScaleFactor => _textScaleFactor;

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void toggleColorBlindMode(bool value) {
    _isColorBlindMode = value;
    notifyListeners();
  }

  void setTextScaleFactor(double value) {
    _textScaleFactor = value;
    notifyListeners();
  }
}
