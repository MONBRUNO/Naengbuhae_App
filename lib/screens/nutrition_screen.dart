import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../utils/format.dart';

// 웹의 NutritionAnalysis.tsx 단순화 버전.
// 백엔드는 식재료별 영양 데이터를 주지 않아서, 사용자 권장 칼로리 + 식재료 개수만 표시.
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _ingredients = [];

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
      final futures = await Future.wait([
        ApiClient.get('/user/me'),
        ApiClient.get('/api/ingredients'),
      ]);
      if (futures[0].statusCode != 200 || futures[1].statusCode != 200) {
        setState(() => _error = '조회 실패');
        return;
      }
      setState(() {
        _profile = jsonDecode(utf8.decode(futures[0].bodyBytes)) as Map<String, dynamic>;
        _ingredients = (jsonDecode(utf8.decode(futures[1].bodyBytes)) as List).cast<Map<String, dynamic>>();
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
      appBar: AppBar(title: const Text('영양 분석')),
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
    final p = _profile;
    if (p == null) return const Center(child: Text('프로필이 없습니다'));

    final allergies = p['allergies']?.toString() ?? '';
    final allergyList = allergies.split(RegExp(r'[,\s]+')).where((s) => s.trim().isNotEmpty).toList();

    final categoryCount = <String, int>{};
    for (final i in _ingredients) {
      final c = i['category']?.toString() ?? '기타';
      categoryCount[c] = (categoryCount[c] ?? 0) + 1;
    }
    final totalCount = _ingredients.length;
    final allergyIngredients = _ingredients.where((i) {
      final w = (i['allergyWarnings'] as List?) ?? [];
      return w.isNotEmpty;
    }).toList();

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // 영양 요약 카드 (CDFF00 그라데이션)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFCDFF00), Color(0xFFB8E600)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 8),
                    Text('나의 영양 요약',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                if (p['recommendedCalories'] != null) ...[
                  Text('${formatThousands(p['recommendedCalories'] as num)} kcal',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${p['dietGoal'] ?? ''} · ${p['activityLevel'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _summaryBox('식재료', '${_ingredients.length}개')),
                    const SizedBox(width: 8),
                    Expanded(child: _summaryBox('분류', '${categoryCount.length}종')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 식재료 분포
          const Text('식재료 분포', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (totalCount == 0)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('등록된 식재료가 없습니다', style: TextStyle(color: Colors.grey))))
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: categoryCount.entries.map((e) {
                  final ratio = e.value / totalCount;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text('${e.value}개 (${(ratio * 100).toStringAsFixed(0)}%)',
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 6,
                            backgroundColor: Colors.white,
                            valueColor: const AlwaysStoppedAnimation(Color(0xFFCDFF00)),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 알레르기 매칭 식재료
          if (allergyIngredients.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber, color: Color(0xFFEF4444)),
                      SizedBox(width: 8),
                      Text('알레르기 주의 식재료', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB91C1C))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...allergyIngredients.map((i) {
                    final w = ((i['allergyWarnings'] as List?) ?? const []).cast<String>();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(i['name']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(child: Text('← ${w.join(", ")}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)))),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // 알레르기 등록 정보
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('내가 등록한 알레르기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (allergyList.isEmpty)
                  const Text('등록된 알레르기 정보가 없습니다',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: allergyList.map((a) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Text(a, style: const TextStyle(fontSize: 12)),
                    )).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
