import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/ingredient_repo.dart';
import '../state/fridge_context.dart';
import '../state/tab_index.dart';
import '../utils/expiry.dart';
import '../utils/theme_colors.dart';
import '../widgets/donut_chart.dart';
import '../widgets/fridge_selector.dart';

// 웹의 Priority.tsx에 대응. 상단 보라-핑크 카드 + 막대 그래프 + 위험도 요약 + 위험/주의/안전 섹션.
class PriorityScreen extends StatefulWidget {
  const PriorityScreen({super.key});

  @override
  State<PriorityScreen> createState() => _PriorityScreenState();
}

class _PriorityScreenState extends State<PriorityScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await IngredientRepo.list(fridgeId: FridgeContext.selectedId);
      if (res.statusCode != 200) {
        setState(() => _error = '조회 실패 (${res.statusCode})');
        return;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      setState(() => _items = data.cast<Map<String, dynamic>>());
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${item['name']}을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await IngredientRepo.delete(item['id'] as int);
    if (res.statusCode == 200) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(onRefresh: _fetch, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Center(child: Text(_error!)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(onPressed: _fetch, child: const Text('다시 시도'))),
      ]);
    }

    final sorted = [..._items]..sort((a, b) => calculateDDay(a['expirationDate']?.toString())
        .compareTo(calculateDDay(b['expirationDate']?.toString())));
    final danger = sorted.where((i) => getExpiryStatus(calculateDDay(i['expirationDate']?.toString())) == ExpiryStatus.danger).toList();
    final warning = sorted.where((i) => getExpiryStatus(calculateDDay(i['expirationDate']?.toString())) == ExpiryStatus.warning).toList();
    final safe = sorted.where((i) => getExpiryStatus(calculateDDay(i['expirationDate']?.toString())) == ExpiryStatus.safe).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: [
        // 헤더
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('소비 우선순위', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            FridgeSelectorButton(),
          ],
        ),
        const SizedBox(height: 4),
        const Text('유통기한 기준으로 우선 소비해야 할 식재료',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        const SizedBox(height: 16),

        // 막대 그래프 카드
        if (_items.isNotEmpty) ...[
          _chartCard(danger.length, warning.length, safe.length),
          const SizedBox(height: 16),
        ],

        // 우선순위 요약
        _summaryAlert(danger.length, warning.length),
        const SizedBox(height: 24),

        // 빈 상태
        if (_items.isEmpty) _emptyState(),

        // 위험
        if (danger.isNotEmpty) ...[
          _sectionTitle('위험', danger.length, ExpiryStatus.danger),
          ...danger.map(_priorityCard),
          const SizedBox(height: 24),
        ],

        // 주의
        if (warning.isNotEmpty) ...[
          _sectionTitle('주의', warning.length, ExpiryStatus.warning),
          ...warning.map(_priorityCard),
          const SizedBox(height: 24),
        ],

        // 안전 (최대 5개)
        if (safe.isNotEmpty) ...[
          _sectionTitle('안전', safe.length, ExpiryStatus.safe),
          ...safe.take(5).map(_priorityCard),
          if (safe.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () => TabIndex.select(1), // 식재료 탭으로 이동
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('외 ${safe.length - 5}개 더 보기',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.skyAccent)),
                    Icon(Icons.chevron_right, size: 16, color: context.skyAccent),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _chartCard(int d, int w, int s) {
    final total = d + w + s;
    final dColor = statusColor(ExpiryStatus.danger);
    final wColor = statusColor(ExpiryStatus.warning);
    final sColor = statusColor(ExpiryStatus.safe);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: context.skyAccent, size: 20),
              const SizedBox(width: 8),
              Text('식재료 위험도 분석',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textColor)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 도넛 차트 + 가운데 총 개수
              SizedBox(
                width: 130, height: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    DonutChart(
                      segments: [
                        DonutSegment(d.toDouble(), dColor),
                        DonutSegment(w.toDouble(), wColor),
                        DonutSegment(s.toDouble(), sColor),
                      ],
                      size: 130,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$total',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const Text('개',
                            style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 통계 요약 — 개수 + 비율 %
              Expanded(
                child: Column(
                  children: [
                    _statBox(d, total, '위험', dColor),
                    const SizedBox(height: 8),
                    _statBox(w, total, '주의', wColor),
                    const SizedBox(height: 8),
                    _statBox(s, total, '안전', sColor),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(int count, int total, String label, Color dotColor) {
    final pct = total == 0 ? 0 : (count * 100 / total).round();
    // 웹 --status-*-bg 처럼 status색 옅은 틴트 (채도 낮게)
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: dotColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: context.subTextColor)),
          const Spacer(),
          Text('$count',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textColor)),
          const SizedBox(width: 4),
          Text('· $pct%',
              style: TextStyle(fontSize: 11, color: context.subTextColor)),
        ],
      ),
    );
  }

  Widget _summaryAlert(int danger, int warning) {
    final text = danger > 0
        ? '긴급: $danger개 식재료 확인 필요'
        : warning > 0
            ? '주의: $warning개 식재료 곧 소비 필요'
            : '안전: 모든 식재료가 양호합니다';
    // 웹 패턴: 다크 카드 + 4px 컬러 좌측바 + 컬러 아이콘
    final accent = danger > 0
        ? context.statusDanger
        : warning > 0
            ? context.statusWarning
            : context.statusSafe;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textColor)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String label, int count, ExpiryStatus s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: statusColor(s), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label ($count)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
          SizedBox(height: 12),
          Text('등록된 식재료가 없습니다', style: TextStyle(color: Color(0xFF9CA3AF))),
          SizedBox(height: 4),
          Text('식재료를 추가하고 관리를 시작하세요',
              style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB))),
        ],
      ),
    );
  }

  Widget _priorityCard(Map<String, dynamic> item) {
    final days = calculateDDay(item['expirationDate']?.toString());
    final s = getExpiryStatus(days);
    final c = statusColor(s);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item['name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(formatDDay(days),
                          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('수량: ${item['quantity']}${item['unit']}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                Text('유통기한: ${item['expirationDate']}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                if (days <= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${-days}일 전에 만료되었습니다',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                  )
                else if (days <= 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$days일 후 만료됩니다',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFA16207), fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(item),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
          ),
        ],
      ),
    );
  }
}
