import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/fridge_context.dart';
import '../widgets/fridge_selector.dart';

const _accentGreen = Color(0xFFCDFF00);

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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF7FEE7), Color(0xFFFEFCE8)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD9F99D)),
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
        else
          ...members.map(_memberRow),
        const SizedBox(height: 20),

        // 자주 추가한 식재료 TOP
        const Text('자주 추가한 식재료',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (topAdded.isEmpty)
          _emptyCard('아직 추가 기록이 없어요')
        else
          ..._rankedList(topAdded, const Color(0xFF16A34A)),
        const SizedBox(height: 20),

        // 자주 비운 식재료 TOP
        const Text('자주 비운 식재료',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (topRemoved.isEmpty)
          _emptyCard('아직 비움 기록이 없어요')
        else
          ..._rankedList(topRemoved, const Color(0xFFEA580C)),
      ],
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
        color: const Color(0xFFF9FAFB),
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
          color: const Color(0xFFF9FAFB),
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
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
      ),
    );
  }
}
