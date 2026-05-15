import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/fridge_context.dart';
import '../utils/theme_colors.dart';
import '../widgets/donut_chart.dart';
import '../widgets/fridge_selector.dart';

const _accentGreen = Color(0xFFCDFF00);

// 도넛 차트 슬라이스 색깔 — TOP 항목 순서대로 할당.
const _pieGreens = [
  Color(0xFF16A34A), Color(0xFF22C55E), Color(0xFF4ADE80),
  Color(0xFF86EFAC), Color(0xFFBBF7D0),
];
const _pieOranges = [
  Color(0xFFEA580C), Color(0xFFF97316), Color(0xFFFB923C),
  Color(0xFFFDBA74), Color(0xFFFED7AA),
];

// 가족 활동 통계 화면 — 현재 선택된 냉장고 기준으로 멤버별 추가/소비 카운트 + 자주 추가/비우는 식재료 TOP 5.
class FamilyActivityScreen extends StatefulWidget {
  const FamilyActivityScreen({super.key});

  @override
  State<FamilyActivityScreen> createState() => _FamilyActivityScreenState();
}

class _FamilyActivityScreenState extends State<FamilyActivityScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _fetch();
    FridgeContext.selected.addListener(_fetch);
  }

  @override
  void dispose() {
    FridgeContext.selected.removeListener(_fetch);
    super.dispose();
  }

  Future<void> _fetch() async {
    final fridgeId = FridgeContext.selectedId;
    if (fridgeId == null) {
      setState(() {
        _loading = false;
        _error = '선택된 냉장고가 없어요';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/fridges/$fridgeId/activity-stats?days=$_days');
      if (res.statusCode != 200) {
        setState(() => _error = '조회 실패 (${res.statusCode})');
        return;
      }
      setState(() => _stats = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
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
        title: const Text('가족 활동', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: FridgeSelectorButton())],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: _fetch, child: const Text('다시 시도'))),
      ]);
    }
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    final members = (stats['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final topAdded = (stats['topAdded'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final topRemoved = (stats['topRemoved'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final fridgeName = stats['fridgeName']?.toString() ?? '';

    final totalAdded = members.fold<int>(0, (s, m) => s + (m['added'] as int? ?? 0));
    final totalRemoved = members.fold<int>(0, (s, m) => s + (m['removed'] as int? ?? 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // 헤더 — 냉장고 이름 + 기간 요약
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
              Text(fridgeName,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 4),
              Text('지난 $_days일간 활동',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _summaryStat('추가', totalAdded, const Color(0xFF16A34A))),
                  Expanded(child: _summaryStat('비움', totalRemoved, const Color(0xFFEA580C))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 기간 선택
        Row(
          children: [
            _periodChip('7일', 7),
            const SizedBox(width: 8),
            _periodChip('30일', 30),
            const SizedBox(width: 8),
            _periodChip('90일', 90),
          ],
        ),
        const SizedBox(height: 20),

        // 멤버별 활동
        const Text('멤버별 활동',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (members.isEmpty)
          _emptyCard('아직 활동 기록이 없어요')
        else ...[
          _memberBarChart(members),
          const SizedBox(height: 8),
          ...members.map(_memberRow),
        ],
        const SizedBox(height: 20),

        // 자주 추가한 식재료 TOP
        const Text('자주 추가한 식재료',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (topAdded.isEmpty)
          _emptyCard('아직 추가 기록이 없어요')
        else ...[
          _donutSection(topAdded, _pieGreens),
          const SizedBox(height: 8),
          ..._rankedList(topAdded, const Color(0xFF16A34A)),
        ],
        const SizedBox(height: 20),

        // 자주 비운 식재료 TOP
        const Text('자주 비운 식재료',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (topRemoved.isEmpty)
          _emptyCard('아직 비움 기록이 없어요')
        else ...[
          _donutSection(topRemoved, _pieOranges),
          const SizedBox(height: 8),
          ..._rankedList(topRemoved, const Color(0xFFEA580C)),
        ],
      ],
    );
  }

  // 멤버별 추가/비움 그룹 막대 차트 — 한 멤버당 추가(녹색) + 비움(주황) 두 막대.
  Widget _memberBarChart(List<Map<String, dynamic>> members) {
    final maxValue = members.fold<int>(0, (m, e) {
      final added = (e['added'] as int? ?? 0);
      final removed = (e['removed'] as int? ?? 0);
      return [added, removed, m].reduce((a, b) => a > b ? a : b);
    });
    final scale = maxValue == 0 ? 1.0 : maxValue.toDouble();
    const chartHeight = 120.0;
    const maxBarHeight = 80.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 범례
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: const [
              _LegendDot(color: Color(0xFF16A34A), label: '추가'),
              SizedBox(width: 12),
              _LegendDot(color: Color(0xFFEA580C), label: '비움'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: members.map((m) {
                final added = m['added'] as int? ?? 0;
                final removed = m['removed'] as int? ?? 0;
                final name = (m['name']?.toString() ?? m['username']?.toString() ?? '').isEmpty
                    ? '-'
                    : (m['name']?.toString() ?? m['username']!.toString());
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar(added, scale, maxBarHeight, const Color(0xFF16A34A)),
                          const SizedBox(width: 4),
                          _bar(removed, scale, maxBarHeight, const Color(0xFFEA580C)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(int value, double scale, double maxH, Color color) {
    final h = (maxH * value / scale).clamp(0.0, maxH);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        const SizedBox(height: 2),
        Container(
          width: 16,
          height: value == 0 ? 4 : h.clamp(6, maxH),
          decoration: BoxDecoration(
            color: value == 0 ? const Color(0xFFE5E7EB) : color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  // TOP N 항목을 도넛 + 색깔 범례로 시각화. 아래쪽 상세 리스트와 결합.
  Widget _donutSection(List<Map<String, dynamic>> items, List<Color> palette) {
    final segments = <DonutSegment>[];
    for (var i = 0; i < items.length; i++) {
      final count = (items[i]['count'] as num? ?? 0).toDouble();
      segments.add(DonutSegment(count, palette[i % palette.length]));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DonutChart(segments: segments, size: 110),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(items.length, (i) {
                final item = items[i];
                final count = (item['count'] as num? ?? 0).toInt();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: palette[i % palette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item['name']?.toString() ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      Text('$count회',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        const SizedBox(height: 4),
        Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
        const Text('개', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ],
    );
  }

  Widget _periodChip(String label, int days) {
    final selected = _days == days;
    return GestureDetector(
      onTap: () {
        setState(() => _days = days);
        _fetch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accentGreen : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 13,
          color: selected ? Colors.black : const Color(0xFF6B7280),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        )),
      ),
    );
  }

  Widget _memberRow(Map<String, dynamic> m) {
    final added = m['added'] as int? ?? 0;
    final removed = m['removed'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.person_outline, size: 18, color: Color(0xFF6B7280)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(m['name']?.toString() ?? m['username']?.toString() ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          _countBadge('+$added', const Color(0xFF16A34A)),
          const SizedBox(width: 6),
          _countBadge('-$removed', const Color(0xFFEA580C)),
        ],
      ),
    );
  }

  Widget _countBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
    );
  }

  List<Widget> _rankedList(List<Map<String, dynamic>> items, Color barColor) {
    final maxCount = items.map((i) => (i['count'] as num? ?? 0).toInt()).reduce((a, b) => a > b ? a : b);
    return List.generate(items.length, (i) {
      final item = items[i];
      final count = (item['count'] as num? ?? 0).toInt();
      final ratio = maxCount == 0 ? 0.0 : count / maxCount;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.boxBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('$count회',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
      );
    });
  }

  Widget _emptyCard(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
      ],
    );
  }
}
