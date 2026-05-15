import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/local_ingredient_store.dart';

// 게스트 → 로그인 전환 시점에 로컬에 쌓인 식재료를 서버로 옮기는 헬퍼.
// 로그인/회원가입 직후 호출.
class IngredientMigration {
  // 옮길 게 없으면 false 반환 (다이얼로그 띄울 필요 없음).
  static Future<bool> hasLocalData() async {
    final count = await LocalIngredientStore.count();
    return count > 0;
  }

  // 사용자에게 묻고 옮긴다. 옮기지 않기로 선택하면 로컬 데이터는 그대로 둔다
  // (다시 게스트로 돌아왔을 때 보이도록). 옮긴 뒤엔 로컬 정리.
  static Future<void> promptAndMigrate(BuildContext context) async {
    final count = await LocalIngredientStore.count();
    if (count == 0) return;

    if (!context.mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('기존 식재료를 옮길까요?'),
        content: Text('비로그인 상태에서 추가한 식재료 $count개가 있어요.\n계정으로 옮기시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니요'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('옮기기'),
          ),
        ],
      ),
    );
    if (agreed != true) return;

    final items = await LocalIngredientStore.list();
    // 서버로 보낼 때는 로컬 id/createdAt/fridgeId 제거 — 서버가 새로 발급.
    final payload = items.map((e) {
      final m = Map<String, dynamic>.from(e);
      m.remove('id');
      m.remove('createdAt');
      m.remove('fridgeId');
      return m;
    }).toList();

    try {
      final res = await ApiClient.post('/api/ingredients/import', body: {
        'items': payload,
      });
      if (res.statusCode == 200) {
        await LocalIngredientStore.clear();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('식재료 $count개를 옮겼어요')),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이전 실패 (${res.statusCode}) — 로컬 데이터는 유지됩니다')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이전 실패 — 로컬 데이터는 유지됩니다')),
      );
    }
  }
}
