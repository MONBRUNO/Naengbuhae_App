import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 사용자 선택 테마 모드(system/light/dark)를 SharedPreferences에 저장.
// MaterialApp이 ValueNotifier를 listen해서 themeMode를 반영한다.
class ThemeModePref {
  static const _kKey = 'theme_mode';

  static final ValueNotifier<ThemeMode> notifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    notifier.value = _fromString(raw);
  }

  static Future<void> set(ThemeMode mode) async {
    notifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, _toString(mode));
  }

  static ThemeMode _fromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
