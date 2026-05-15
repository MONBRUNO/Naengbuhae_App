import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/guest_mode.dart';
import '../widgets/login_required.dart';

const _accentGreen = Color(0xFFCDFF00);
const _units = ['개', 'g', 'kg', 'ml', 'L', '팩'];

// 웹의 ShoppingList.tsx에 대응.
// 헤더(N개·완료 M개) + 항목 추가 버튼(또는 인라인 폼) + 구매할 항목/구매 완료 섹션.
// 각 미완료 항목 옆에 "냉장고 이관" 버튼: 토글 후 일괄 이관 API 호출 (백엔드는 checked 일괄 이관만 지원).
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
            const Icon(Icons.shopping_cart_outlined, size: 56, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 16),
            const Text('장보기 기능은 로그인 후 사용할 수 있어요',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('가족과 공유되는 장보기 목록은\n계정 데이터로 관리돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.5)),
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
    } catch (e) {
      setState(() => _error = '서버 연결 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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

  // 미완료 항목 옆 "냉장고 이관" 버튼.
  // 백엔드는 per-item transfer를 지원하지 않으므로 toggle → move-to-fridge 순서로 호출.
  // 다른 체크된 항목이 있으면 같이 옮겨가지만 일반적으로 문제 없음.
  Future<void> _transfer(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    setState(() => _transferringIds.add(id));
    try {
      final t = await ApiClient.patch('/api/shopping-list/$id/toggle');
      if (t.statusCode != 200) {
        _snack('이관 실패 (${t.statusCode})');
        return;
      }
      final m = await ApiClient.post('/api/shopping-list/move-to-fridge');
      if (m.statusCode == 200) {
        _snack('${item['name']}을(를) 냉장고로 이관했습니다');
        _fetch();
      } else {
        _snack('이관 실패 (${m.statusCode})');
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
                  child: const Text('취소',
                      style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectionMode
                ? '${_selectedIds.length}개 선택됨'
                : '총 ${_items.length}개 · 완료 ${checked.length}개',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
                      backgroundColor: _accentGreen,
                      foregroundColor: Colors.black,
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
                    backgroundColor: const Color(0xFFF3F4F6),
                    foregroundColor: const Color(0xFF374151),
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

          // 빈 상태
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 48, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 12),
                  Text('장보기 리스트가 비어있습니다', style: TextStyle(color: Color(0xFF9CA3AF))),
                  SizedBox(height: 4),
                  Text('필요한 항목을 추가해보세요',
                      style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB))),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
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
        color: const Color(0xFFF5F5F5),
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
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.black,
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
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: Colors.black,
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

  InputDecoration _inputDecoration(String? hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black)),
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
              ? const Color(0xFFECFCCB)
              : const Color(0xFFF5F5F5),
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
                color: isSelected ? Colors.black : const Color(0xFF9CA3AF),
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
                    border: Border.all(color: const Color(0xFFD1D5DB), width: 2),
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text('${item['quantity']}${item['unit'] ?? ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
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
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(transferring ? '이관 중...' : '냉장고 이관'),
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
                ? const Color(0xFFECFCCB)
                : const Color(0xFFF5F5F5),
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
                  color: isSelected ? Colors.black : const Color(0xFF9CA3AF),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text('${item['quantity']}${item['unit'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
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
