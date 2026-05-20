import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/ingredient_repo.dart';
import '../services/notification_service.dart';
import '../state/fridge_context.dart';
import '../state/guest_mode.dart';
import '../utils/expiry.dart';
import '../utils/theme_colors.dart';
import '../widgets/fridge_selector.dart';
import '../widgets/login_required.dart';
import 'ingredient_edit_screen.dart';
import 'nutrition_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

const _categories = ['전체', '채소', '육류', '유제품', '곡물', '해산물', '과일',
    '가공식품', '음료', '조미료', '간식', '기타'];
const _storages = ['전체', '냉장', '냉동', '실온'];

// 식재료별 영양정보 (100g 기준) — 웹 Ingredients.tsx의 nutritionDatabase와 동일 셋.
// 카드/상세 sheet에서 사용량(quantity) 비례로 환산해 표시.
const Map<String, Map<String, double>> _nutritionDb = {
  '당근':    {'calories': 41,  'protein': 0.9,  'carbs': 9.6,  'fat': 0.2},
  '양파':    {'calories': 40,  'protein': 1.1,  'carbs': 9.3,  'fat': 0.1},
  '토마토':  {'calories': 18,  'protein': 0.9,  'carbs': 3.9,  'fat': 0.2},
  '배추':    {'calories': 13,  'protein': 1.2,  'carbs': 2.2,  'fat': 0.2},
  '브로콜리': {'calories': 34,  'protein': 2.8,  'carbs': 6.6,  'fat': 0.4},
  '시금치':  {'calories': 23,  'protein': 2.9,  'carbs': 3.6,  'fat': 0.4},
  '돼지고기': {'calories': 242, 'protein': 27.3, 'carbs': 0,    'fat': 14.0},
  '소고기':  {'calories': 250, 'protein': 26.1, 'carbs': 0,    'fat': 15.4},
  '닭고기':  {'calories': 165, 'protein': 31.0, 'carbs': 0,    'fat': 3.6},
  '닭가슴살': {'calories': 165, 'protein': 31.0, 'carbs': 0,    'fat': 3.6},
  '고등어':  {'calories': 205, 'protein': 18.6, 'carbs': 0,    'fat': 13.9},
  '연어':    {'calories': 208, 'protein': 20.4, 'carbs': 0,    'fat': 13.4},
  '새우':    {'calories': 99,  'protein': 20.9, 'carbs': 0.9,  'fat': 1.7},
  '우유':    {'calories': 61,  'protein': 3.2,  'carbs': 4.8,  'fat': 3.3},
  '요구르트': {'calories': 59,  'protein': 3.5,  'carbs': 4.7,  'fat': 3.3},
  '치즈':    {'calories': 402, 'protein': 25.0, 'carbs': 1.3,  'fat': 33.1},
  '사과':    {'calories': 52,  'protein': 0.3,  'carbs': 13.8, 'fat': 0.2},
  '바나나':  {'calories': 89,  'protein': 1.1,  'carbs': 22.8, 'fat': 0.3},
  '딸기':    {'calories': 32,  'protein': 0.7,  'carbs': 7.7,  'fat': 0.3},
  '쌀':     {'calories': 130, 'protein': 2.7,  'carbs': 28.2, 'fat': 0.3},
  '현미':    {'calories': 111, 'protein': 2.6,  'carbs': 23.5, 'fat': 0.9},
  '귀리':    {'calories': 389, 'protein': 16.9, 'carbs': 66.3, 'fat': 6.9},
  '식빵':    {'calories': 265, 'protein': 8.7,  'carbs': 49.4, 'fat': 3.2},
  'default': {'calories': 150, 'protein': 5,    'carbs': 20,   'fat': 3},
};

Map<String, double> _nutritionOf(String name) =>
    _nutritionDb[name] ?? _nutritionDb['default']!;

enum _SortBy { expiry, name, category }

