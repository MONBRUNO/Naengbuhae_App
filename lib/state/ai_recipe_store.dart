import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// AI 추천 결과를 SharedPreferences에 누적 저장 (웹의 aiRecipeStore.ts와 동일 정책).
// 한 번 받은 추천이 페이지 이탈로 날아가지 않도록 보존.
// 즐겨찾기 토글/개별 삭제 지원. 식별자(id)는 클라이언트에서 생성.

class SavedAiRecipe {
  final String id;
  final String dishName;
  final List<String> additionalIngredients;
  final String healthBenefits;
  final String recipeTip;
  final bool favorite;
  final int createdAt;

  const SavedAiRecipe({
    required this.id,
    required this.dishName,
    required this.additionalIngredients,
    required this.healthBenefits,
    required this.recipeTip,
    required this.favorite,
    required this.createdAt,
  });

  factory SavedAiRecipe.fromJson(Map<String, dynamic> j) => SavedAiRecipe(
        id: j['id']?.toString() ?? '',
        dishName: j['dish_name']?.toString() ?? '',
        additionalIngredients:
            (j['additional_ingredients'] as List?)?.cast<String>() ?? const [],
        healthBenefits: j['health_benefits']?.toString() ?? '',
        recipeTip: j['recipe_tip']?.toString() ?? '',
        favorite: j['favorite'] == true,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dish_name': dishName,
        'additional_ingredients': additionalIngredients,
        'health_benefits': healthBenefits,
        'recipe_tip': recipeTip,
        'favorite': favorite,
        'createdAt': createdAt,
      };

  SavedAiRecipe copyWith({bool? favorite}) => SavedAiRecipe(
        id: id,
        dishName: dishName,
        additionalIngredients: additionalIngredients,
        healthBenefits: healthBenefits,
        recipeTip: recipeTip,
        favorite: favorite ?? this.favorite,
        createdAt: createdAt,
      );
}

class AiRecipeStore {
  static const String _key = 'ai-recipes';

  static Future<List<SavedAiRecipe>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<String, dynamic>>()
          .map(SavedAiRecipe.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // 새 추천 결과를 기존 목록 맨 앞에 prepend. 같은 dish_name이라도 그냥 누적.
  static Future<List<SavedAiRecipe>> saveAll(
      List<Map<String, dynamic>> recipes) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    final newOnes = recipes.asMap().entries.map((e) {
      final r = e.value;
      return SavedAiRecipe(
        id: 'ai-$now-${e.key}',
        dishName: r['dish_name']?.toString() ?? '',
        additionalIngredients:
            (r['additional_ingredients'] as List?)?.cast<String>() ?? const [],
        healthBenefits: r['health_benefits']?.toString() ?? '',
        recipeTip: r['recipe_tip']?.toString() ?? '',
        favorite: false,
        createdAt: now,
      );
    }).toList();
    final merged = [...newOnes, ...existing];
    await prefs.setString(
        _key, jsonEncode(merged.map((r) => r.toJson()).toList()));
    return merged;
  }

  static Future<SavedAiRecipe?> getOne(String id) async {
    final all = await getAll();
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  static Future<SavedAiRecipe?> toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    final idx = all.indexWhere((r) => r.id == id);
    if (idx < 0) return null;
    all[idx] = all[idx].copyWith(favorite: !all[idx].favorite);
    await prefs.setString(
        _key, jsonEncode(all.map((r) => r.toJson()).toList()));
    return all[idx];
  }

  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    all.removeWhere((r) => r.id == id);
    await prefs.setString(
        _key, jsonEncode(all.map((r) => r.toJson()).toList()));
  }
}
