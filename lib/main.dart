import 'package:flutter/material.dart';

import 'api/auth_storage.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        return snapshot.data == true ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
