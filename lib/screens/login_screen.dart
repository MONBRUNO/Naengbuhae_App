import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 브랜드 로고 — Transform.scale로 좌우로 살짝 더 키움.
                  // alignment topCenter라 시각적으로 아래쪽으로 자라서 로그인칸에 가까워짐.
                  Transform.scale(
                    scale: 1.15,
                    alignment: Alignment.topCenter,
                    child: Image.asset('assets/brand/logo_full.png',
                        width: double.infinity, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 0),
                  _textField(
                    controller: _usernameController,
                    hint: '아이디',
                    autocorrect: false,
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    child: Text(_submitting ? '로그인 중...' : '로그인'),
                  ),
                  const SizedBox(height: 12),
                  // 비로그인 진입 + 비번 찾기 — 한 줄에 묶어 깔끔하게 (밑줄 제거, · 구분)
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _startAsGuest,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: const Color(0xFF6B7280),
                          ),
                          child: const Text('로그인 없이 둘러보기',
                              style: TextStyle(fontSize: 13)),
                        ),
                        Container(
                            width: 1,
                            height: 11,
                            color: const Color(0xFFD1D5DB)),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen()),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: const Color(0xFF6B7280),
                          ),
                          child: const Text('비밀번호 찾기',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text('간편 로그인',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _socialIcon(
                        provider: 'kakao',
                        bg: const Color(0xFFFEE500),
                        // 동그란 카카오 로고가 버튼 원을 꽉 채움 (full-bleed)
                        child: _brandChild(
                          asset: 'assets/social/kakao.png',
                          size: 56,
                          fallback: const Icon(SimpleIcons.kakaotalk,
                              color: Colors.black, size: 26),
                        ),
                      ),
                      const SizedBox(width: 20),
                      _socialIcon(
                        provider: 'naver',
                        bg: const Color(0xFF03C75A),
                        // 네이버는 익숙한 N 마크라 simple_icons 글리프 그대로 사용
                        child: const Icon(SimpleIcons.naver,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 20),
                      // 구글 가이드라인: 4색 G는 흰 배경에 변형 없이 — 다크에서도 흰 원 유지
                      _socialIcon(
                        provider: 'google',
                        bg: Colors.white,
                        border: true,
                        child: _brandChild(
                          asset: 'assets/social/google.png',
                          size: 24,
                          fallback: const Icon(SimpleIcons.google,
                              color: Color(0xFF4285F4), size: 24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                              color: context.skyAccent,
                              fontWeight: FontWeight.w700,
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

  // 간편 로그인: 전폭 버튼 대신 원형 아이콘 한 줄 (스크롤 없이 한 화면에)
  // 공식 브랜드 에셋(assets/social/*.png) 우선 사용.
  // 파일이 아직 없으면 simple_icons 글리프로 대체 (각 사 공식 에셋 받아 넣으면 자동 적용).
  Widget _brandChild({
    required String asset,
    required double size,
    required Widget fallback,
  }) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  Widget _socialIcon({
    required String provider,
    required Color bg,
    required Widget child,
    bool border = false,
  }) {
    return GestureDetector(
      onTap: () => _socialLogin(provider),
      child: Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border
              ? Border.all(color: const Color(0xFFE0E0E0), width: 2)
              : null,
        ),
        child: Center(child: child),
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
