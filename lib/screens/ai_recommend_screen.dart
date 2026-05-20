import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/ingredient_repo.dart';
import '../state/fridge_context.dart';
import '../utils/theme_colors.dart';
import 'ai_recipe_detail_screen.dart';

// 웹 Recipes.tsx의 AIRecommendModal과 동등한 흐름을 앱에서 풀스크린으로 제공.
// Step 1(식재료) → Step 2(스타일) → 로딩 → 결과 리스트 → 단일 결과 상세.
// 백엔드 POST /api/recipes/ai-recommendations 호출, AI 서버 /api/recommend 프록시.

enum _AiStep { selectIngredients, selectStyles, loading, results, error }

class _CuisineStyle {
  final String id;
  final String label;
  final String emoji;
  const _CuisineStyle(this.id, this.label, this.emoji);
}

const List<_CuisineStyle> _kStyles = [
  _CuisineStyle('korean', '한식', '🍚'),
  _CuisineStyle('chinese', '중식', '🥢'),
  _CuisineStyle('japanese', '일식', '🍣'),
  _CuisineStyle('western', '양식', '🍝'),
  _CuisineStyle('southeast', '동남아식', '🍜'),
  _CuisineStyle('indian', '인도식', '🍛'),
  _CuisineStyle('fusion', '퓨전', '✨'),
  _CuisineStyle('diet', '다이어트', '🥗'),
  _CuisineStyle('soup', '국/탕/찌개', '🍲'),
  _CuisineStyle('snack', '간식/디저트', '🧁'),
];

class AiRecommendScreen extends StatefulWidget {
  const AiRecommendScreen({super.key});

  @override
  State<AiRecommendScreen> createState() => _AiRecommendScreenState();
}

