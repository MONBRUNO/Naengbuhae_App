import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/ingredient_repo.dart';
import '../services/notification_service.dart';
import '../state/fridge_context.dart';
import '../state/guest_mode.dart';
import '../utils/expiry.dart';
import '../widgets/fridge_selector.dart';
import '../widgets/login_required.dart';
import 'ingredient_edit_screen.dart';
import 'nutrition_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

const _categories = ['전체', '채소', '육류', '유제품', '곡물', '해산물', '과일',
    '가공식품', '음료', '조미료', '간식', '기타'];
const _storages = ['전체', '냉장', '냉동', '실온'];

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
          // 헤더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('식재료 관리', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    FridgeSelectorButton(),
                  ],
                ),
                const SizedBox(height: 4),
                Text('총 ${list.length}개',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 추가 + 영양 분석 버튼
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
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.black,
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
            child: SizedBox(
              width: double.infinity,
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
                  backgroundColor: const Color(0xFFF0FDF4),
                  foregroundColor: const Color(0xFF15803D),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFFBBF7D0), width: 2),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('영양 분석 보기'),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 이름 검색
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: '이름으로 검색',
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF9CA3AF)),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
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
                      color: selected ? _accentGreen : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(c, style: TextStyle(
                        fontSize: 13,
                        color: selected ? Colors.black : const Color(0xFF6B7280),
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
                  color: _showExpiredOnly ? const Color(0xFFFEE2E2) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _showExpiredOnly ? const Color(0xFFFCA5A5) : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showExpiredOnly ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: _showExpiredOnly ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '만료된 것만 보기',
                      style: TextStyle(
                        fontSize: 13,
                        color: _showExpiredOnly ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 20),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 12),
                  Text('조건에 맞는 식재료가 없습니다', style: TextStyle(color: Color(0xFF9CA3AF))),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: list.map(_ingredientCard).toList()),
            ),
        ],
      ),
    );
  }

  InputDecoration _filterDecoration() => InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  Widget _ingredientCard(Map<String, dynamic> item) {
    final days = calculateDDay(item['expirationDate']?.toString());
    final s = getExpiryStatus(days);
    final c = statusColor(s);
    final warnings = (item['allergyWarnings'] as List?)?.cast<String>() ?? const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final updated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => IngredientEditScreen(existing: item)),
        );
        if (updated == true) _fetch();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(item['name']?.toString() ?? '',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(formatDDay(days),
                            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                      if (warnings.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber, size: 12, color: Colors.red),
                              const SizedBox(width: 2),
                              Text('알레르기 ${warnings.join(", ")}',
                                  style: TextStyle(
                                      color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                  onPressed: () => _delete(item),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${item['quantity']}${item['unit']} · ${item['category']} · ${item['storage']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              '유통기한: ${item['expirationDate']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
