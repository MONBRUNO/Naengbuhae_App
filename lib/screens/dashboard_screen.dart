import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/ingredient_repo.dart';
import '../state/fridge_context.dart';
import '../state/guest_mode.dart';
import '../utils/theme_colors.dart';
import '../widgets/login_required.dart';
import '../utils/expiry.dart';
import '../widgets/donut_chart.dart';
import '../widgets/fridge_selector.dart';
import 'ingredient_edit_screen.dart';
import 'meal_plan_screen.dart';
import 'recipes_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

// 웹의 Home.tsx에 대응. 대시보드: 상태 통계, 빠른 추가, 기능 바로가기, 임박 알림, 식재료 미리보기.
class DashboardScreen extends StatefulWidget {
  // 전체보기 클릭 시 식재료 탭으로 전환 (MainScaffold에서 주입).
  final VoidCallback? onSeeAllIngredients;
  const DashboardScreen({super.key, this.onSeeAllIngredients});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _ingredients = [];

  @override
  void initState() {
    super.initState();
    _fetch();
    // 냉장고 바뀌면 자동 새로고침
    FridgeContext.selected.addListener(_fetch);
  }

  @override
  void dispose() {
    FridgeContext.selected.removeListener(_fetch);
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await IngredientRepo.list(fridgeId: FridgeContext.selectedId);
      if (res.statusCode != 200) {
        setState(() => _error = '조회 실패 (${res.statusCode})');
        return;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      setState(() => _ingredients = data.cast<Map<String, dynamic>>());
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetch,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(_error!)),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: _fetch, child: const Text('다시 시도'))),
        ],
      );
    }

    final sorted = [..._ingredients]..sort((a, b) =>
        calculateDDay(a['expirationDate']?.toString()).compareTo(calculateDDay(b['expirationDate']?.toString())));
    final dangerCount = sorted.where((i) => getExpiryStatus(calculateDDay(i['expirationDate']?.toString())) == ExpiryStatus.danger).length;
    final warningCount = sorted.where((i) => getExpiryStatus(calculateDDay(i['expirationDate']?.toString())) == ExpiryStatus.warning).length;
    final safeCount = sorted.where((i) => getExpiryStatus(calculateDDay(i['expirationDate']?.toString())) == ExpiryStatus.safe).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: const [
            Text('냉장고', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            FridgeSelectorButton(),
          ],
        ),
        const SizedBox(height: 4),
        Text('총 ${_ingredients.length}개 식재료 보관 중',
            style: TextStyle(color: context.subTextColor, fontSize: 13)),
        const SizedBox(height: 16),
        if (_ingredients.isNotEmpty) _statusSummary(dangerCount, warningCount, safeCount),
        const SizedBox(height: 16),
        _quickAddButton(),
        const SizedBox(height: 16),
        _featureGrid(),
        if (dangerCount + warningCount > 0) ...[
          const SizedBox(height: 16),
          _expiryAlert(dangerCount, warningCount),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('식재료 목록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            GestureDetector(
              onTap: () => widget.onSeeAllIngredients?.call(),
              child: Text(
                '전체보기',
                style: TextStyle(fontSize: 13, color: context.subTextColor, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          _emptyState()
        else
          ...sorted.take(10).map(_ingredientTile),
      ],
    );
  }

  Widget _statusSummary(int danger, int warning, int safe) {
    final segments = <DonutSegment>[
      if (danger > 0) DonutSegment(danger.toDouble(), statusColor(ExpiryStatus.danger)),
      if (warning > 0) DonutSegment(warning.toDouble(), statusColor(ExpiryStatus.warning)),
      if (safe > 0) DonutSegment(safe.toDouble(), statusColor(ExpiryStatus.safe)),
    ];

    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF3B0764), Color(0xFF500724)] // purple-950, pink-950
              : const [Color(0xFFFAF5FF), Color(0xFFFDF2F8)], // purple-50 → pink-50
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF6B21A8) : const Color(0xFFE9D5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('식재료 상태', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('현재 냉장고 상태를 확인하세요',
                        style: TextStyle(fontSize: 11, color: context.subTextColor)),
                  ],
                ),
              ),
              const Icon(Icons.trending_up, color: Color(0xFF9333EA), size: 20), // purple-600
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              DonutChart(segments: segments),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    if (danger > 0) _statusRow(danger, ExpiryStatus.danger,
                        isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2)),
                    if (warning > 0) _statusRow(warning, ExpiryStatus.warning,
                        isDark ? const Color(0xFF422006) : const Color(0xFFFEFCE8)),
                    if (safe > 0) _statusRow(safe, ExpiryStatus.safe,
                        isDark ? const Color(0xFF052E16) : const Color(0xFFF0FDF4)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusRow(int count, ExpiryStatus s, Color bg) {
    final c = statusColor(s);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(statusLabel(s), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            Text('$count개', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _quickAddButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const IngredientEditScreen()),
          );
          if (added == true) _fetch();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: context.accentColor,
          foregroundColor: context.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('식재료 추가하기', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _featureGrid() {
    final isDark = context.isDark;
    return Row(
      children: [
        Expanded(child: _featureCard('레시피 추천', LucideIcons.chefHat,
            isDark ? const Color(0xFF431407) : const Color(0xFFFFF7ED),
            isDark ? const Color(0xFF9A3412) : const Color(0xFFFED7AA),
            const Color(0xFFEA580C), () {
          if (GuestMode.currentlyGuest) {
            LoginRequired.show(context, featureName: '레시피 추천');
            return;
          }
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecipesScreen()));
        })),
        const SizedBox(width: 12),
        Expanded(child: _featureCard('식단 추천', LucideIcons.calendar,
            isDark ? const Color(0xFF052E16) : const Color(0xFFF0FDF4),
            isDark ? const Color(0xFF166534) : const Color(0xFFBBF7D0),
            const Color(0xFF16A34A), () {
          if (GuestMode.currentlyGuest) {
            LoginRequired.show(context, featureName: '식단 추천');
            return;
          }
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MealPlanScreen()));
        })),
      ],
    );
  }

  Widget _featureCard(String title, IconData icon, Color bg, Color border, Color iconColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _expiryAlert(int danger, int warning) {
    final msg = danger > 0
        ? '유통기한이 지난 식재료가 $danger개 있어요'
        : '유통기한이 임박한 식재료가 $warning개 있어요';
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(msg, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: context.hintTextColor),
          const SizedBox(height: 12),
          Text('등록된 식재료가 없습니다', style: TextStyle(color: context.hintTextColor)),
          const SizedBox(height: 4),
          Text('첫 식재료를 추가해보세요!', style: TextStyle(color: context.hintTextColor, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _ingredientTile(Map<String, dynamic> item) {
    final days = calculateDDay(item['expirationDate']?.toString());
    final s = getExpiryStatus(days);
    final c = statusColor(s);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item['name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(formatDDay(days),
                          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['quantity']}${item['unit']} · ${item['category']} · ${item['storage']}',
                  style: TextStyle(fontSize: 12, color: context.subTextColor),
                ),
              ],
            ),
          ),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}
