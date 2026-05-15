import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/ingredient_repo.dart';
import '../state/fridge_context.dart';
import '../state/guest_mode.dart';
import '../utils/expiry_defaults.dart';
import '../utils/theme_colors.dart';
import '../widgets/login_required.dart';
import 'receipt_recognition_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

const _categories = ['채소', '육류', '유제품', '곡물', '해산물', '과일',
    '가공식품', '음료', '조미료', '간식', '기타'];
const _storages = ['냉장', '냉동', '실온'];
const _units = ['개', 'g', 'kg', 'ml', 'L', '팩'];

// existing이 null이면 추가, 있으면 수정 모드.
// 사진은 AI 인식용으로만 임시 전송하고 백엔드에 저장하진 않는다.
class IngredientEditScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const IngredientEditScreen({super.key, this.existing});

  @override
  State<IngredientEditScreen> createState() => _IngredientEditScreenState();
}

class _IngredientEditScreenState extends State<IngredientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _category = '채소';
  String _storage = '냉장';
  String _unit = '개';
  DateTime _purchaseDate = DateTime.now();
  DateTime? _manualExpirationDate;
  bool _useAutoExpiry = true;
  bool _submitting = false;

  // 카메라/갤러리로 고른 사진 (미리보기 + AI 인식 전송용). 저장은 안 함.
  File? _selectedImage;
  bool _recognizing = false;

  // AI가 알려준 보관별 권장 일수. 보관 드롭다운 바꾸면 이걸로 유통기한 재계산.
  Map<String, int>? _expiryDaysByStorage;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameController.text = e['name']?.toString() ?? '';
      _quantityController.text = _formatQuantity(e['quantity']);
      _category = (e['category']?.toString() ?? '채소');
      _storage = (e['storage']?.toString() ?? '냉장');
      _unit = (e['unit']?.toString() ?? '개');
      final p = DateTime.tryParse(e['purchaseDate']?.toString() ?? '');
      if (p != null) _purchaseDate = p;
      final exp = DateTime.tryParse(e['expirationDate']?.toString() ?? '');
      if (exp != null) _manualExpirationDate = exp;
      _useAutoExpiry = false;
      if (!_units.contains(_unit)) _unit = '개';
      if (!_categories.contains(_category)) _category = '채소';
      if (!_storages.contains(_storage)) _storage = '냉장';
    }
  }

  String _formatQuantity(dynamic q) {
    if (q == null) return '';
    final d = q is num ? q.toDouble() : double.tryParse(q.toString()) ?? 0;
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _pickExpirationDate() async {
    final initial = _manualExpirationDate ?? _purchaseDate.add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _manualExpirationDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    DateTime expiry;
    if (_useAutoExpiry) {
      expiry = defaultExpirationDate(_nameController.text.trim(), _purchaseDate);
    } else {
      if (_manualExpirationDate == null) {
        _snack('유통기한을 입력해주세요');
        return;
      }
      if (_manualExpirationDate!.isBefore(_purchaseDate)) {
        _snack('유통기한은 구매일 이후여야 합니다');
        return;
      }
      expiry = _manualExpirationDate!;
    }

    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        'quantity': double.parse(_quantityController.text),
        'category': _category,
        'unit': _unit,
        'storage': _storage,
        'purchaseDate': _formatDate(_purchaseDate),
        'expirationDate': _formatDate(expiry),
      };
      // 추가 모드일 땐 현재 선택된 냉장고로. 수정 모드는 기존 fridge 유지(서버가 처리).
      if (!_isEdit && FridgeContext.selectedId != null) {
        body['fridgeId'] = FridgeContext.selectedId;
      }
      final res = _isEdit
          ? await IngredientRepo.update(widget.existing!['id'] as int, body)
          : await IngredientRepo.add(body);
      if (res.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        _snack(_extractError(res.body) ??
            (_isEdit ? '수정 실패 (${res.statusCode})' : '추가 실패 (${res.statusCode})'));
      }
    } catch (_) {
      _snack('서버 연결 실패');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _extractError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        return data['message']?.toString() ?? data['error']?.toString();
      }
    } catch (_) {}
    return null;
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  // _expiryDaysByStorage에서 현재 _storage에 해당하는 일수를 가져와 유통기한 갱신.
  // 사진 인식 직후, 그리고 사용자가 보관 드롭다운을 바꿀 때 호출된다.
  void _applyExpiryFromStorage() {
    final map = _expiryDaysByStorage;
    if (map == null) return;
    final days = map[_storage];
    if (days == null || days <= 0) return;
    _manualExpirationDate = _purchaseDate.add(Duration(days: days));
    _useAutoExpiry = false;
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
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;

    setState(() {
      _selectedImage = File(file.path);
      _recognizing = true;
    });

    // 사진을 AI 인식용으로만 전송. 응답에서 인식 결과만 받아 폼에 채우고 사진 자체는 저장 안 함.
    try {
      final res = await ApiClient.uploadFile(
        '/api/ingredients/recognize',
        fieldName: 'image',
        filePath: file.path,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final recognized = (data['recognized'] as Map?)?.cast<String, dynamic>();
        if (recognized != null) {
          setState(() {
            final name = recognized['name']?.toString();
            if (name != null && name.isNotEmpty) _nameController.text = name;
            final category = recognized['category']?.toString();
            if (category != null && _categories.contains(category)) _category = category;
            final storage = recognized['storage']?.toString();
            if (storage != null && _storages.contains(storage)) _storage = storage;
            final qty = recognized['quantity'];
            if (qty != null) _quantityController.text = _formatQuantity(qty);
            final unit = recognized['unit']?.toString();
            if (unit != null && _units.contains(unit)) _unit = unit;
            // AI가 보관별 권장 일수를 알려준 경우 → 저장해두고 현재 보관에 맞춰 유통기한 세팅.
            // 사용자가 보관 드롭다운 바꾸면 _applyExpiryFromStorage()가 다시 재계산.
            final byStorage = recognized['expiryDaysByStorage'];
            if (byStorage is Map) {
              _expiryDaysByStorage = byStorage.map((k, v) =>
                  MapEntry(k.toString(), v is num ? v.toInt() : 0));
              _applyExpiryFromStorage();
            }
          });
          _snack('식재료를 인식했습니다. 확인 후 저장해주세요');
        }
      } else if (res.statusCode == 404) {
        _snack('AI 인식 기능 준비 중입니다. 직접 입력해주세요');
      } else {
        _snack('인식 실패 (${res.statusCode}). 직접 입력해주세요');
      }
    } catch (_) {
      _snack('서버 연결 실패. 직접 입력해주세요');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEdit ? '식재료 수정' : '식재료 추가',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // 영수증으로 일괄 추가 (추가 모드에서만)
            if (!_isEdit) ...[
              InkWell(
                onTap: () async {
                  if (GuestMode.currentlyGuest) {
                    await LoginRequired.show(context, featureName: '영수증 인식');
                    return;
                  }
                  final added = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const ReceiptRecognitionScreen()),
                  );
                  if (added == true && mounted) Navigator.of(context).pop(true);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.receipt_long_outlined, color: _accentGreen, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('영수증으로 여러 개 한 번에 추가',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 카메라 인식 영역. 추가 모드에서만 표시. 게스트는 서버 AI를 못 쓰니까 숨김.
            if (!_isEdit && !GuestMode.currentlyGuest) ...[
              InkWell(
                onTap: _recognizing ? null : _pickImage,
                borderRadius: BorderRadius.circular(12),
                child: _selectedImage == null
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD1D5DB), width: 2),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.photo_camera_outlined, size: 32, color: Color(0xFF9CA3AF)),
                            SizedBox(height: 8),
                            Text('사진으로 식재료 인식하기',
                                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_selectedImage!,
                                width: double.infinity, height: 200, fit: BoxFit.cover),
                          ),
                          if (_recognizing)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(color: Colors.white),
                                      SizedBox(height: 12),
                                      Text('AI가 식재료를 인식 중...',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedImage = null),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
            ],

            _label('식재료 이름', required: true),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration('예: 우유, 계란, 양상추'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '식재료 이름을 입력해주세요' : null,
              onChanged: (v) {
                // 알려진 식재료면 카테고리/보관 자동 세팅 (사용자가 이후 수동 변경 가능)
                final d = lookupIngredient(v);
                if (d == null) return;
                setState(() {
                  if (d.category != null && _categories.contains(d.category)) {
                    _category = d.category!;
                  }
                  if (d.storage != null && _storages.contains(d.storage)) {
                    _storage = d.storage!;
                  }
                });
              },
            ),
            const SizedBox(height: 24),

            _label('카테고리', required: true),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: _inputDecoration(null),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v ?? '채소'),
            ),
            const SizedBox(height: 24),

            _label('수량', required: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inputDecoration('1'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return '수량을 입력해주세요';
                      final d = double.tryParse(v);
                      if (d == null || d <= 0) return '0보다 큰 수';
                      return null;
                    },
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
            const SizedBox(height: 24),

            _label('보관 상태', required: true),
            const SizedBox(height: 8),
            Row(
              children: _storages.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                final selected = s == _storage;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < _storages.length - 1 ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _storage = s;
                        _applyExpiryFromStorage();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? _accentGreen : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(s, style: TextStyle(
                            color: selected ? Colors.black : const Color(0xFF6B7280),
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          )),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _label('구매일', required: true),
            const SizedBox(height: 8),
            _dateField(_purchaseDate, _pickPurchaseDate),
            const SizedBox(height: 24),

            // 유통기한 자동 설정 체크박스
            InkWell(
              onTap: () => setState(() => _useAutoExpiry = !_useAutoExpiry),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _useAutoExpiry,
                        onChanged: (v) => setState(() => _useAutoExpiry = v ?? true),
                        activeColor: Colors.black,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('유통기한 자동 설정 (식재료별 추천 기간)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),

            // 유통기한 수동 입력 (체크 해제 시)
            if (!_useAutoExpiry) ...[
              const SizedBox(height: 24),
              _label('유통기한', required: true),
              const SizedBox(height: 8),
              _dateField(
                _manualExpirationDate ?? _purchaseDate.add(const Duration(days: 7)),
                _pickExpirationDate,
                isPlaceholder: _manualExpirationDate == null,
              ),
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _submitting ? '저장 중...' : (_isEdit ? '수정하기' : '추가하기'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (required)
          const Text(' *', style: TextStyle(fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.boxBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black, width: 1.5),
        ),
      );

  Widget _dateField(DateTime d, VoidCallback onTap, {bool isPlaceholder = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.boxBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _formatDate(d),
                style: TextStyle(
                  color: isPlaceholder ? const Color(0xFF9CA3AF) : Colors.black,
                ),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
