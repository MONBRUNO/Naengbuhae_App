import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_storage.dart';
import '../services/fcm_service.dart';
import '../services/ingredient_migration.dart';
import '../services/notification_service.dart';
import '../state/guest_mode.dart';
import '../utils/theme_colors.dart';
import 'forgot_password_screen.dart';
import 'main_scaffold.dart';
import 'oauth_webview_screen.dart';
import 'signup_screen.dart';

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
      // 게스트 모드에서 진입한 경우 플래그 해제 + 로컬 식재료 마이그레이션 안내
      await GuestMode.clear();
      if (mounted) await IngredientMigration.promptAndMigrate(context);
      // 로그인 직후 알림 권한 요청 + FCM 토큰 등록. 실패해도 로그인 흐름은 진행.
      // ignore: unawaited_futures
      NotificationService.requestPermission();
      // ignore: unawaited_futures
      FcmService.registerCurrentToken();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScaffold()),
      );
    } catch (e) {
      _showSnackBar('서버 연결에 실패했습니다. 백엔드가 켜져있는지 확인해주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _startAsGuest() async {
    await GuestMode.setGuest();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScaffold()),
    );
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
                  const SizedBox(height: 12),
                  // 비로그인 진입 — 회원가입만 있는 줄 알고 이탈하지 않도록 로그인 버튼 바로 아래에 배치
                  Center(
                    child: TextButton(
                      onPressed: _startAsGuest,
                      child: const Text(
                        '로그인 없이 둘러보기',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 비밀번호 잊은 사용자용 — 메일로 재설정 링크 받기
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: const Text(
                        '비밀번호 잊으셨나요?',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                  _socialButton('카카오로 시작하기', const Color(0xFFFEE500), Colors.black,
                      provider: 'kakao'),
                  const SizedBox(height: 8),
                  _socialButton('네이버로 시작하기', const Color(0xFF03C75A), Colors.white,
                      provider: 'naver'),
                  const SizedBox(height: 8),
                  _socialButton(
                    '구글로 시작하기',
                    context.isDark ? const Color(0xFF374151) : Colors.white,
                    context.isDark ? Colors.white : Colors.black,
                    border: true,
                    provider: 'google',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('아직 회원이 아니신가요? ',
                          style: TextStyle(color: Colors.grey)),
                      GestureDetector(
                        onTap: () async {
                          // 가입 성공 시 username을 받아서 자동으로 채워준다.
                          final newUsername = await Navigator.of(context).push<String>(
                            MaterialPageRoute(builder: (_) => const SignupScreen()),
                          );
                          if (!mounted || newUsername == null || newUsername.isEmpty) return;
                          setState(() => _usernameController.text = newUsername);
                        },
                        child: Text('회원가입',
                            style: TextStyle(
                              color: context.textColor,
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
        fillColor: context.cardBg,
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

  Widget _socialButton(
    String label,
    Color bg,
    Color fg, {
    bool border = false,
    required String provider,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => _socialLogin(provider),
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

  // OAuth WebView 열어 토큰 받아오기. 받으면 로컬 저장 + 알림 권한/FCM 등록 +
  // 메인으로 이동. 추가 정보가 필요한 경우 백엔드가 needsAdditionalInfo=true로 알려주는데
  // 일단 메인에서 프로필 미완성 배너로 노출되므로 별도 분기 없이 진입.
  Future<void> _socialLogin(String provider) async {
    final result = await Navigator.of(context).push<OAuthResult>(
      MaterialPageRoute(builder: (_) => OAuthWebViewScreen(provider: provider)),
    );
    if (result == null) return; // 사용자가 도중에 닫음

    await AuthStorage.save(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await GuestMode.clear();
    if (mounted) await IngredientMigration.promptAndMigrate(context);
    // ignore: unawaited_futures
    NotificationService.requestPermission();
    // ignore: unawaited_futures
    FcmService.registerCurrentToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScaffold()),
    );
  }
}
