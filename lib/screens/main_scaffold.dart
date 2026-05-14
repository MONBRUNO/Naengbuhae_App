import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../services/notification_service.dart';
import '../state/fridge_context.dart';
import 'dashboard_screen.dart';
import 'ingredients_screen.dart';
import 'login_screen.dart';
import 'priority_screen.dart';
import 'profile_screen.dart';
import 'shopping_screen.dart';

// 웹의 Root.tsx에 대응. 5개 탭 + 하단 네비. IndexedStack으로 탭 전환 시 상태 유지.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;
  StreamSubscription<void>? _loggedOutSub;

  @override
  void initState() {
    super.initState();
    // 어느 탭에서든 401/refresh 실패가 발생하면 로그인 화면으로
    _loggedOutSub = ApiClient.onLoggedOut.listen((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
    // 냉장고 목록 + 현재 선택된 냉장고 로드 (전역 상태)
    FridgeContext.load();
    // 앱 시작 시 식재료 한 번 fetch해서 유통기한 알림 예약 (사용자가 식재료 탭을 안 열어도 동작하도록)
    _prefetchForNotifications();
  }

  Future<void> _prefetchForNotifications() async {
    try {
      final res = await ApiClient.get('/api/ingredients');
      if (res.statusCode != 200) return;
      final items = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
      await NotificationService.rescheduleExpiryNotifications(items);
    } catch (_) {
      // 네트워크 실패해도 무시 — 다음 fetch에서 갱신됨
    }
  }

  @override
  void dispose() {
    _loggedOutSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(onSeeAllIngredients: () => setState(() => _index = 1)),
          const IngredientsScreen(),
          const PriorityScreen(),
          const ShoppingScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

// 웹 Root.tsx의 하단 네비와 동일: lucide 아이콘, 활성=black, 비활성=gray-400.
class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _BottomNav({required this.index, required this.onChanged});

  static const _items = [
    (LucideIcons.house, '홈'),
    (LucideIcons.package, '식재료'),
    (LucideIcons.circleAlert, '우선순위'),
    (LucideIcons.shoppingCart, '장보기'),
    (LucideIcons.user, '마이'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final (icon, label) = _items[i];
              final active = i == index;
              final color = active ? Colors.black : const Color(0xFF9CA3AF);
              return Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 24, color: color),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
