import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/guest_mode.dart';

// 인앱 알림 미확인 개수를 전역 ValueNotifier로 관리.
// - ProfileScreen 배지가 listen — FCM 도착이나 read-all 시 즉시 반영
// - FcmService.onMessage가 push 도착 시 increment 호출
// - NotificationCenterScreen 진입 시 read-all 후 0으로 reset
class UnreadNotificationCount {
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  // 서버에서 가져온 값으로 동기화. 로그인 직후 / 앱 포커스 복귀 시 호출.
  static Future<void> refresh() async {
    if (GuestMode.currentlyGuest) {
      notifier.value = 0;
      return;
    }
    try {
      final res = await ApiClient.get('/api/notifications/unread-count');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final count = data['count'];
      notifier.value = count is num ? count.toInt() : 0;
    } catch (_) {
      // 네트워크 실패는 무시 — 다음 진입 시 다시 시도
    }
  }

  // FCM foreground 도착 시 +1. 인앱 DB에는 AppNotificationService가 이미 저장했음.
  static void increment() {
    notifier.value = notifier.value + 1;
  }

  // 알림 센터에서 read-all 호출 후 reset.
  static void reset() {
    notifier.value = 0;
  }
}
