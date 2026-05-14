import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'notification_service.dart';

// FCM 푸시 알림 (멤버/초대 등 서버 트리거 이벤트).
// 백그라운드 메시지 핸들러는 top-level 함수여야 함 (isolate 분리됨).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // 백그라운드는 시스템이 알아서 알림 표시. 추가 처리 필요 없음.
  if (kDebugMode) debugPrint('FCM background: ${message.messageId}');
}

class FcmService {
  static bool _inited = false;

  // Firebase 초기화 + 권한 요청 + 토큰을 서버에 등록.
  // 로그인 직후 또는 앱 시작 시 (로그인 상태일 때) 호출.
  static Future<void> init() async {
    if (_inited) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // google-services.json 미배치 시 여기서 실패 — 알림은 로컬만 동작
      if (kDebugMode) debugPrint('Firebase init skipped: $e');
      return;
    }

    final messaging = FirebaseMessaging.instance;

    // iOS 권한 요청 (Android는 NotificationService에서 별도)
    if (Platform.isIOS) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }

    // 백그라운드 메시지 핸들러
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 포그라운드 메시지 — 로컬 알림으로 띄움 (FCM은 포그라운드에선 자동 표시 안 함)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notif = message.notification;
      final data = message.data;
      final title = notif?.title ?? data['title']?.toString() ?? '냉부해';
      final body = notif?.body ?? data['body']?.toString() ?? '';
      if (body.isEmpty) return;
      NotificationService.showLocal(title: title, body: body);
    });

    // 토큰 갱신 시 서버에 재등록
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registerToken(token);
    });

    _inited = true;
  }

  // 로그인 직후 호출 — 현재 토큰을 서버에 등록.
  static Future<void> registerCurrentToken() async {
    if (!_inited) await init();
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('FCM token fetch failed: $e');
    }
  }

  // 로그아웃 시 호출 — 서버에서 토큰 폐기.
  static Future<void> unregisterCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.delete('/user/fcm-tokens/$token');
    } catch (_) {
      // 네트워크 오류여도 로컬은 어차피 끝 — 무시
    }
  }

  static Future<void> _registerToken(String token) async {
    final platform = Platform.isAndroid ? 'ANDROID' : (Platform.isIOS ? 'IOS' : 'WEB');
    try {
      await ApiClient.post('/user/fcm-tokens', body: {
        'token': token,
        'platform': platform,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('FCM token register failed: $e');
    }
  }
}
