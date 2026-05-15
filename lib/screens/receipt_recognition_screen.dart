import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../state/fridge_context.dart';
import '../utils/theme_colors.dart';

const _accentGreen = Color(0xFFCDFF00);
const _categories = ['채소', '육류', '유제품', '곡물', '해산물', '과일',
    '가공식품', '음료', '조미료', '간식', '기타'];
const _storages = ['냉장', '냉동', '실온'];
const _units = ['개', 'g', 'kg', 'ml', 'L', '팩'];

// 영수증 사진을 받아 AI가 추출한 식재료 목록을 확인/수정/저장하는 화면.
class ReceiptRecognitionScreen extends StatefulWidget {
  const ReceiptRecognitionScreen({super.key});

  @override
  State<ReceiptRecognitionScreen> createState() => _ReceiptRecognitionScreenState();
}

class _ReceiptItem {
  bool selected = true;
  String name;
  String category;
  String storage;
  String quantity;
  String unit;
  Map<String, int> expiryDaysByStorage;

  _ReceiptItem({
    required this.name,
    required this.category,
    required this.storage,
    required this.quantity,
    required this.unit,
    required this.expiryDaysByStorage,
  });

  factory _ReceiptItem.fromJson(Map<String, dynamic> j) {
    final byStorage = <String, int>{};
    final raw = j['expiryDaysByStorage'];
    if (raw is Map) {
      raw.forEach((k, v) {
        byStorage[k.toString()] = v is num ? v.toInt() : 0;
      });
    }
    String pickValid(String? v, List<String> valid, String fallback) =>
        (v != null && valid.contains(v)) ? v : fallback;

    final qty = j['quantity'];
    String qtyStr = '1';
    if (qty is num) {
      qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
    }

    return _ReceiptItem(
      name: j['name']?.toString() ?? '',
      category: pickValid(j['category']?.toString(), _categories, '기타'),
      storage: pickValid(j['storage']?.toString(), _storages, '냉장'),
      quantity: qtyStr,
      unit: pickValid(j['unit']?.toString(), _units, '개'),
      expiryDaysByStorage: byStorage,
    );
  }

  // 현재 보관 기준 권장 일수. 0이면 7일 fallback.
  int get expiryDays {
    final d = expiryDaysByStorage[storage] ?? 0;
    return d > 0 ? d : 7;
  }
}

class _ReceiptRecognitionScreenState extends State<ReceiptRecognitionScreen> {
  bool _recognizing = false;
  bool _saving = false;
  List<_ReceiptItem> _items = [];
  File? _photo;

  @override
  void initState() {
    super.initState();
    // 화면 진입 즉시 사진 선택 띄움
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('취소'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (source == null) {
      if (_items.isEmpty && mounted) Navigator.of(context).pop();
      return;
    }

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null) {
      if (_items.isEmpty && mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _photo = File(file.path);
      _recognizing = true;
    });

    try {
      final res = await ApiClient.uploadFile(
        '/api/ingredients/recognize-receipt',
        fieldName: 'image',
        filePath: file.path,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final items = (data['items'] as List?) ?? [];
        setState(() {
          _items = items
              .whereType<Map>()
              .map((m) => _ReceiptItem.fromJson(m.cast<String, dynamic>()))
              .where((i) => i.name.isNotEmpty)
              .toList();
        });
        if (_items.isEmpty) {
          _snack('영수증에서 식재료를 찾지 못했습니다');
        } else {
          _snack('${_items.length}개 항목을 찾았어요. 확인 후 저장해주세요');
        }
      } else if (res.statusCode == 404) {
        _snack('AI 인식 기능 준비 중입니다');
      } else {
        _snack('인식 실패 (${res.statusCode})');
      }
    } catch (_) {
      _snack('서버 연결 실패');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _saveAll() async {
    final selected = _items.where((i) => i.selected).toList();
    if (selected.isEmpty) {
      _snack('저장할 항목을 선택해주세요');
      return;
    }
    setState(() => _saving = true);
    final today = DateTime.now();
    int ok = 0;
    int fail = 0;
    for (final item in selected) {
      final qty = double.tryParse(item.quantity);
      if (qty == null || qty <= 0 || item.name.trim().isEmpty) {
        fail++;
        continue;
      }
      final body = <String, dynamic>{
        'name': item.name.trim(),
        'quantity': qty,
        'category': item.category,
        'unit': item.unit,
        'storage': item.storage,
        'purchaseDate': _formatDate(today),
        'expirationDate': _formatDate(today.add(Duration(days: item.expiryDays))),
      };
      if (FridgeContext.selectedId != null) {
        body['fridgeId'] = FridgeContext.selectedId;
      }
      final res = await ApiClient.post('/api/ingredients', body: body);
      if (res.statusCode == 200) {
        ok++;
      } else {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (fail == 0) {
      Navigator.of(context).pop(true);
      _snack('$ok개 식재료를 추가했어요');
    } else {
      _snack('$ok개 추가 / $fail개 실패');
      if (ok > 0) Navigator.of(context).pop(true);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('영수증으로 추가', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        actions: [
          if (_items.isNotEmpty && !_recognizing)
            IconButton(icon: const Icon(Icons.refresh), tooltip: '다시 촬영', onPressed: _pickImage),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _saving
                        ? '저장 중...'
                        : '선택한 ${_items.where((i) => i.selected).length}개 추가하기',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_recognizing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_photo!, width: 200, height: 200, fit: BoxFit.cover),
              ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('AI가 영수증을 분석 중...',
                style: TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF6B7280))),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 64, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              const Text('영수증 사진을 선택해주세요',
                  style: TextStyle(color: Color(0xFF6B7280))),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('영수증 촬영/선택'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _itemCard(i),
    );
  }

  Widget _itemCard(int idx) {
    final item = _items[idx];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: item.selected
            ? context.boxBg
            : (context.isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.selected
              ? context.borderColor
              : (context.isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: item.selected,
                  onChanged: (v) => setState(() => item.selected = v ?? true),
                  activeColor: Colors.black,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: item.name)
                    ..selection = TextSelection.collapsed(offset: item.name.length),
                  enabled: item.selected,
                  onChanged: (v) => item.name = v,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '이름',
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _items.removeAt(idx)),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (item.selected) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _miniDropdown(
                  value: item.category,
                  items: _categories,
                  onChanged: (v) => setState(() => item.category = v),
                ),
                const SizedBox(width: 8),
                _miniDropdown(
                  value: item.storage,
                  items: _storages,
                  onChanged: (v) => setState(() => item.storage = v),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: TextEditingController(text: item.quantity)
                      ..selection = TextSelection.collapsed(offset: item.quantity.length),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => item.quantity = v,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: context.surfaceBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
                _miniDropdown(
                  value: item.unit,
                  items: _units,
                  onChanged: (v) => setState(() => item.unit = v),
                  width: 64,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '유통기한: ${_formatDate(DateTime.now().add(Duration(days: item.expiryDays)))} (${item.expiryDays}일)',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    double width = 86,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      decoration: BoxDecoration(
        color: context.surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isDense: true,
          isExpanded: true,
          items: items.map((s) => DropdownMenuItem(
            value: s,
            child: Text(s, style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
