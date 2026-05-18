import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'guest_mode.dart';

// 전역 냉장고 컨텍스트.
// 어느 냉장고를 보고 있는지는 앱 전체에서 공유돼야 함 (홈/식재료/우선순위/추가 등 모두 같은 냉장고 기준).
// ValueNotifier로 노출 → 화면들이 ValueListenableBuilder로 listen.
class FridgeContext {
  static const _kSelectedFridgeIdKey = 'selected_fridge_id';

  // 게스트 모드에서 쓰는 단일 가상 냉장고. id는 'guest' (서버 UUID와 절대 충돌하지 않음).
  static const Map<String, dynamic> _guestFridge = {
    'id': 'guest',
    'name': '내 냉장고',
    'isOwner': true,
    'members': [],
  };

  // 내가 멤버인 냉장고 목록 (id, name, ownerUsername, isOwner, members 등)
  static final ValueNotifier<List<Map<String, dynamic>>> fridges =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  // 현재 선택된 냉장고. null이면 아직 로드 전 또는 빈 상태.
  static final ValueNotifier<Map<String, dynamic>?> selected =
      ValueNotifier<Map<String, dynamic>?>(null);

  // 백엔드 Fridge가 UUID로 마이그레이션됨 — id는 문자열.
  static String? get selectedId => selected.value?['id'] as String?;

  // 앱 시작 시 한 번 호출 (로그인 후 MainScaffold initState 등).
  static Future<void> load() async {
    // 게스트는 서버 호출 없이 가상 냉장고 1개만 들고 다닌다.
    if (await GuestMode.isGuest()) {
      fridges.value = [_guestFridge];
      selected.value = _guestFridge;
      return;
    }
    try {
      final res = await ApiClient.get('/api/fridges');
      if (res.statusCode != 200) return;
      final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
      fridges.value = list;

      // 이전에 선택했던 냉장고 복원 (있으면), 없으면 첫 번째
      final prefs = await SharedPreferences.getInstance();
      // 과거 int(Long) id 시절 저장값이 남아있을 수 있어 getString 실패 시 정리.
      String? savedId;
      try {
        savedId = prefs.getString(_kSelectedFridgeIdKey);
      } catch (_) {
        await prefs.remove(_kSelectedFridgeIdKey);
      }
      Map<String, dynamic>? toSelect;
      if (savedId != null) {
        toSelect = list.where((f) => f['id'] == savedId).firstOrNull;
      }
      toSelect ??= list.isNotEmpty ? list.first : null;
      selected.value = toSelect;
    } catch (_) {
      // 네트워크 실패 시 빈 상태 유지 — 화면에서 빈 상태 안내
    }
  }

  // 선택 변경 (드롭다운/시트에서 클릭).
  static Future<void> select(Map<String, dynamic> fridge) async {
    selected.value = fridge;
    final id = fridge['id'];
    if (id is String) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelectedFridgeIdKey, id);
    }
  }

  // 로그아웃/탈퇴 시 호출.
  static Future<void> clear() async {
    fridges.value = [];
    selected.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSelectedFridgeIdKey);
  }

  // 냉장고 추가/이름변경/삭제/가입 등 변경 후 호출해서 목록 새로고침.
  // 가능하면 selected를 유지하되, 그 냉장고가 없어졌으면 첫 번째로 전환.
  static Future<void> refresh() async {
    final currentId = selectedId;
    await load();
    if (currentId != null) {
      final still = fridges.value.where((f) => f['id'] == currentId).firstOrNull;
      if (still != null) {
        selected.value = still;
      }
    }
  }
}
