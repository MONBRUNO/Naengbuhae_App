import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_storage.dart';
import 'home_screen.dart';

const _accentGreen = Color(0xFFCDFF00);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showSnackBar('아이디와 비밀번호를 입력해주세요.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/user/login', body: {
        'username': username,
        'password': password,
      });
      if (res.statusCode != 200) {
        _showSnackBar('로그인에 실패했습니다.');
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // 백엔드 LoginResponse: { success, message, token, refreshToken }
      // success=false여도 HTTP 200으로 옴
      if (data['success'] != true) {
        _showSnackBar(data['message']?.toString() ?? '아이디 또는 비밀번호를 확인해주세요.');
        return;
      }
      await AuthStorage.save(
        accessToken: data['token'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      _showSnackBar('서버 연결에 실패했습니다. 백엔드가 켜져있는지 확인해주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  const Text('스마트 냉장고',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('신선한 식재료 관리의 시작',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 48),
                  _textField(
                    controller: _usernameController,
                    hint: '아이디',
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: _passwordController,
                    hint: '비밀번호',
                    obscureText: !_showPassword,
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    child: Text(_submitting ? '로그인 중...' : '로그인'),
                  ),
                  const SizedBox(height: 32),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text('간편 로그인',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  // 소셜 로그인은 OAuth WebView 처리가 필요 — 추후 연결.
                  // 기능적 placeholder만.
                  _socialButton('카카오로 시작하기', const Color(0xFFFEE500), Colors.black),
                  const SizedBox(height: 8),
                  _socialButton('네이버로 시작하기', const Color(0xFF03C75A), Colors.white),
                  const SizedBox(height: 8),
                  _socialButton('구글로 시작하기', Colors.white, Colors.black, border: true),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('아직 회원이 아니신가요? ',
                          style: TextStyle(color: Colors.grey)),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('회원가입 화면은 추후 추가 예정')));
                        },
                        child: const Text('회원가입',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    bool autocorrect = true,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      autocorrect: autocorrect,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentGreen, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _socialButton(String label, Color bg, Color fg, {bool border = false}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('소셜 로그인은 OAuth WebView 연결 후 사용 가능 (추후)')));
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: border ? const BorderSide(color: Color(0xFFE0E0E0), width: 2) : BorderSide.none,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
