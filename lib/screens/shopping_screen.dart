import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/fridge_context.dart';
import '../state/guest_mode.dart';
import '../utils/theme_colors.dart';
import '../widgets/login_required.dart';

const _accentGreen = Color(0xFFCDFF00);
const _units = ['개', 'g', 'kg', 'ml', 'L', '팩'];

// 웹의 ShoppingList.tsx에 대응.
// 헤더(N개·완료 M개) + 항목 추가 버튼(또는 인라인 폼) + 구매할 항목/구매 완료 섹션.
// 각 미완료 항목 옆에 "냉장고에 추가" 버튼: per-item transfer endpoint 직접 호출.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  bool _showAddForm = false;
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _unit = '개';
  final Set<int> _transferringIds = {};

  // 다중 선택 모드 — 카드 탭으로 토글, 액션바에서 일괄 삭제.
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  bool _bulkDeleting = false;

  // 자동 제안 — 가족이 자주 비웠는데 지금 냉장고/장보기 모두에 없는 식재료
  List<Map<String, dynamic>> _suggestions = [];
  String? _addingSuggestion;

  @override
  void initState() {
    super.initState();
    // 장보기는 서버 기반(/api/shopping-list)이라 게스트는 안내 화면만 표시.
    if (GuestMode.currentlyGuest) {
      _loading = false;
      return;
    }
    _fetch();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Widget _buildGuestPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: context.hintTextColor),
            const SizedBox(height: 16),
            const Text('장보기 기능은 로그인 후 사용할 수 있어요',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('가족과 공유되는 장보기 목록은\n계정 데이터로 관리돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.subTextColor, height: 1.5)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => LoginRequired.show(context, featureName: '장보기'),
              child: const Text('로그인하기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/shopping-list');
      if (res.statusCode != 200) {
        setState(() => _error = '조회 실패 (${res.statusCode})');
        return;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      setState(() => _items = data.cast<Map<String, dynamic>>());
      // 장보기 갱신 후 제안도 같이 — 제안에 있던 식재료가 장보기에 들어가면 사라지도록
      // ignore: unawaited_futures
      _fetchSuggestions();
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchSuggestions() async {
    final fridgeId = FridgeContext.selectedId;
    try {
      final path = fridgeId != null
          ? '/api/shopping-list/suggestions?fridgeId=$fridgeId&limit=5'
          : '/api/shopping-list/suggestions?limit=5';
      final res = await ApiClient.get(path);
      if (res.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      if (mounted) {
        setState(() => _suggestions = data.cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // 무시 — 다음 fetch에서 다시 시도
    }
  }

  Future<void> _addSuggestion(String name) async {
    if (_addingSuggestion != null) return;
    setState(() => _addingSuggestion = name);
    try {
      final res = await ApiClient.post('/api/shopping-list', body: {
        'name': name,
        'quantity': 1.0,
        'unit': '개',
      });
      if (res.statusCode == 200) {
        await _fetch(); // 장보기 + 제안 동시 갱신
      } else {
        _snack('추가 실패 (${res.statusCode})');
      }
    } catch (_) {
      _snack('서버 연결 실패');
    } finally {
      if (mounted) setState(() => _addingSuggestion = null);
    }
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    final q = double.tryParse(_quantityController.text);
    if (name.isEmpty) {
      _snack('상품 이름을 입력해주세요');
      return;
    }
    if (q == null || q <= 0) {
      _snack('올바른 수량을 입력해주세요');
      return;
    }
    final res = await ApiClient.post('/api/shopping-list', body: {
      'name': name,
      'quantity': q,
      'unit': _unit,
    });
    if (res.statusCode == 200) {
      _nameController.clear();
      _quantityController.text = '1';
      setState(() {
        _unit = '개';
        _showAddForm = false;
      });
      _fetch();
    } else {
      _snack('추가 실패 (${res.statusCode})');
    }
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final res = await ApiClient.patch('/api/shopping-list/${item['id']}/toggle');
    if (res.statusCode == 200) _fetch();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final res = await ApiClient.delete('/api/shopping-list/${item['id']}');
    if (res.statusCode == 200) _fetch();
  }

  // [-/+] 카운터. 1에서 -누르면 삭제 confirm.
  Future<void> _decrement(Map<String, dynamic> item) async {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    if (qty <= 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${item['name']}을(를) 삭제하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
          ],
        ),
      );
      if (ok == true) await _delete(item);
      return;
    }
    await _updateQuantity(item, qty - 1);
  }

  Future<void> _increment(Map<String, dynamic> item) async {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    await _updateQuantity(item, qty + 1);
  }

  Future<void> _updateQuantity(Map<String, dynamic> item, double newQty) async {
    final res = await ApiClient.patch(
      '/api/shopping-list/${item['id']}/quantity',
      body: {'quantity': newQty},
    );
    if (res.statusCode == 200) {
      // refetch 안 하고 _items 안의 해당 항목만 patch — 순서 유지 (사용자 어지러움 방지)
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere((i) => i['id'] == item['id']);
          if (idx >= 0) {
            _items[idx] = {..._items[idx], 'quantity': newQty};
          }
        });
      }
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
      _selectedIds.addAll(_items.map((e) => e['id'] as int));
    });
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제하시겠습니까?'),
        content: Text('${_selectedIds.length}개의 장보기 항목을 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _bulkDeleting = true);
    try {
      final res = await ApiClient.post('/api/shopping-list/bulk-delete', body: {
        'ids': _selectedIds.toList(),
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        _exitSelectionMode();
        await _fetch();
      } else {
        _snack('일괄 삭제 실패 (${res.statusCode})');
      }
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  // 미완료 항목 옆 "냉장고에 추가" 버튼.
  // 백엔드에 단일 항목 이관 endpoint (POST /api/shopping-list/{id}/transfer)가 추가돼
  // toggle+move-to-fridge 패턴 대신 직접 호출 (다른 체크 항목 휩쓸림 방지).
  Future<void> _transfer(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    final name = item['name']?.toString() ?? '';

    // 실수 클릭 방지 — 구매했는지 확인
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name 구매하셨나요?'),
        content: const Text('냉장고로 옮길게요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('냉장고에 추가')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _transferringIds.add(id));
    try {
      final res = await ApiClient.post('/api/shopping-list/$id/transfer');
      if (res.statusCode == 200) {
        _snack('$name 냉장고에 추가했어요');
        _fetch();
      } else {
        _snack('냉장고 추가 실패 (${res.statusCode})');
      }
    } finally {
      if (mounted) setState(() => _transferringIds.remove(id));
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    if (GuestMode.currentlyGuest) {
      return Scaffold(body: SafeArea(bottom: false, child: _buildGuestPlaceholder()));
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: _buildBody()),
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

    final unchecked = _items.where((i) => i['checked'] != true).toList();
    final checked = _items.where((i) => i['checked'] == true).toList();

    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
        children: [
          // 헤더 (선택 모드면 우측 "취소", 아니면 일반)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('장보기 리스트', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              if (_selectionMode)
                TextButton(
                  onPressed: _exitSelectionMode,
                  child: Text('취소',
                      style: TextStyle(color: context.subTextColor, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectionMode
                ? '${_selectedIds.length}개 선택됨'
                : '총 ${_items.length}개 · 완료 ${checked.length}개',
            style: TextStyle(fontSize: 13, color: context.subTextColor),
          ),
          const SizedBox(height: 16),

          if (_selectionMode) ...[
            // 일괄 액션 바
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _selectAllVisible,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('전체 선택 (${_items.length})',
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
            const SizedBox(height: 16),
          ] else if (!_showAddForm) ...[
            // 추가 버튼 + 선택 모드 진입
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _showAddForm = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: context.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('항목 추가하기'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _items.isEmpty ? null : _enterSelectionMode,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: context.cardBg,
                    foregroundColor: context.isDark ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide.none,
                  ),
                  child: const Icon(Icons.check_box_outlined, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            _addForm(),
            const SizedBox(height: 16),
          ],

          // 자동 제안 — 가족이 자주 비웠는데 지금 없는 식재료
          if (!_selectionMode && !_showAddForm && _suggestions.isNotEmpty) ...[
            _suggestionsCard(),
            const SizedBox(height: 16),
          ],

          // 빈 상태
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 48, color: context.hintTextColor),
                  const SizedBox(height: 12),
                  Text('장보기 리스트가 비어있습니다', style: TextStyle(color: context.hintTextColor)),
                  const SizedBox(height: 4),
                  Text('필요한 항목을 추가해보세요',
                      style: TextStyle(fontSize: 12, color: context.hintTextColor)),
                ],
              ),
            ),

          // 구매할 항목
          if (unchecked.isNotEmpty) ...[
            Text('구매할 항목 (${unchecked.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...unchecked.map(_uncheckedTile),
            const SizedBox(height: 24),
          ],

          // 구매 완료
          if (checked.isNotEmpty) ...[
            Text('구매 완료 (${checked.length})',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.subTextColor)),
            const SizedBox(height: 12),
            ...checked.map(_checkedTile),
          ],
        ],
      ),
    );
  }

  Widget _addForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: _inputDecoration('상품 이름'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDecoration('1'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: _inputDecoration(null),
                  items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => setState(() => _unit = v ?? '개'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _add,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: context.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('추가'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() {
                    _showAddForm = false;
                    _nameController.clear();
                    _quantityController.text = '1';
                    _unit = '개';
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.cardBg,
                    foregroundColor: context.textColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('취소'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionsCard() {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1E2A1A), Color(0xFF191C20)]
              : const [Color(0xFFF7FEE7), Colors.white],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF4D7C0F) : const Color(0xFFD9F99D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF15803D)),
              const SizedBox(width: 6),
              const Text('이건 어때요?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('자주 비우는데 지금 없어요',
                  style: TextStyle(fontSize: 11, color: context.subTextColor)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _suggestions[i];
                final name = s['name']?.toString() ?? '';
                final count = (s['count'] as num? ?? 0).toInt();
                final adding = _addingSuggestion == name;
                return GestureDetector(
                  onTap: adding ? null : () => _addSuggestion(name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.surfaceBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? const Color(0xFF4D7C0F) : const Color(0xFFD9F99D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(adding ? Icons.hourglass_top : Icons.add,
                            size: 14, color: const Color(0xFF15803D)),
                        const SizedBox(width: 4),
                        Text(name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('${count}회',
                            style: TextStyle(fontSize: 11, color: context.hintTextColor)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String? hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.surfaceBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.textColor)),
      );

  Widget _uncheckedTile(Map<String, dynamic> item) {
    final id = item['id'] as int;
    final transferring = _transferringIds.contains(id);
    final isSelected = _selectedIds.contains(id);
    return GestureDetector(
      onTap: _selectionMode ? () => _toggleSelection(id) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
        child: Row(
          children: [
            if (_selectionMode)
              Icon(
                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                color: isSelected ? context.textColor : context.hintTextColor,
                size: 22,
              )
            else
              GestureDetector(
                onTap: () => _toggle(item),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: context.isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB), width: 2),
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (_selectionMode)
                    Text('${item['quantity']}${item['unit'] ?? ''}',
                        style: TextStyle(fontSize: 12, color: context.subTextColor))
                  else
                    _QuantityCounter(
                      item: item,
                      onDecrement: () => _decrement(item),
                      onIncrement: () => _increment(item),
                      onCommit: (newQty) async {
                        if (newQty <= 0) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('${item['name']}을(를) 삭제하시겠습니까?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('취소')),
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('삭제')),
                              ],
                            ),
                          );
                          if (ok == true) await _delete(item);
                          return;
                        }
                        final cur = (item['quantity'] as num?)?.toDouble() ?? 0;
                        if (newQty != cur) {
                          await _updateQuantity(item, newQty);
                        }
                      },
                    ),
                ],
              ),
            ),
            if (!_selectionMode) ...[
              IconButton(
                onPressed: () => _delete(item),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: transferring ? null : () => _transfer(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: context.onAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(transferring ? '추가 중...' : '냉장고에 추가'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _checkedTile(Map<String, dynamic> item) {
    final id = item['id'] as int;
    final isSelected = _selectedIds.contains(id);
    return GestureDetector(
      onTap: _selectionMode ? () => _toggleSelection(id) : null,
      child: Opacity(
        opacity: _selectionMode && isSelected ? 1.0 : 0.6,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
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
          child: Row(
            children: [
              if (_selectionMode)
                Icon(
                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: isSelected ? context.textColor : context.hintTextColor,
                  size: 22,
                )
              else
                GestureDetector(
                  onTap: () => _toggle(item),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _accentGreen),
                    child: const Icon(Icons.check, size: 16, color: Colors.black),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.subTextColor,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text('${item['quantity']}${item['unit'] ?? ''}',
                        style: TextStyle(fontSize: 12, color: context.hintTextColor)),
                  ],
                ),
              ),
              if (!_selectionMode)
                IconButton(
                  onPressed: () => _delete(item),
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// 장보기 항목 수량 카운터 — [-] [TextField] [unit] [+]
// 키보드로 직접 편집 가능. onSubmitted/onEditingComplete 시 commit.
// 외부에서 item.quantity 변경되면 controller 동기화 (사용자가 입력 중이 아닐 때).
class _QuantityCounter extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final Future<void> Function(double) onCommit;

  const _QuantityCounter({
    required this.item,
    required this.onDecrement,
    required this.onIncrement,
    required this.onCommit,
  });

  @override
  State<_QuantityCounter> createState() => _QuantityCounterState();
}

class _QuantityCounterState extends State<_QuantityCounter> {
  late TextEditingController _ctrl;
  late FocusNode _focusNode;

  String _formatQty(dynamic q) {
    if (q == null) return '1';
    final n = (q as num).toDouble();
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toString();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatQty(widget.item['quantity']));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_QuantityCounter old) {
    super.didUpdateWidget(old);
    // 외부에서 quantity 바뀌면 controller 동기화 (사용자 입력 중이 아닐 때만)
    final newText = _formatQty(widget.item['quantity']);
    if (!_focusNode.hasFocus && _ctrl.text != newText) {
      _ctrl.text = newText;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_ctrl.text);
    if (parsed == null) {
      _ctrl.text = _formatQty(widget.item['quantity']);
      return;
    }
    widget.onCommit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: widget.onDecrement,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(Icons.remove, size: 16),
              ),
            ),
            SizedBox(
              width: 40,
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                widget.item['unit']?.toString() ?? '',
                style: TextStyle(fontSize: 11, color: context.subTextColor),
              ),
            ),
            InkWell(
              onTap: widget.onIncrement,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(Icons.add, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
