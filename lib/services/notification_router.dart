import 'package:flutter/material.dart';

import '../screens/fridge_management_screen.dart';
import '../screens/meal_plan_screen.dart';
import '../state/tab_index.dart';

// 알림(로컬/FCM) 탭 시 어느 화면을 띄울지 결정.
// 앱 전체에서 공유하는 navigatorKey + tabIndex 상태를 함께 다뤄야 해서 라우팅 헬퍼로 분리.
class NotificationRouter {
  // MaterialApp의 navigatorKey와 연결됨 — main.dart에서 주입.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // 식재료 탭 = 1 (main_scaffold의 IndexedStack 순서: 홈, 식재료, 우선순위, 장보기, 마이)
  static const _ingredientsTabIndex = 1;

  // payload 또는 FCM data의 route 값을 받아 분기.
  static void route(String? key) {
    if (key == null) return;
    switch (key) {
      // 로컬 유통기한 알림 / FCM 식재료 추가·삭제 — 둘 다 식재료 탭으로
      case 'expiry':
      case 'ingredients':
        TabIndex.select(_ingredientsTabIndex);
        break;
      case 'meal':
        _push(const MealPlanScreen());
        break;
      case 'fridge':
        _push(const FridgeManagementScreen());
        break;
    }
  }

  static void _push(Widget screen) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }
}
