import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 사용자 선택 테마 모드(light/dark)를 SharedPreferences에 저장.
// MaterialApp이 ValueNotifier를 listen해서 themeMode를 반영한다.
// (system 모드 제거 — 라이트/다크 명시 선택만. 기본 라이트)
class ThemeModePref {
  static const _kKey = 'theme_mode';

  static final ValueNotifier<ThemeMode> notifier = ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    final mode = _fromString(raw);
    notifier.value = mode;
    // 기존 'system' 저장값 마이그레이션 — light/dark로 확정 저장
    if (raw == 'system' || raw == null) {
      await prefs.setString(_kKey, _toString(mode));
    }
  }

  static Future<void> set(ThemeMode mode) async {
    notifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, _toString(mode));
  }

  static ThemeMode _fromString(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  static String _toString(ThemeMode mode) {
    return mode == ThemeMode.dark ? 'dark' : 'light';
  }
}
