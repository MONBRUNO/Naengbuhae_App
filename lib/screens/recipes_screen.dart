import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/ai_recipe_store.dart';
import '../utils/theme_colors.dart';
import 'ai_recipe_detail_screen.dart';
import 'ai_recommend_screen.dart';
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
  // 추천 API 원본 (이미 매칭률 내림차순 정렬). 만들수있는/즐겨찾기 탭은 이 위에서 필터.
  List<Map<String, dynamic>> _recommended = [];
  // SharedPreferences에 저장된 AI 추천 결과 — 전체 탭 맨 위에 노출.
  List<SavedAiRecipe> _aiRecipes = [];

  List<Map<String, dynamic>> get _matches => _recommended
      .where((m) => ((m['hasIngredients'] as List?) ?? const []).isNotEmpty)
      .toList();
  List<Map<String, dynamic>> get _favorites => _recommended
      .where((m) => (m['recipe'] is Map) && (m['recipe'] as Map)['favorite'] == true)
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetch();
    _loadAiRecipes();
  }

  Future<void> _loadAiRecipes() async {
    final list = await AiRecipeStore.getAll();
    if (!mounted) return;
    setState(() => _aiRecipes = list);
  }

  Future<void> _removeAi(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('이 AI 추천을 삭제할까요?'),
        content: Text(name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    await AiRecipeStore.remove(id);
    await _loadAiRecipes();
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
        _recommended = recs.toList()
          ..sort((a, b) => ((b['matchRate'] ?? 0) as num).compareTo((a['matchRate'] ?? 0) as num));
      });
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 즐겨찾기 토글 — 백엔드 응답으로 새 상태 받아 _recommended와 _all 모두 동기화.
  Future<void> _toggleFavorite(int recipeId) async {
    try {
      final res = await ApiClient.post('/api/recipes/$recipeId/favorite/toggle');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newState = data['favorite'] == true;
      setState(() {
        for (final m in _recommended) {
          final r = m['recipe'];
          if (r is Map && r['id'] == recipeId) r['favorite'] = newState;
        }
        for (final r in _all) {
          if (r['id'] == recipeId) r['favorite'] = newState;
        }
      });
    } catch (_) {
      // 무시 — UX상 silent 실패
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('레시피'),
        actions: [
          IconButton(
            tooltip: 'AI 추천',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiRecommendScreen()),
              );
              // AI 추천 화면에서 새 결과 저장될 수 있으니 돌아오면 다시 로드
              await _loadAiRecipes();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: context.textColor,
          labelColor: context.textColor,
          unselectedLabelColor: context.subTextColor,
          tabs: [
            const Tab(text: '전체'),
            Tab(text: '만들 수 있는 (${_matches.length})'),
            Tab(text: '즐겨찾기 (${_favorites.length})'),
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
        _favoriteList(),
      ],
    );
  }

  Widget _favoriteList() {
    final favs = _favorites;
    if (favs.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('즐겨찾기한 레시피가 없어요.\n레시피 카드의 하트를 눌러 저장해보세요.',
            textAlign: TextAlign.center, style: TextStyle(color: context.subTextColor)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: favs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final m = favs[i];
          final recipe = (m['recipe'] as Map).cast<String, dynamic>();
          return _recipeCard(recipe, m);
        },
      ),
    );
  }

  Widget _allList() {
    if (_all.isEmpty && _aiRecipes.isEmpty) {
      return Center(
          child: Text('등록된 레시피가 없습니다',
              style: TextStyle(color: context.subTextColor)));
    }
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_fetch(), _loadAiRecipes()]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_aiRecipes.isNotEmpty) ...[
            _aiRecipesSection(),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          ..._all.expand((r) => [_recipeCard(r, null), const SizedBox(height: 12)]),
        ],
      ),
    );
  }

  // localStorage(SharedPreferences) 기반 AI 추천 리스트 — 한 번 받으면 안 사라짐.
  Widget _aiRecipesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7A9600)),
            const SizedBox(width: 6),
            Text('AI 추천 레시피 (${_aiRecipes.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ..._aiRecipes.map((rec) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AiRecipeDetailScreen(recipeId: rec.id),
                          ),
                        );
                        await _loadAiRecipes(); // 즐겨찾기 토글 등 반영
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFCDFF00),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome,
                                      size: 10, color: Color(0xFF1A3300)),
                                  SizedBox(width: 2),
                                  Text('AI',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1A3300))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(rec.dishName,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (rec.favorite)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.favorite,
                                    size: 14, color: Colors.red),
                              ),
                            Icon(Icons.chevron_right,
                                size: 18, color: context.subTextColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 16, color: context.subTextColor),
                    onPressed: () => _removeAi(rec.id, rec.dishName),
                    tooltip: '삭제',
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _matchList() {
    final list = _matches;
    if (list.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('만들 수 있는 요리가 없습니다.\n식재료를 추가하면 추천이 시작됩니다.',
            textAlign: TextAlign.center, style: TextStyle(color: context.subTextColor)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final m = list[i];
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
          color: context.cardBg,
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
                          style: TextStyle(fontSize: 12, color: context.subTextColor)),
                    ],
                  ),
                ),
                if (matchRate != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: matchColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$matchRate%',
                        style: TextStyle(color: matchColor, fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  const SizedBox(width: 4),
                ],
                // 하트 — 카드 탭과 분리 (InkWell의 자식 GestureDetector로 처리)
                GestureDetector(
                  onTap: () => _toggleFavorite(recipe['id'] as int),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      recipe['favorite'] == true ? Icons.favorite : Icons.favorite_border,
                      color: recipe['favorite'] == true
                          ? const Color(0xFFEF4444)
                          : context.hintTextColor,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.isDark ? const Color(0xFF450A0A) : Colors.red.shade100,
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
              Wrap(spacing: 4, runSpacing: 4, children: missing.map((s) => _chip('-$s',
                  context.isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2),
                  context.isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))).toList()),
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
