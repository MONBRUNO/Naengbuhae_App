import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../utils/theme_colors.dart';

const _accentGreen = Color(0xFFCDFF00);

// 웹의 RecipeDetail.tsx에 대응. 재료/조리법/영양정보 + 부족 재료를 장보기 리스트에 추가.
class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final Map<String, dynamic>? match;
  const RecipeDetailScreen({super.key, required this.recipe, this.match});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _adding = false;
  // 같은 레시피를 다시 봐도 안 묻도록 메모리에 기록 (앱 종료 시 초기화 — 그 정도면 충분)
  static final Set<String> _dismissedAskIds = {};

  @override
  void initState() {
    super.initState();
    // 빌드 직후 부족 재료 안내 다이얼로그 자동 노출
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  void _maybeAsk() {
    final id = widget.recipe['id']?.toString();
    if (id == null) return;
    if (_dismissedAskIds.contains(id)) return;
    final missing = _missingItems();
    if (missing.isEmpty) return;
    _showAskDialog(missing);
  }

  // 부족 재료 이름 + 레시피 측 quantity/unit 같이 묶어서 반환.
  List<Map<String, dynamic>> _missingItems() {
    final missing = (widget.match?['missingIngredients'] as List?)?.cast<String>() ?? const [];
    if (missing.isEmpty) return const [];
    final ingredients = (widget.recipe['ingredients'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return missing.map((name) {
      final m = ingredients.firstWhere(
        (e) => e['name']?.toString() == name,
        orElse: () => {'name': name, 'quantity': 1.0, 'unit': '개'},
      );
      return {
        'name': m['name'],
        'quantity': (m['quantity'] as num?)?.toDouble() ?? 1.0,
        'unit': (m['unit']?.toString().isNotEmpty ?? false) ? m['unit'] : '개',
      };
    }).toList();
  }

  Future<void> _showAskDialog(List<Map<String, dynamic>> missing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('부족한 재료 ${missing.length}개가 있어요'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('장보기 리스트에 한 번에 추가할까요?',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.boxBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: missing.map((m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(m['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        Text('${m['quantity']}${m['unit']}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('괜찮아요')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.accentColor,
              foregroundColor: Colors.black,
            ),
            child: const Text('장보기에 추가'),
          ),
        ],
      ),
    );
    final id = widget.recipe['id']?.toString();
    if (id != null) _dismissedAskIds.add(id); // 닫든 추가든 다시 안 묻기
    if (result == true) await _bulkAdd(missing);
  }

  Future<void> _addMissingToShopping() async {
    final missing = _missingItems();
    if (missing.isEmpty) {
      _snack('부족한 재료가 없어요');
      return;
    }
    await _bulkAdd(missing);
  }

  Future<void> _bulkAdd(List<Map<String, dynamic>> missing) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final res = await ApiClient.post('/api/shopping-list/bulk-add', body: {
        'items': missing,
      });
      if (res.statusCode == 200) {
        _snack('장보기에 ${missing.length}개 추가했어요');
      } else {
        _snack('추가 실패 (${res.statusCode})');
      }
    } catch (_) {
      _snack('서버 연결 실패');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final match = widget.match;
    final ingredients = (r['ingredients'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final steps = (r['steps'] as List?)?.cast<String>() ?? const [];
    final nutrition = (r['nutrition'] as Map?)?.cast<String, dynamic>();
    final warnings = (r['allergyWarnings'] as List?)?.cast<String>() ?? const [];
    final has = ((match?['hasIngredients'] as List?)?.cast<String>() ?? const []).toSet();
    final missing = (match?['missingIngredients'] as List?)?.cast<String>() ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(r['name']?.toString() ?? '레시피')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _badge(r['category']?.toString() ?? '',
                  context.isDark ? Colors.white : Colors.black,
                  context.isDark ? Colors.black : Colors.white),
              _badge('${r['cookingTime'] ?? '-'}분', context.cardBg, context.textColor),
              _badge('${r['servings'] ?? '-'}인분', context.cardBg, context.textColor),
              _badge(r['difficulty']?.toString() ?? '', context.cardBg, context.textColor),
              if (match?['matchRate'] != null)
                _badge('${match!['matchRate']}% 매칭', _accentGreen, Colors.black),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('알레르기 주의: ${warnings.join(", ")}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB91C1C)))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('필요한 재료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...ingredients.map((ing) {
            final name = ing['name']?.toString() ?? '';
            final ok = has.contains(name);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: ok ? const Color(0xFF22C55E) : Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name)),
                  Text('${ing['quantity'] ?? ''} ${ing['unit'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _adding ? null : _addMissingToShopping,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text(_adding ? '추가 중...' : '부족한 재료 ${missing.length}개 장보기에 추가'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: context.textColor),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (steps.isNotEmpty) ...[
            const Text('조리 방법', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...steps.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: context.isDark ? Colors.white : Colors.black,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text('${e.key + 1}',
                            style: TextStyle(
                              color: context.isDark ? Colors.black : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 14, height: 1.5))),
                    ],
                  ),
                )),
          ],
          if (nutrition != null) ...[
            const SizedBox(height: 16),
            const Text('영양 정보 (1인분)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _nutritionItem('칼로리', '${nutrition['calories'] ?? '-'} kcal'),
                  _nutritionItem('단백질', '${nutrition['protein'] ?? '-'} g'),
                  _nutritionItem('탄수화물', '${nutrition['carbs'] ?? '-'} g'),
                  _nutritionItem('지방', '${nutrition['fat'] ?? '-'} g'),
                  if (nutrition['sodium'] != null) _nutritionItem('나트륨', '${nutrition['sodium']} mg'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _nutritionItem(String label, String value) {
    return SizedBox(
      width: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
