import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'recipe_detail_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

// 웹의 Recipes.tsx에 대응. "전체"와 "만들 수 있는" 두 탭.
// 만들 수 있는 = 추천 API에서 매칭 재료 1개 이상.
class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final futures = await Future.wait([
        ApiClient.get('/api/recipes'),
        ApiClient.get('/api/recipes/recommendations'),
      ]);
      if (futures[0].statusCode != 200 || futures[1].statusCode != 200) {
        setState(() => _error = '레시피 조회 실패');
        return;
      }
      final all = (jsonDecode(utf8.decode(futures[0].bodyBytes)) as List).cast<Map<String, dynamic>>();
      final recs = (jsonDecode(utf8.decode(futures[1].bodyBytes)) as List).cast<Map<String, dynamic>>();
      setState(() {
        _all = all;
        _matches = recs.where((m) {
          final has = (m['hasIngredients'] as List?) ?? [];
          return has.isNotEmpty;
        }).toList()
          ..sort((a, b) => ((b['matchRate'] ?? 0) as num).compareTo((a['matchRate'] ?? 0) as num));
      });
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('레시피'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          tabs: [
            const Tab(text: '전체 레시피'),
            Tab(text: '만들 수 있는 (${_matches.length})'),
          ],
        ),
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
    return TabBarView(
      controller: _tabController,
      children: [
        _allList(),
        _matchList(),
      ],
    );
  }

  Widget _allList() {
    if (_all.isEmpty) return const Center(child: Text('등록된 레시피가 없습니다', style: TextStyle(color: Colors.grey)));
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _recipeCard(_all[i], null),
      ),
    );
  }

  Widget _matchList() {
    if (_matches.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('만들 수 있는 요리가 없습니다.\n식재료를 추가하면 추천이 시작됩니다.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _matches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final m = _matches[i];
          final recipe = (m['recipe'] as Map).cast<String, dynamic>();
          return _recipeCard(recipe, m);
        },
      ),
    );
  }

  Widget _recipeCard(Map<String, dynamic> recipe, Map<String, dynamic>? match) {
    final matchRate = match?['matchRate'];
    final has = (match?['hasIngredients'] as List?)?.cast<String>() ?? const [];
    final missing = (match?['missingIngredients'] as List?)?.cast<String>() ?? const [];
    final warnings = (recipe['allergyWarnings'] as List?)?.cast<String>() ?? const [];

    Color matchColor = const Color(0xFF22C55E);
    if (matchRate != null) {
      final n = (matchRate as num).toInt();
      if (n < 50) {
        matchColor = const Color(0xFFEF4444);
      } else if (n < 100) {
        matchColor = const Color(0xFFFF9500);
      }
    }

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecipeDetailScreen(recipe: recipe, match: match),
        ));
        _fetch();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
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
                      Text(recipe['name']?.toString() ?? '',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${recipe['category'] ?? ''} · ${recipe['cookingTime'] ?? '-'}분 · ${recipe['servings'] ?? '-'}인분 · ${recipe['difficulty'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (matchRate != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: matchColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$matchRate%',
                        style: TextStyle(color: matchColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('알레르기 ${warnings.join(", ")}',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            if (has.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: has.map((s) => _chip(s, _accentGreen, Colors.black)).toList()),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: missing.map((s) => _chip('-$s', const Color(0xFFFEE2E2), const Color(0xFFB91C1C))).toList()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