// 웹의 Ingredients.tsx에 대응. 필터(분류/보관) + 정렬 + 카드 목록.
class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  String _categoryFilter = '전체';
  String _storageFilter = '전체';
  _SortBy _sort = _SortBy.expiry;
  String _searchQuery = '';
  bool _showExpiredOnly = false;
  final TextEditingController _searchController = TextEditingController();

  // 다중 선택 모드. 활성화 시 카드를 탭하면 체크 토글, 상단 액션 바 표시.
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  bool _bulkDeleting = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    FridgeContext.selected.addListener(_fetch);
  }

  @override
  void dispose() {
    FridgeContext.selected.removeListener(_fetch);
    _searchController.dispose();
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
      final items = data.cast<Map<String, dynamic>>();
      setState(() => _items = items);
      // 식재료 갱신 후 유통기한 알림 재스케줄
      // ignore: unawaited_futures
      NotificationService.rescheduleExpiryNotifications(items);
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selectedIds.addAll(_filtered.map((e) => e['id'] as int));
    });
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제하시겠습니까?'),
        content: Text('${_selectedIds.length}개의 식재료를 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _bulkDeleting = true);
    try {
      final ids = _selectedIds.toList();
      final res = await IngredientRepo.bulkDelete(ids);
      if (!mounted) return;
      if (res.statusCode == 200) {
        _exitSelectionMode();
        await _fetch();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('일괄 삭제 실패 (${res.statusCode})')));
      }
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제하시겠습니까?'),
        content: Text('${item['name']}을(를) 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await IngredientRepo.delete(item['id'] as int);
    if (res.statusCode == 200) {
      _fetch();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패 (${res.statusCode})')));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _searchQuery.trim().toLowerCase();
    final list = _items.where((i) {
      if (_categoryFilter != '전체' && i['category']?.toString() != _categoryFilter) return false;
      if (_storageFilter != '전체' && i['storage']?.toString() != _storageFilter) return false;
      if (query.isNotEmpty) {
        final name = (i['name']?.toString() ?? '').toLowerCase();
        if (!name.contains(query)) return false;
      }
      if (_showExpiredOnly) {
        // D-day < 0 = 이미 만료 (오늘 만료는 포함 안 함 — "만료된 것"의 통상 의미)
        if (calculateDDay(i['expirationDate']?.toString()) >= 0) return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case _SortBy.expiry:
        list.sort((a, b) => calculateDDay(a['expirationDate']?.toString())
            .compareTo(calculateDDay(b['expirationDate']?.toString())));
        break;
      case _SortBy.name:
        list.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
        break;
      case _SortBy.category:
        list.sort((a, b) => (a['category']?.toString() ?? '').compareTo(b['category']?.toString() ?? ''));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _fetch, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    final list = _filtered;
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 32, 0, 24),
        children: [
          // 헤더 — 선택 모드면 우측에 "취소" 버튼, 아니면 냉장고 선택
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('식재료 관리', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    if (_selectionMode)
                      TextButton(
                        onPressed: _exitSelectionMode,
                        child: Text('취소',
                            style: TextStyle(color: context.subTextColor, fontWeight: FontWeight.w600)),
                      )
                    else
                      const FridgeSelectorButton(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _selectionMode ? '${_selectedIds.length}개 선택됨' : '총 ${list.length}개',
                  style: TextStyle(fontSize: 13, color: context.subTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_selectionMode) ...[
            // 일괄 액션 바
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _selectAllVisible,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('전체 선택 (${list.length})',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedIds.isEmpty || _bulkDeleting ? null : _bulkDelete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _bulkDeleting ? '삭제 중...' : '${_selectedIds.length}개 삭제',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            // 추가 + 영양 분석 + 선택 모드 진입 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final added = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const IngredientEditScreen()),
                    );
                    if (added == true) _fetch();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: context.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('식재료 추가하기'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (GuestMode.currentlyGuest) {
                          LoginRequired.show(context, featureName: '영양 분석');
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NutritionScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: context.isDark ? const Color(0xFF052E16) : const Color(0xFFF0FDF4),
                        foregroundColor: context.isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: context.isDark ? const Color(0xFF166534) : const Color(0xFFBBF7D0), width: 2),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('영양 분석 보기'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: list.isEmpty ? null : _enterSelectionMode,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: context.cardBg,
                      foregroundColor: context.isDark ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide.none,
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.check_box_outlined, size: 18),
                    label: const Text('선택'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 이름 검색
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: '이름으로 검색',
                prefixIcon: Icon(Icons.search, size: 20, color: context.hintTextColor),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 18, color: context.hintTextColor),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: context.cardBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 카테고리 필터
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _categories[i];
                final selected = c == _categoryFilter;
                return GestureDetector(
                  onTap: () => setState(() => _categoryFilter = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? _accentGreen : context.cardBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(c, style: TextStyle(
                        fontSize: 13,
                        color: selected ? Colors.black : (context.isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280)),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      )),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // 보관 + 정렬
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _storageFilter,
                    decoration: _filterDecoration(),
                    items: _storages.map((s) => DropdownMenuItem(value: s, child: Text('보관: $s'))).toList(),
                    onChanged: (v) => setState(() => _storageFilter = v ?? '전체'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<_SortBy>(
                    initialValue: _sort,
                    decoration: _filterDecoration(),
                    items: const [
                      DropdownMenuItem(value: _SortBy.expiry, child: Text('유통기한순')),
                      DropdownMenuItem(value: _SortBy.name, child: Text('이름순')),
                      DropdownMenuItem(value: _SortBy.category, child: Text('분류순')),
                    ],
                    onChanged: (v) => setState(() => _sort = v ?? _SortBy.expiry),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 만료된 것만 보기 토글
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () => setState(() => _showExpiredOnly = !_showExpiredOnly),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _showExpiredOnly
                      ? (context.isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2))
                      : context.cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _showExpiredOnly
                        ? (context.isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5))
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showExpiredOnly ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: _showExpiredOnly ? const Color(0xFFDC2626) : context.hintTextColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '만료된 것만 보기',
                      style: TextStyle(
                        fontSize: 13,
                        color: _showExpiredOnly ? const Color(0xFFDC2626) : context.subTextColor,
                        fontWeight: _showExpiredOnly ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 목록
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: context.hintTextColor),
                  const SizedBox(height: 12),
                  Text('조건에 맞는 식재료가 없습니다', style: TextStyle(color: context.hintTextColor)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: list
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ingredientCard(item),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _filterDecoration() => InputDecoration(
        filled: true,
        fillColor: context.cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  // 2열 그리드용 컴팩트 카드. 탭 → bottom sheet 상세. 선택 모드면 토글.
  // 웹 Ingredients.tsx `grid grid-cols-2 gap-3`와 동일 패턴 (팀원 디자인 적용).
  Widget _ingredientCard(Map<String, dynamic> item) {
    final days = calculateDDay(item['expirationDate']?.toString());
    final s = getExpiryStatus(days);
    final c = statusColor(s);
    final warnings = (item['allergyWarnings'] as List?)?.cast<String>() ?? const [];
    final id = item['id'] as int;
    final isSelected = _selectedIds.contains(id);

    // 영양 정보는 100g 기준값 그대로 표시. quantity 단위가 "개"/"팩"일 때 g 환산이 부정확해
    // (장보기에서 이관된 항목은 quantity=1로 들어와 거의 다 0으로 떴음) 라벨에 "/100g" 명시.
    final n = _nutritionOf(item['name']?.toString() ?? '');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(id);
        } else {
          _showDetailSheet(item);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _selectionMode && isSelected
              ? (context.isDark ? const Color(0xFF365314) : const Color(0xFFECFCCB))
              : context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: _selectionMode && isSelected
              ? Border.all(color: _accentGreen, width: 2)
              : null,
        ),
        // Row + crossAxisAlignment center → 삭제 버튼이 세로 가운데 정렬됨
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 왼쪽: D-day 뱃지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(formatDDay(days),
                  style: TextStyle(
                      color: c, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            // 중간: 이름 + (카테고리/보관 chip + 알레르기) + 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(item['name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.2)),
                      ),
                      const SizedBox(width: 6),
                      _smallChip(item['category']?.toString() ?? '', bold: false),
                      const SizedBox(width: 4),
                      _smallChip(item['storage']?.toString() ?? '', bold: true),
                      if (warnings.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.isDark
                                ? const Color(0xFF450A0A)
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.warning_amber,
                              size: 12, color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item['expirationDate']?.toString() ?? ''} · ${n['calories']!.round()}kcal/100g · 단${n['protein']!.round()}g · 탄${n['carbs']!.round()}g',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.subTextColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 오른쪽: 삭제 / 체크박스 (Row crossAxis center로 세로 가운데)
            if (_selectionMode)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSelected ? _accentGreen : Colors.white,
                  border: Border.all(
                    color: isSelected ? _accentGreen : const Color(0xFFD1D5DB),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                    : null,
              )
            else
              InkWell(
                onTap: () => _delete(item),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: Colors.red.shade400),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 카테고리/보관 표시용 작은 chip
  Widget _smallChip(String text, {bool bold = false}) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.boxBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              color: context.subTextColor,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
    );
  }

  // 카드 탭 시 띄우는 상세 bottom sheet. 웹의 detailIngredient 모달과 동일 정보.
  // 수정 버튼은 앱 고유(웹은 별도 흐름 없음) — 기존 IngredientEditScreen 진입.
  Future<void> _showDetailSheet(Map<String, dynamic> item) async {
    final days = calculateDDay(item['expirationDate']?.toString());
    final s = getExpiryStatus(days);
    final c = statusColor(s);
    final warnings = (item['allergyWarnings'] as List?)?.cast<String>() ?? const [];
    final n = _nutritionOf(item['name']?.toString() ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.boxBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 핸들 바
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetCtx.surfaceBg,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 헤더
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(item['name']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Icon(Icons.close, color: sheetCtx.subTextColor),
                      ),
                    ],
                  ),
                ),
                // 상태 태그 + 알레르기
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(formatDDay(days),
                            style: TextStyle(
                                color: c, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      if (warnings.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: sheetCtx.isDark
                                ? const Color(0xFF450A0A)
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.warning_amber, size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Text('알레르기 ${warnings.join(", ")}',
                                style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 정보 블록
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sheetCtx.surfaceBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _infoRow(sheetCtx, '수량', '${item['quantity']}${item['unit']}'),
                        _infoRow(sheetCtx, '분류', item['category']?.toString() ?? '-'),
                        _infoRow(sheetCtx, '보관 방법', item['storage']?.toString() ?? '-'),
                        _infoRow(sheetCtx, '유통기한',
                            item['expirationDate']?.toString() ?? '-'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 영양 정보 2x2
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sheetCtx.surfaceBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('영양 정보 (100g 기준)',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: sheetCtx.subTextColor)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _nutritionBox(sheetCtx,
                                  '${n['calories']!.round()}', 'kcal')),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _nutritionBox(sheetCtx,
                                  '${n['protein']!.round()}g', '단백질')),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: _nutritionBox(sheetCtx,
                                  '${n['carbs']!.round()}g', '탄수화물')),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _nutritionBox(sheetCtx,
                                  '${n['fat']!.round()}g', '지방')),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 수정 + 삭제
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            final updated = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                  builder: (_) => IngredientEditScreen(existing: item)),
                            );
                            if (updated == true) _fetch();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('수정'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            _delete(item);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sheetCtx.isDark
                                ? const Color(0xFF450A0A)
                                : const Color(0xFFFEE2E2),
                            foregroundColor: const Color(0xFFDC2626),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('삭제'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: ctx.subTextColor)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _nutritionBox(BuildContext ctx, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ctx.boxBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: ctx.subTextColor)),
        ],
      ),
    );
  }
}
