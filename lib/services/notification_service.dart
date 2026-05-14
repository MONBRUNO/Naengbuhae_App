import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../state/notification_settings.dart';

// 로컬 알림 스케줄링.
// - 유통기한: 매일 오전 9시. 현재 식재료 기준으로 다음 7일치 알림을 미리 예약 (앱 안 켜도 동작).
// - 식단: 사용자 지정 식사 시간 - 10분. 호출 시점의 오늘/이번주 식단 데이터로 예약.
// - FCM foreground 도착 시도 동일 채널로 즉시 표시.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  // 설정 변경 시 즉시 재스케줄 가능하도록 마지막 데이터 캐시 (in-memory).
  // 데이터가 한 번이라도 fetch 됐으면 토글 직후 알림이 바로 반영됨.
  static List<Map<String, dynamic>>? _cachedIngredients;
  static ({String? breakfast, String? lunch, String? dinner})? _cachedMeals;

  // 채널 분리 — 사용자가 OS 설정에서 끄거나 우선순위 다르게 둘 수 있게.
  static const _expiryChannelId = 'expiry_channel';
  static const _mealChannelId = 'meal_channel';
  static const _fcmChannelId = 'fcm_channel';

  // 알림 id 영역 — 충돌 방지 위해 prefix 분리.
  static const int _expiryIdBase = 1000;   // +0..6 = 7일치
  static const int _mealIdBase = 2000;     // +0/+1/+2 = 오늘 아점저
  // FCM은 timestamp 기반 id

  static Future<void> init() async {
    if (_inited) return;

    // 타임존 — zonedSchedule이 로컬 시간을 정확히 다루려면 필요.
    tzdata.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      // 실패 시 UTC fallback — 한국 환경에선 거의 발생 안 함.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    _inited = true;
  }

  // 시스템 권한 요청 (Android 13+ POST_NOTIFICATIONS, iOS 알림 권한).
  static Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final granted = await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
      return granted;
    }
    if (Platform.isAndroid) {
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notif = await impl?.requestNotificationsPermission() ?? false;
      // 정확 알람 권한 (Android 12+) — 거부돼도 inexact으로 떨어뜨릴 수 있어 실패 무시
      await impl?.requestExactAlarmsPermission();
      return notif;
    }
    return true;
  }

  // ===== 유통기한 알림 =====
  // 식재료 변경/조회 직후 호출. 오늘부터 다음 7일치를 미리 예약 — 앱을 안 열어도 동작하게.
  // 각 날짜에 해당하는 임박 식재료(D-0 ~ D-3)를 계산해서 본문에 포함.
  static Future<void> rescheduleExpiryNotifications(
    List<Map<String, dynamic>> ingredients,
  ) async {
    _cachedIngredients = ingredients;
    if (!_inited) await init();

    // 기존 유통기한 알림 7개 모두 cancel
    for (int i = 0; i < 7; i++) {
      await _plugin.cancel(_expiryIdBase + i);
    }

    if (!NotificationSettings.masterEnabled.value ||
        !NotificationSettings.expiryEnabled.value) {
      return;
    }

    final now = tz.TZDateTime.now(tz.local);

    for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
      final target = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + dayOffset,
        9, // 오전 9시
      );
      // 오늘 9시가 이미 지났으면 오늘 알림은 건너뜀
      if (target.isBefore(now)) continue;

      final imminent = _imminentItemsOn(target, ingredients);
      if (imminent.isEmpty) continue;

      final body = _buildExpiryBody(imminent);
      await _plugin.zonedSchedule(
        _expiryIdBase + dayOffset,
        '유통기한 임박 식재료 ${imminent.length}개',
        body,
        target,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _expiryChannelId,
            '유통기한 알림',
            channelDescription: '임박한 식재료를 매일 오전 9시에 알려드립니다',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'expiry',
      );
    }
  }

  // ===== 식단 알림 =====
  // 호출 시점에 알고 있는 오늘 식단으로 아침/점심/저녁을 각각 식사 시간 - 10분에 예약.
  // 메뉴가 null이면 해당 끼니는 예약하지 않음.
  static Future<void> rescheduleMealNotifications({
    String? breakfast,
    String? lunch,
    String? dinner,
  }) async {
    _cachedMeals = (breakfast: breakfast, lunch: lunch, dinner: dinner);
    if (!_inited) await init();

    // 기존 식단 알림 cancel
    for (int i = 0; i < 3; i++) {
      await _plugin.cancel(_mealIdBase + i);
    }

    if (!NotificationSettings.masterEnabled.value ||
        !NotificationSettings.mealEnabled.value) {
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    await _scheduleMealAt(
      idOffset: 0,
      label: '아침',
      menu: breakfast,
      time: NotificationSettings.breakfastTime.value,
      now: now,
    );
    await _scheduleMealAt(
      idOffset: 1,
      label: '점심',
      menu: lunch,
      time: NotificationSettings.lunchTime.value,
      now: now,
    );
    await _scheduleMealAt(
      idOffset: 2,
      label: '저녁',
      menu: dinner,
      time: NotificationSettings.dinnerTime.value,
      now: now,
    );
  }

  // FCM foreground 메시지나 즉시 알림용.
  static Future<void> showLocal({
    required String title,
    required String body,
    String channelId = _fcmChannelId,
    String channelName = '앱 알림',
  }) async {
    if (!_inited) await init();
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> cancelAll() => _plugin.cancelAll();

  // 설정 토글/시간 변경 직후 호출 — 마지막으로 가져온 데이터로 재스케줄.
  // 데이터가 한 번도 없었으면 그냥 cancel만 (다음 fetch에서 자연스럽게 반영됨).
  static Future<void> rescheduleFromCache() async {
    if (_cachedIngredients != null) {
      await rescheduleExpiryNotifications(_cachedIngredients!);
    }
    if (_cachedMeals != null) {
      await rescheduleMealNotifications(
        breakfast: _cachedMeals!.breakfast,
        lunch: _cachedMeals!.lunch,
        dinner: _cachedMeals!.dinner,
      );
    }
  }

  // ===== 내부 헬퍼 =====

  static List<Map<String, dynamic>> _imminentItemsOn(
    tz.TZDateTime when,
    List<Map<String, dynamic>> ingredients,
  ) {
    final list = <Map<String, dynamic>>[];
    for (final item in ingredients) {
      final dateStr = item['expirationDate']?.toString();
      if (dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      final whenDate = DateTime(when.year, when.month, when.day);
      final dDay = date.difference(whenDate).inDays;
      // D-3 ~ D-0 (만료일까지 3일 이하 + 오늘)
      if (dDay >= 0 && dDay <= 3) list.add(item);
    }
    // 임박한 순서대로
    list.sort((a, b) {
      final ad = DateTime.parse(a['expirationDate'].toString());
      final bd = DateTime.parse(b['expirationDate'].toString());
      return ad.compareTo(bd);
    });
    return list;
  }

  static String _buildExpiryBody(List<Map<String, dynamic>> items) {
    final preview = items.take(3).map((i) {
      final name = i['name']?.toString() ?? '';
      final date = DateTime.tryParse(i['expirationDate']?.toString() ?? '');
      if (date == null) return name;
      final today = DateTime.now();
      final d = date.difference(DateTime(today.year, today.month, today.day)).inDays;
      final dLabel = d == 0 ? 'D-day' : (d > 0 ? 'D-$d' : 'D+${-d}');
      return '$name ($dLabel)';
    }).join(', ');
    if (items.length <= 3) return preview;
    return '$preview 외 ${items.length - 3}개';
  }

  static Future<void> _scheduleMealAt({
    required int idOffset,
    required String label,
    required String? menu,
    required dynamic time, // TimeOfDay
    required tz.TZDateTime now,
  }) async {
    if (menu == null || menu.trim().isEmpty || menu == '-') return;

    // 식사 시간 - 10분 = 알림 시각
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(minutes: 10));

    // 이미 지났으면 내일로
    if (when.isBefore(now)) {
      when = when.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        _mealIdBase + idOffset,
        '곧 $label 시간이에요',
        '오늘 $label 식단: $menu',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _mealChannelId,
            '식단 알림',
            channelDescription: '각 식사 10분 전에 추천 식단을 알려드립니다',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'meal',
      );
    } catch (e) {
      // 정확 알람 권한 거부된 경우 inexact으로 fallback
      if (kDebugMode) debugPrint('meal exact alarm fallback: $e');
      await _plugin.zonedSchedule(
        _mealIdBase + idOffset,
        '곧 $label 시간이에요',
        '오늘 $label 식단: $menu',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _mealChannelId,
            '식단 알림',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'meal',
      );
    }
  }
}
