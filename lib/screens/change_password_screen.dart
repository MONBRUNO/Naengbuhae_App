import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../utils/theme_colors.dart';

const _accentGreen = Color(0xFFCDFF00);

// 로그인된 사용자가 마이페이지에서 비밀번호 변경.
// 비번 찾기(forgot/reset)와 다른 흐름 — 현재 비번 입력 확인 후 변경.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPw = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPw = false;
  bool _submitting = false;

  @override
  void dispose() {
    _current.dispose();
    _newPw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPw.text != _confirm.text) {
      _snack('새 비밀번호가 일치하지 않습니다');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/user/me/password', body: {
        'currentPassword': _current.text,
        'newPassword': _newPw.text,
      });
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        if (!mounted) return;
        // 변경 성공 안내 후 마이페이지로 복귀
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('비밀번호가 변경되었어요'),
            content: const Text('다음 로그인부터 새 비밀번호로 입장해주세요.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        _snack(data['message']?.toString() ?? '비밀번호 변경에 실패했습니다');
      }
    } catch (_) {
      _snack('서버 연결에 실패했습니다');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 변경')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _label('현재 비밀번호'),
            TextFormField(
              controller: _current,
              obscureText: !_showPw,
              decoration: _inputDecoration(null),
              validator: (v) => (v == null || v.isEmpty) ? '현재 비밀번호를 입력해주세요' : null,
            ),
            const SizedBox(height: 20),
            _label('새 비밀번호'),
            TextFormField(
              controller: _newPw,
              obscureText: !_showPw,
              decoration: _inputDecoration('영소문자 + 숫자 + 특수문자 8자 이상'),
              validator: (v) => (v == null || v.isEmpty) ? '새 비밀번호를 입력해주세요' : null,
            ),
            const SizedBox(height: 20),
            _label('새 비밀번호 확인'),
            TextFormField(
              controller: _confirm,
              obscureText: !_showPw,
              decoration: _inputDecoration(null).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey),
                  onPressed: () => setState(() => _showPw = !_showPw),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? '새 비밀번호를 다시 입력해주세요' : null,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _submitting ? '변경 중...' : '비밀번호 변경하기',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
