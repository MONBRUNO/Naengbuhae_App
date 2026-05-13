import 'package:flutter/material.dart';

import '../api/api_client.dart';

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

  Future<void> _addMissingToShopping() async {
    final missing = (widget.match?['missingIngredients'] as List?)?.cast<String>() ?? const [];
    if (missing.isEmpty) {
      _snack('부족한 재료가 없습니다');
      return;
    }
    setState(() => _adding = true);
    int ok = 0;
    int fail = 0;
    for (final name in missing) {
      final res = await ApiClient.post('/api/shopping-list', body: {
        'name': name,
        'quantity': 1.0,
        'unit': '개',
      });
      if (res.statusCode == 200) {
        ok++;
      } else {
        fail++;
      }
    }
    if (mounted) setState(() => _adding = false);
    _snack('장보기에 추가: 성공 $ok / 실패 $fail');
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
              _badge(r['category']?.toString() ?? '', Colors.black, Colors.white),
              _badge('${r['cookingTime'] ?? '-'}분', const Color(0xFFF5F5F5), Colors.black),
              _badge('${r['servings'] ?? '-'}인분', const Color(0xFFF5F5F5), Colors.black),
              _badge(r['difficulty']?.toString() ?? '', const Color(0xFFF5F5F5), Colors.black),
              if (match?['matchRate'] != null)
                _badge('${match!['matchRate']}% 매칭', _accentGreen, Colors.black),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
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
                color: const Color(0xFFF5F5F5),
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
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.black),
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
                        decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text('${e.key + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
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
                color: const Color(0xFFF5F5F5),
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
