import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// 게스트 모드 전용 로컬 식재료 저장소.
// 서버 응답과 같은 모양(JSON Map 배열)으로 SharedPreferences에 저장 — 화면 코드는 그대로 사용 가능.
// id는 -1, -2, ... 음수로 발급해서 나중에 서버 id와 절대 충돌하지 않게 한다.
class LocalIngredientStore {
  static const _kKey = 'guest_ingredients';
  static const _kNextIdKey = 'guest_ingredients_next_id';

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  static Future<int> count() async {
    final items = await list();
    return items.length;
  }

  static Future<Map<String, dynamic>> add(Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    final nextId = (prefs.getInt(_kNextIdKey) ?? -1);
    final now = DateTime.now().toIso8601String();
    final row = <String, dynamic>{
      ...body,
      'id': nextId,
      'createdAt': now,
      // 게스트는 단일 가상 냉장고만 — fridgeId는 기록만 하고 의미 없음.
      'fridgeId': -1,
    };
    items.add(row);
    await _save(items);
    await prefs.setInt(_kNextIdKey, nextId - 1);
    return row;
  }

  static Future<bool> update(int id, Map<String, dynamic> body) async {
    final items = await list();
    final idx = items.indexWhere((e) => e['id'] == id);
    if (idx < 0) return false;
    final old = items[idx];
    items[idx] = {...old, ...body, 'id': id};
    await _save(items);
    return true;
  }

  static Future<bool> delete(int id) async {
    final items = await list();
    final before = items.length;
    items.removeWhere((e) => e['id'] == id);
    if (items.length == before) return false;
    await _save(items);
    return true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
    await prefs.remove(_kNextIdKey);
  }

  static Future<void> _save(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(items));
  }
}
