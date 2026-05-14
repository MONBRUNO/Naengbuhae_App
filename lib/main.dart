import 'package:flutter/material.dart';

import 'api/auth_storage.dart';
import 'screens/login_screen.dart';
import 'screens/main_scaffold.dart';
import 'services/fcm_service.dart';
import 'services/notification_router.dart';
import 'services/notification_service.dart';
import 'state/notification_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 알림 인프라 초기화 — 로컬은 무조건, FCM은 google-services.json이 있어야 동작
  await NotificationSettings.load();
  await NotificationService.init();
  // FCM은 비차단으로 — 초기화 실패해도 로컬 알림은 계속 동작해야 함
  // ignore: unawaited_futures
  FcmService.init();
  runApp(const NaengbuhaeApp());
}

// 웹 프론트의 #CDFF00 초록 + 검정 테마를 그대로 가져옴.
const _accentGreen = Color(0xFFCDFF00);

class NaengbuhaeApp extends StatelessWidget {
  const NaengbuhaeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉부해',
      debugShowCheckedModeBanner: false,
      // 알림 탭 핸들러에서 화면 전환할 때 사용
      navigatorKey: NotificationRouter.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentGreen,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      // 시작 시 토큰 있으면 홈, 없으면 로그인
      home: const _AuthGate(),
    );
  }
}

// 시작 시 저장된 토큰 확인 후 라우팅. 웹의 sessionStorage/localStorage 분기 + isLoggedIn 체크와 같은 역할.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthStorage.hasToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == true ? const MainScaffold() : const LoginScreen();
      },
    );
  }
}
