import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../utils/theme_colors.dart';
import 'shopping_screen.dart';

// AI 추천 결과 단일 상세 — 기존 RecipeDetailScreen과 유사한 layout이지만 AI 응답 데이터(즉석) 기반.
// AI 응답엔 quantity/unit/step 없어 일부 섹션만 표시. 장보기 일괄 추가 흐름 동일.
class AiRecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  const AiRecipeDetailScreen({super.key, required this.recipe});

  @override
  State<AiRecipeDetailScreen> createState() => _AiRecipeDetailScreenState();
}

class _AiRecipeDetailScreenState extends State<AiRecipeDetailScreen> {
  bool _adding = false;

  // "신선한 채소 (루꼴라, 시금치 등): 활용법..." 같은 자유 형식 → ":" or "(" 앞부분.
  String _parseName(String text) => text.split(RegExp(r'[:\(（]'))[0].trim();
  String _parseDetail(String text) =>
      text.contains(':') ? text.substring(text.indexOf(':') + 1).trim() : '';

  Future<void> _addToShopping() async {
    if (_adding) return;
    final additional =
        (widget.recipe['additional_ingredients'] as List?)?.cast<String>() ??
            const [];
    final items = additional
        .map(_parseName)
        .where((n) => n.isNotEmpty)
        .map((n) => {'name': n, 'quantity': 1, 'unit': '개'})
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('추가할 재료가 없어요')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('재료 ${items.length}개를 장보기에 추가할까요?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items
                .map((i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('· ${i['name']}',
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('추가')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _adding = true);
    try {
      final res = await ApiClient.post('/api/shopping-list/bulk-add',
          body: {'items': items});
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('장보기에 ${items.length}개 항목을 추가했어요')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('추가 실패 (${res.statusCode})')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('서버 연결 실패')));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recipe;
    final additional =
        (rec['additional_ingredients'] as List?)?.cast<String>() ?? const [];
    final healthBenefits = rec['health_benefits']?.toString() ?? '';
    final recipeTip = rec['recipe_tip']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(rec['dish_name']?.toString() ?? '레시피'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // AI 추천 뱃지
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCDFF00),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 14, color: Color(0xFF1A3300)),
                      SizedBox(width: 4),
                      Text('AI 추천',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A3300))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('냉장고 식재료 기반으로 만든 맞춤 추천',
                      style: TextStyle(
                          fontSize: 12, color: context.subTextColor)),
                ),
              ],
            ),
          ),

          // 필요한 재료
          if (additional.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('필요한 재료',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...additional.map((text) {
              final name = _parseName(text);
              final detail = _parseDetail(text);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(detail,
                          style: TextStyle(
                              fontSize: 12, color: context.subTextColor)),
                    ],
                  ],
                ),
              );
            }),

            // 액션 버튼 — 재료 바로 밑 (RecipeDetailScreen과 동일 패턴)
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _adding ? null : _addToShopping,
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: Text(
                      _adding
                          ? '추가 중...'
                          : '재료 ${additional.length}개 장보기에 추가',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ShoppingScreen())),
                    icon: const Icon(Icons.shopping_cart, size: 18),
                    label: const Text('장보기 리스트 보기',
                        style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: context.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // 효능 / 추천 이유
          if (healthBenefits.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('효능 / 추천 이유',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(healthBenefits,
                style: const TextStyle(fontSize: 14, height: 1.5)),
          ],

          // 조리 팁
          if (recipeTip.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('조리 팁',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Text('💡 $recipeTip',
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }
}
