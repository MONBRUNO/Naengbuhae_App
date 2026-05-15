import 'package:flutter/material.dart';

import '../api/auth_storage.dart';
import '../state/fridge_context.dart';
import '../state/guest_mode.dart';
import '../screens/login_screen.dart';

// 게스트가 로그인 필요 기능에 진입하려 할 때 표시하는 다이얼로그.
// 사용자가 '로그인하기'를 누르면 LoginScreen으로 push (게스트 데이터 유지 — 마이그레이션은 로그인 성공 시).
class LoginRequired {
  static Future<void> show(BuildContext context, {required String featureName}) async {
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('로그인이 필요해요'),
        content: Text('$featureName 기능은 로그인 후 사용할 수 있어요.\n지금 추가한 식재료는 로그인하면 그대로 옮겨드릴게요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그인하기'),
          ),
        ],
      ),
    );
    if (goLogin != true) return;
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // 게스트 모드를 끝낼 때 토큰/냉장고 상태도 같이 정리. ProfileScreen의 "로그아웃" 자리에 사용.
  static Future<void> exitGuest(BuildContext context) async {
    await GuestMode.clear();
    await AuthStorage.clear();
    await FridgeContext.clear();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}
