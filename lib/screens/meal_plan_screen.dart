import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../services/notification_service.dart';
import '../utils/format.dart';
import '../utils/theme_colors.dart';
import '../widgets/bar_chart.dart';
import 'recipes_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

const _daysOfWeek = ['월', '화', '수', '목', '금', '토', '일'];

class _MealPlanItem {
  final String day;
  final String breakfast;
  final String lunch;
  final String dinner;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;

  _MealPlanItem({
    required this.day,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
  });
}

// 웹의 MealPlan.tsx에 대응.
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  bool _loading = true;
  String? _error;
  // 추천 API 응답 (모든 레시피 + 매칭정보). 식단은 이걸로 생성.
  List<Map<String, dynamic>> _matches = [];
  bool _hasIngredients = true;
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.get('/api/recipes/recommendations'),
        ApiClient.get('/api/ingredients'),
      ]);
      if (results[0].statusCode != 200) {
        setState(() => _error = '레시피 조회 실패');
        return;
      }
      final matches = (jsonDecode(utf8.decode(results[0].bodyBytes)) as List).cast<Map<String, dynamic>>();
      final ingredients = (jsonDecode(utf8.decode(results[1].bodyBytes)) as List);
      setState(() {
        _matches = matches;
        _hasIngredients = ingredients.isNotEmpty;
      });
      // 오늘의 식단을 알림에 반영
      final plan = _generateMealPlan();
      final todays = plan.isNotEmpty ? plan.first : null;
      // ignore: unawaited_futures
      NotificationService.rescheduleMealNotifications(
        breakfast: todays?.breakfast,
        lunch: todays?.lunch,
        dinner: todays?.dinner,
      );
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_MealPlanItem> _generateMealPlan() {
    if (_matches.isEmpty) return [];

    // 매칭률 높은 순 정렬 — 만들기 쉬운 레시피가 앞쪽.
    final sorted = _matches.toList()
      ..sort((a, b) =>
          ((b['matchRate'] ?? 0) as num).compareTo((a['matchRate'] ?? 0) as num));
    final allRecipes = sorted
        .map((m) => (m['recipe'] as Map).cast<String, dynamic>())
        .toList();
    if (allRecipes.isEmpty) return [];

    List<Map<String, dynamic>> inCats(List<String> cats) => allRecipes
        .where((r) => cats.contains(r['category']?.toString()))
        .toList();

    // 아침: 간식·음료(가벼운 끼니). 점심·저녁: 밥/면·반찬·기타·샐러드. 적으면 전체로 폴백.
    var breakfastPool = inCats(['간식', '음료']);
    if (breakfastPool.length < 2) breakfastPool = allRecipes;
    var mealPool = inCats(['밥/면', '반찬', '기타', '샐러드']);
    if (mealPool.length < 4) mealPool = allRecipes;

    final plan = <_MealPlanItem>[];
    for (var i = 0; i < _selectedDays; i++) {
      final breakfast = breakfastPool[i % breakfastPool.length];
      // 점심·저녁은 서로 다른 인덱스 — 같은 날 중복 방지 + 요일별 순환
      final lunch = mealPool[(i * 2) % mealPool.length];
      final dinner = mealPool[(i * 2 + 1) % mealPool.length];

      final bn = (breakfast['nutrition'] as Map?)?.cast<String, dynamic>();
      final ln = (lunch['nutrition'] as Map?)?.cast<String, dynamic>();
      final dn = (dinner['nutrition'] as Map?)?.cast<String, dynamic>();

      double sum(String key) =>
          _num(bn?[key]) + _num(ln?[key]) + _num(dn?[key]);

      plan.add(_MealPlanItem(
        day: _daysOfWeek[i % 7],
        breakfast: breakfast['name']?.toString() ?? '-',
        lunch: lunch['name']?.toString() ?? '-',
        dinner: dinner['name']?.toString() ?? '-',
        totalCalories: sum('calories'),
        totalProtein: sum('protein'),
        totalCarbs: sum('carbs'),
        totalFat: sum('fat'),
      ));
    }
    return plan;
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('식단 추천', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _fetch, child: const Text('다시 시도')),
        ],
      ));
    }

    final mealPlan = _generateMealPlan();
    final totalCalories = mealPlan.fold<double>(0, (s, d) => s + d.totalCalories);
    final totalProtein = mealPlan.fold<double>(0, (s, d) => s + d.totalProtein);

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // 부제
          Text('보유 식재료 기반 균형잡힌 식단',
              style: TextStyle(fontSize: 13, color: context.subTextColor)),
          const SizedBox(height: 16),

          // 기간 선택
          Row(
            children: [
              _periodChip('오늘', 1),
              const SizedBox(width: 8),
              _periodChip('3일', 3),
              const SizedBox(width: 8),
              _periodChip('일주일', 7),
            ],
          ),
          const SizedBox(height: 16),

          // 영양 요약 (lime-yellow 그라데이션)
          if (mealPlan.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: context.isDark
                      ? const [Color(0xFF365314), Color(0xFF422006)]
                      : const [Color(0xFFF7FEE7), Color(0xFFFEFCE8)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.isDark ? const Color(0xFF4D7C0F) : const Color(0xFFD9F99D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF4D7C0F)),
                      const SizedBox(width: 8),
                      Text(
                        _selectedDays == 1 ? '오늘 영양 요약' : '$_selectedDays일간 영양 요약',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _summaryStat('총 칼로리', formatThousands(totalCalories), 'kcal', '평균 ${formatThousands(totalCalories / _selectedDays)}kcal/일')),
                      Expanded(child: _summaryStat('총 단백질', '${totalProtein.toInt()}', 'g', '평균 ${(totalProtein / _selectedDays).toInt()}g/일')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 영양소 균형 그래프 (orange-yellow)
          if (mealPlan.isNotEmpty && _selectedDays >= 3) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: context.isDark
                      ? const [Color(0xFF431407), Color(0xFF422006)]
                      : const [Color(0xFFFFF7ED), Color(0xFFFEFCE8)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.isDark ? const Color(0xFF9A3412) : const Color(0xFFFED7AA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('일별 영양소 균형 (g)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  SimpleBarChart(
                    height: 160,
                    items: mealPlan.map((d) => BarItem(
                      d.day,
                      (d.totalProtein + d.totalCarbs + d.totalFat).toInt(),
                      const Color(0xFF8B5CF6),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      _legend('단백질+탄수화물+지방', const Color(0xFF8B5CF6)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 식단표
          if (mealPlan.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.restaurant_outlined, size: 48, color: context.hintTextColor),
                  const SizedBox(height: 12),
                  Text('식단을 생성할 레시피가 부족합니다',
                      style: TextStyle(color: context.hintTextColor)),
                  const SizedBox(height: 4),
                  Text('레시피를 추가하면 식단이 자동 생성돼요',
                      style: TextStyle(fontSize: 12, color: context.hintTextColor)),
                ],
              ),
            )
          else ...[
            const Text('식단표', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...mealPlan.map(_dayCard),
          ],

          // 식재료 없음 안내
          if (!_hasIngredients) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF422006) : const Color(0xFFFEFCE8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.isDark ? const Color(0xFF854D0E) : const Color(0xFFFEF08A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('더 정확한 식단 추천을 위해',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('보유 식재료를 등록하면 맞춤 식단을 추천해드려요',
                      style: TextStyle(fontSize: 11, color: context.subTextColor)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _periodChip(String label, int days) {
    final selected = _selectedDays == days;
    return GestureDetector(
      onTap: () => setState(() => _selectedDays = days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accentGreen : context.cardBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          color: selected ? Colors.black : context.subTextColor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        )),
      ),
    );
  }

  Widget _summaryStat(String label, String value, String unit, String avg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: context.subTextColor)),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: TextStyle(color: context.textColor),
            children: [
              TextSpan(text: value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              TextSpan(text: ' $unit', style: TextStyle(fontSize: 12, color: context.subTextColor)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(avg, style: TextStyle(fontSize: 11, color: context.subTextColor)),
      ],
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: context.subTextColor)),
      ],
    );
  }

  Widget _dayCard(_MealPlanItem day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: context.subTextColor),
              const SizedBox(width: 8),
              Text('${day.day}요일',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${formatThousands(day.totalCalories)}kcal',
                  style: TextStyle(fontSize: 12, color: context.subTextColor)),
            ],
          ),
          const SizedBox(height: 12),
          _mealRow('아침', day.breakfast),
          _mealRow('점심', day.lunch),
          _mealRow('저녁', day.dinner),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.borderColor),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('단백질 ${day.totalProtein.toInt()}g',
                  style: TextStyle(fontSize: 12, color: context.subTextColor)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecipesScreen()),
                ),
                child: Row(
                  children: const [
                    Text('레시피 보기',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mealRow(String label, String meal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 40,
              child: Text(label, style: TextStyle(fontSize: 13, color: context.subTextColor))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(meal, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