class _AiRecommendScreenState extends State<AiRecommendScreen> {
  _AiStep _step = _AiStep.selectIngredients;
  List<Map<String, dynamic>> _ingredients = [];
  bool _loadingIngredients = true;
  final Set<String> _selectedIngredients = {};
  final Set<String> _selectedStyles = {};
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    try {
      final res = await IngredientRepo.list(fridgeId: FridgeContext.selectedId);
      if (res.statusCode == 200) {
        final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
            .cast<Map<String, dynamic>>();
        setState(() {
          _ingredients = list;
          _loadingIngredients = false;
        });
      } else {
        setState(() => _loadingIngredients = false);
      }
    } catch (_) {
      setState(() => _loadingIngredients = false);
    }
  }

  Future<void> _runRecommend() async {
    setState(() {
      _step = _AiStep.loading;
      _error = null;
      _results = [];
    });
    try {
      final stylesLabels = _selectedStyles
          .map((id) => _kStyles.firstWhere((s) => s.id == id).label)
          .toList();
      final res = await ApiClient.post('/api/recipes/ai-recommendations', body: {
        'ingredients': _selectedIngredients.toList(),
        'styles': stylesLabels,
      });
      if (res.statusCode != 200) {
        setState(() {
          _error = res.statusCode == 503
              ? 'AI 서버에 연결할 수 없습니다.'
              : res.statusCode == 429
                  ? '요청이 너무 많아요. 잠시 후 다시 시도해주세요.'
                  : '추천 실패 (${res.statusCode})';
          _step = _AiStep.error;
        });
        return;
      }
      final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
      setState(() {
        _results = list;
        _step = _AiStep.results;
      });
    } catch (_) {
      setState(() {
        _error = '서버 연결 실패';
        _step = _AiStep.error;
      });
    }
  }

  // 결과 카드 미리보기에서 재료 이름만 짧게 보여주기 위한 파서. 상세 처리는 AiRecipeDetailScreen이 함.
  String _parseIngredientName(String text) {
    return text.split(RegExp(r'[:\(（]'))[0].trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.auto_awesome, size: 20),
          const SizedBox(width: 6),
          Text(_appBarTitle()),
        ]),
      ),
      body: _buildBody(),
    );
  }

  String _appBarTitle() {
    switch (_step) {
      case _AiStep.selectIngredients:
        return 'AI 레시피 추천';
      case _AiStep.selectStyles:
        return 'AI 레시피 추천';
      case _AiStep.loading:
        return 'AI 분석 중';
      case _AiStep.results:
        return 'AI 추천 결과';
      case _AiStep.error:
        return 'AI 레시피 추천';
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case _AiStep.selectIngredients:
        return _buildStep1();
      case _AiStep.selectStyles:
        return _buildStep2();
      case _AiStep.loading:
        return _buildLoading();
      case _AiStep.results:
        return _buildResults();
      case _AiStep.error:
        return _buildError();
    }
  }

  // ── Step 1: 식재료 선택 ──
  Widget _buildStep1() {
    if (_loadingIngredients) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _stepIndicator(1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('사용할 식재료를 선택하세요',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('중복 선택 가능 · ${_selectedIngredients.length}개 선택됨',
                  style: TextStyle(fontSize: 11, color: context.subTextColor)),
            ],
          ),
        ),
        Expanded(
          child: _ingredients.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('등록된 식재료가 없어요.\n식재료를 먼저 추가해주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.subTextColor)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: _ingredients.length,
                  itemBuilder: (_, i) {
                    final name = _ingredients[i]['name']?.toString() ?? '';
                    final selected = _selectedIngredients.contains(name);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedIngredients.remove(name);
                        } else {
                          _selectedIngredients.add(name);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFCDFF0030)
                              : context.cardBg,
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFCDFF00)
                                : context.borderColor,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? const Color(0xFF3D5A00) : context.textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (selected)
                              const Positioned(
                                top: 2,
                                right: 2,
                                child: Icon(Icons.check_circle,
                                    size: 14, color: Color(0xFF7A9600)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // 다음 버튼
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedIngredients.isEmpty
                    ? null
                    : () => setState(() => _step = _AiStep.selectStyles),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: context.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('다음', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 2: 스타일 선택 ──
  Widget _buildStep2() {
    return Column(
      children: [
        _stepIndicator(2),
        // 이전 step 선택 재료 미리보기 (웹과 동일 패턴)
        if (_selectedIngredients.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('선택한 재료 (${_selectedIngredients.length}개)',
                    style: TextStyle(fontSize: 11, color: context.subTextColor)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedIngredients
                      .map((n) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: context.cardBg,
                              border: Border.all(color: context.borderColor),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(n,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('원하는 요리 스타일을 선택하세요',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('중복 선택 가능 · 선택 없으면 전체 스타일 추천',
                  style: TextStyle(fontSize: 11, color: context.subTextColor)),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.2,
            ),
            itemCount: _kStyles.length,
            itemBuilder: (_, i) {
              final s = _kStyles[i];
              final selected = _selectedStyles.contains(s.id);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _selectedStyles.remove(s.id);
                  } else {
                    _selectedStyles.add(s.id);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFCDFF0030) : context.cardBg,
                    border: Border.all(
                      color: selected ? const Color(0xFFCDFF00) : context.borderColor,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(s.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? const Color(0xFF3D5A00) : context.textColor,
                            )),
                      ),
                      if (selected)
                        const Icon(Icons.check, size: 16, color: Color(0xFF7A9600)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '⏱️ AI 분석은 1~3분 정도 걸려요. 잠시만 기다려주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: context.isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _step = _AiStep.selectIngredients),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('이전', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _runRecommend,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentColor,
                          foregroundColor: context.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('AI 추천 받기',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 로딩 ──
  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('AI가 분석 중입니다... (최대 3분)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('공공데이터 + Gemini를 거쳐 추천이 만들어져요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.subTextColor)),
          ],
        ),
      ),
    );
  }

  // ── 결과 리스트 ──
  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('추천 결과가 없어요.',
                style: TextStyle(color: context.subTextColor)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _step = _AiStep.selectIngredients),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final rec = _results[i];
        final additional =
            (rec['additional_ingredients'] as List?)?.cast<String>() ?? const [];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AiRecipeDetailScreen(recipe: rec),
            ),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cardBg,
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(rec['dish_name']?.toString() ?? '',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    Icon(Icons.chevron_right, color: context.subTextColor),
                  ],
                ),
                if (additional.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '추가 재료: ${additional.map(_parseIngredientName).join(', ')}',
                    style: TextStyle(fontSize: 12, color: context.subTextColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if ((rec['health_benefits']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(rec['health_benefits']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 에러 ──
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(_error ?? '오류가 발생했습니다',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => _step = _AiStep.selectStyles),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step indicator (1/2) ──
  Widget _stepIndicator(int currentStep) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          _stepDot(1, currentStep >= 1, '식재료 선택',
              subText: currentStep >= 2 && _selectedIngredients.isNotEmpty
                  ? '${_selectedIngredients.length}개 선택됨'
                  : '사용할 재료 고르기'),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: currentStep >= 2 ? const Color(0xFFCDFF00) : context.borderColor,
            ),
          ),
          _stepDot(2, currentStep >= 2, '스타일 선택', subText: '요리 스타일 고르기'),
        ],
      ),
    );
  }

  Widget _stepDot(int n, bool active, String label, {required String subText}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFCDFF00) : context.cardBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF1A3300) : context.subTextColor,
              )),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? context.textColor : context.subTextColor,
                )),
            Text(subText,
                style: TextStyle(fontSize: 9, color: context.subTextColor)),
          ],
        ),
      ],
    );
  }
}
