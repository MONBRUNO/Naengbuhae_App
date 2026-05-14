import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 사용자가 프로필 화면에서 조절하는 알림 설정.
// SharedPreferences에 저장 + ValueNotifier로 노출 → 변경 시 NotificationService가 listen해서 재스케줄.
class NotificationSettings {
  static const _kMasterEnabled = 'notif_master_enabled';
  static const _kExpiryEnabled = 'notif_expiry_enabled';
  static const _kMealEnabled = 'notif_meal_enabled';
  static const _kBreakfastHour = 'notif_breakfast_hour';
  static const _kBreakfastMinute = 'notif_breakfast_minute';
  static const _kLunchHour = 'notif_lunch_hour';
  static const _kLunchMinute = 'notif_lunch_minute';
  static const _kDinnerHour = 'notif_dinner_hour';
  static const _kDinnerMinute = 'notif_dinner_minute';

  // 마스터 토글 (전체 알림 on/off)
  static final ValueNotifier<bool> masterEnabled = ValueNotifier<bool>(true);

  // 유통기한 알림 (매일 아침 9시, D-3부터)
  static final ValueNotifier<bool> expiryEnabled = ValueNotifier<bool>(true);

  // 식단 알림 (각 식사 10분 전)
  static final ValueNotifier<bool> mealEnabled = ValueNotifier<bool>(true);

  static final ValueNotifier<TimeOfDay> breakfastTime =
      ValueNotifier<TimeOfDay>(const TimeOfDay(hour: 8, minute: 0));
  static final ValueNotifier<TimeOfDay> lunchTime =
      ValueNotifier<TimeOfDay>(const TimeOfDay(hour: 12, minute: 30));
  static final ValueNotifier<TimeOfDay> dinnerTime =
      ValueNotifier<TimeOfDay>(const TimeOfDay(hour: 19, minute: 0));

  // 앱 시작 시 한 번 호출 (main.dart에서)
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    masterEnabled.value = prefs.getBool(_kMasterEnabled) ?? true;
    expiryEnabled.value = prefs.getBool(_kExpiryEnabled) ?? true;
    mealEnabled.value = prefs.getBool(_kMealEnabled) ?? true;
    breakfastTime.value = TimeOfDay(
      hour: prefs.getInt(_kBreakfastHour) ?? 8,
      minute: prefs.getInt(_kBreakfastMinute) ?? 0,
    );
    lunchTime.value = TimeOfDay(
      hour: prefs.getInt(_kLunchHour) ?? 12,
      minute: prefs.getInt(_kLunchMinute) ?? 30,
    );
    dinnerTime.value = TimeOfDay(
      hour: prefs.getInt(_kDinnerHour) ?? 19,
      minute: prefs.getInt(_kDinnerMinute) ?? 0,
    );
  }

  static Future<void> setMasterEnabled(bool v) async {
    masterEnabled.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMasterEnabled, v);
  }

  static Future<void> setExpiryEnabled(bool v) async {
    expiryEnabled.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExpiryEnabled, v);
  }

  static Future<void> setMealEnabled(bool v) async {
    mealEnabled.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMealEnabled, v);
  }

  static Future<void> setBreakfastTime(TimeOfDay t) async {
    breakfastTime.value = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBreakfastHour, t.hour);
    await prefs.setInt(_kBreakfastMinute, t.minute);
  }

  static Future<void> setLunchTime(TimeOfDay t) async {
    lunchTime.value = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLunchHour, t.hour);
    await prefs.setInt(_kLunchMinute, t.minute);
  }

  static Future<void> setDinnerTime(TimeOfDay t) async {
    dinnerTime.value = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDinnerHour, t.hour);
    await prefs.setInt(_kDinnerMinute, t.minute);
  }
}
