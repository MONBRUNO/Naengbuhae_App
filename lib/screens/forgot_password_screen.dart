import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../utils/theme_colors.dart';

const _accentGreen = Color(0xFFCDFF00);

// 비밀번호 찾기 — 이메일 입력 → 백엔드가 재설정 메일 발송.
// 재설정 링크는 웹에서 처리 (앱 내 재설정은 별도 deep link 필요해서 보류).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '이메일을 입력해주세요.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      // 인증 불필요한 엔드포인트 — ApiClient 안 거치고 직접 호출 (토큰 부착 안 함)
      final res = await http.post(
        Uri.parse('${ApiClient.baseUrl}/user/password/forgot'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == false) {
        setState(() => _error = data['message']?.toString() ?? '요청 처리 실패');
      } else {
        setState(() => _sent = true);
      }
    } catch (_) {
      setState(() => _error = '서버 연결에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _sent ? _sentView() : _formView(),
        ),
      ),
    );
  }

  Widget _formView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text('비밀번호 찾기',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('가입할 때 사용한 이메일을 입력해주세요.\n재설정 링크를 보내드릴게요.',
            style: TextStyle(fontSize: 13, color: context.subTextColor, height: 1.5)),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'email@example.com',
            filled: true,
            fillColor: context.cardBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accentGreen, width: 2),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          child: Text(_submitting ? '전송 중...' : '재설정 링크 보내기'),
        ),
      ],
    );
  }

  Widget _sentView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Color(0xFF059669), size: 28),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text('이메일을 확인해주세요',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(_emailController.text.trim(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('재설정 안내 메일을 보냈어요.',
              style: TextStyle(fontSize: 13, color: context.subTextColor)),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.email_outlined, size: 16, color: context.subTextColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '메일이 안 오면 스팸함을 확인하거나 이메일 주소가 정확한지 확인해주세요. 링크는 30분 동안 유효합니다.',
                  style: TextStyle(fontSize: 12, color: context.subTextColor, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          child: const Text('로그인으로 돌아가기'),
        ),
      ],
    );
  }
}
