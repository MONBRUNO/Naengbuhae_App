import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/auth_storage.dart';
import '../utils/format.dart';
import '../utils/theme_colors.dart';

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

  // ── AI 영양 검색 (capstone-ai /analyze 프록시) ──
  final TextEditingController _searchController = TextEditingController();
  bool _analyzing = false;
  List<Map<String, dynamic>>? _aiResults;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // /api/nutrition/analyze 호출 — text 또는 file 중 하나. multipart로 전송.
  Future<void> _runAnalyze({String? text, String? filePath}) async {
    setState(() {
      _analyzing = true;
      _aiError = null;
      _aiResults = null;
    });
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/api/nutrition/analyze');
      final token = await AuthStorage.readAccessToken();
      final req = http.MultipartRequest('POST', uri);
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      if (text != null) req.fields['text'] = text;
      if (filePath != null) {
        req.files.add(await http.MultipartFile.fromPath('file', filePath));
      }
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) {
        setState(() {
          _aiError = res.statusCode == 503
              ? 'AI 서버에 연결할 수 없습니다.'
              : res.statusCode == 429
                  ? '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.'
                  : '분석 실패 (${res.statusCode})';
        });
        return;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _aiResults = ((data['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
      });
    } catch (_) {
      setState(() => _aiError = '서버 연결 실패');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _onSearchText() async {
    final q = _searchController.text.trim();
    if (q.isEmpty || _analyzing) return;
    await _runAnalyze(text: q);
  }

  Future<void> _onPickImage() async {
    if (_analyzing) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _runAnalyze(filePath: picked.path);
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
          // 영양 요약 카드 (라이트=CDFF00, 다크=채도 낮춘 라임 그라데이션)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: context.isDark
                    ? const [Color(0xFFF2F3EE), Color(0xFFD8D9D2)]
                    : const [Color(0xFFCDFF00), Color(0xFFB8E600)],
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
              decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
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
                            backgroundColor: context.isDark ? const Color(0xFF374151) : Colors.white,
                            valueColor: AlwaysStoppedAnimation(context.accentColor),
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
                color: context.isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
              ),
              child: Builder(builder: (context) {
                final dark = context.isDark;
                final iconColor =
                    dark ? const Color(0xFFF87171) : const Color(0xFFEF4444);
                final redText =
                    dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, color: iconColor),
                        const SizedBox(width: 8),
                        Text('알레르기 주의 식재료',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: redText)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...allergyIngredients.map((i) {
                      final w = ((i['allergyWarnings'] as List?) ?? const [])
                          .cast<String>();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(i['name']?.toString() ?? '',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: context.textColor)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text('← ${w.join(", ")}',
                                    style: TextStyle(
                                        fontSize: 12, color: redText))),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
            const SizedBox(height: 16),
          ],
          // 알레르기 등록 정보
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(12)),
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
                      decoration: BoxDecoration(
                        color: context.isDark ? const Color(0xFF374151) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(a, style: const TextStyle(fontSize: 12)),
                    )).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // AI 영양 검색 (capstone-ai /analyze 프록시)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: context.cardBg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('다른 음식 영양 검색',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('음식 이름이나 사진으로 영양 정보 검색 (AI 분석, 100g 기준)',
                    style: TextStyle(fontSize: 11, color: context.subTextColor)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      enabled: !_analyzing,
                      decoration: InputDecoration(
                        hintText: '예: 김치찌개',
                        filled: true,
                        fillColor: context.boxBg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _onSearchText(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _analyzing ? null : _onSearchText,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('검색'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _analyzing ? null : _onPickImage,
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('사진으로 분석'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (_analyzing) ...[
                  const SizedBox(height: 10),
                  const Center(child: Text('AI가 분석 중입니다...',
                      style: TextStyle(fontSize: 12, color: Colors.grey))),
                ],
                if (_aiError != null) ...[
                  const SizedBox(height: 8),
                  Text(_aiError!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
                ],
                if (_aiResults != null && _aiResults!.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('분석 결과가 없습니다',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                if (_aiResults != null && _aiResults!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ..._aiResults!.map(_nutritionResultCard),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nutritionResultCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(item['food_name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (item['cat'] != null)
                Text('(${item['cat']})',
                    style: TextStyle(fontSize: 11, color: context.subTextColor)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _nutCell('kcal', '${(item['cal'] as num?)?.round() ?? 0}')),
              Expanded(child: _nutCell('단백질', '${(item['protein'] as num?)?.round() ?? 0}g')),
              Expanded(child: _nutCell('탄수', '${(item['carbohydrate'] as num?)?.round() ?? 0}g')),
              Expanded(child: _nutCell('지방', '${(item['fat'] as num?)?.round() ?? 0}g')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nutCell(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: context.subTextColor)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ],
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
