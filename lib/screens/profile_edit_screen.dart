import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../utils/theme_colors.dart';

const _accentGreen = Color(0xFFCDFF00);

const _activityLevels = ['거의 움직임 없음', '가벼운 활동', '보통 활동', '많은 활동', '매우 많은 활동'];
const _dietGoals = ['체중 감량', '체중 유지', '근육량 증가', '건강 관리'];

class ProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ProfileEditScreen({super.key, required this.profile});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _allergiesController;
  late String _gender;
  late DateTime _birthDate;
  late String _activityLevel;
  late String _dietGoal;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameController = TextEditingController(text: p['name']?.toString() ?? '');
    _heightController = TextEditingController(text: p['height']?.toString() ?? '');
    _weightController = TextEditingController(text: p['weight']?.toString() ?? '');
    _allergiesController = TextEditingController(text: p['allergies']?.toString() ?? '');
    _gender = (p['gender']?.toString() ?? '남');
    if (_gender != '남' && _gender != '여') _gender = '남';
    final d = DateTime.tryParse(p['birthDate']?.toString() ?? '');
    _birthDate = d ?? DateTime(1995, 1, 1);
    _activityLevel = (p['activityLevel']?.toString() ?? _activityLevels[2]);
    if (!_activityLevels.contains(_activityLevel)) _activityLevel = _activityLevels[2];
    _dietGoal = (p['dietGoal']?.toString() ?? _dietGoals[1]);
    if (!_dietGoals.contains(_dietGoal)) _dietGoal = _dietGoals[1];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final body = {
        'name': _nameController.text.trim(),
        'gender': _gender,
        'birthDate': _formatDate(_birthDate),
        'height': double.parse(_heightController.text),
        'weight': double.parse(_weightController.text),
        'activityLevel': _activityLevel,
        'dietGoal': _dietGoal,
        'allergies': _allergiesController.text.trim(),
      };
      final res = await ApiClient.put('/user/me', body: body);
      if (res.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        _snack(_extractError(res.body) ?? '수정 실패 (${res.statusCode})');
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
      if (data is Map) return data['message']?.toString() ?? data['error']?.toString();
    } catch (_) {}
    return null;
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 수정')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _label('이름'),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration('이름'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해주세요' : null,
            ),
            const SizedBox(height: 16),
            _label('성별'),
            Row(
              children: ['남', '여'].asMap().entries.map((entry) {
                final i = entry.key;
                final g = entry.value;
                final selected = g == _gender;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => _gender = g),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? Colors.black : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            g,
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF6B7280),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _label('생년월일'),
            InkWell(
              onTap: _pickBirthDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: context.cardBg, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(child: Text(_formatDate(_birthDate))),
                    const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('키 (cm)'),
                      TextFormField(
                        controller: _heightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('170'),
                        validator: _numberValidator,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('몸무게 (kg)'),
                      TextFormField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputDecoration('65'),
                        validator: _numberValidator,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('활동량'),
            DropdownButtonFormField<String>(
              value: _activityLevel,
              decoration: _inputDecoration(null),
              items: _activityLevels.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
              onChanged: (v) => setState(() => _activityLevel = v ?? _activityLevels[2]),
            ),
            const SizedBox(height: 16),
            _label('식단 목표'),
            DropdownButtonFormField<String>(
              value: _dietGoal,
              decoration: _inputDecoration(null),
              items: _dietGoals.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => setState(() => _dietGoal = v ?? _dietGoals[1]),
            ),
            const SizedBox(height: 16),
            _label('알레르기 정보 (선택)'),
            TextFormField(
              controller: _allergiesController,
              decoration: _inputDecoration('예) 우유, 땅콩, 새우'),
              maxLines: 2,
            ),
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
                  _submitting ? '저장 중...' : '저장하기',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.isEmpty) return '필수';
    final d = double.tryParse(v);
    if (d == null || d <= 0) return '0보다 큰 수';
    return null;
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );

  InputDecoration _inputDecoration(String? hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accentGreen, width: 2),
        ),
      );
}
