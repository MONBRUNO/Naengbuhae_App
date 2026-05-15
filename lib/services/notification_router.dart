import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/ingredient_repo.dart';
import '../screens/fridge_management_screen.dart';
import '../screens/ingredient_edit_screen.dart';
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
  // 형식:
  //   "ingredient:{id}" → 해당 식재료 수정 화면까지 직행 (이미 삭제됐으면 목록 탭으로 폴백)
  //   "ingredients" / "expiry" → 식재료 탭
  //   "meal" → 식단 추천
  //   "fridge" → 냉장고 관리
  static void route(String? key) {
    if (key == null) return;
    if (key.startsWith('ingredient:')) {
      final id = int.tryParse(key.substring('ingredient:'.length));
      if (id != null) {
        _openIngredient(id);
        return;
      }
    }
    switch (key) {
      // 로컬 유통기한 알림 / FCM 식재료 일괄 삭제 — 식재료 탭으로
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

  // 식재료 id로 목록을 가져와 해당 항목 수정 화면까지 push.
  // 가족이 비워서 이미 사라졌으면 목록 탭으로 폴백.
  static Future<void> _openIngredient(int id) async {
    try {
      final res = await IngredientRepo.list();
      if (res.statusCode == 200) {
        final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
            .cast<Map<String, dynamic>>();
        final item = list.where((e) => e['id'] == id).firstOrNull;
        if (item != null) {
          _push(IngredientEditScreen(existing: item));
          return;
        }
      }
    } catch (_) {
      // 네트워크 실패 — 폴백
    }
    TabIndex.select(_ingredientsTabIndex);
  }

  static void _push(Widget screen) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }
}
