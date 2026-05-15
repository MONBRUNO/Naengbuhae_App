import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 비로그인(게스트) 모드 플래그.
// 토큰 없이 로컬 식재료 관리만 쓰는 사용자를 위해 _AuthGate가 토큰과 함께 이 플래그도 검사함.
// 가입/로그인 성공 시 false로 전환되고 로컬 데이터는 마이그레이션 후 정리.
class GuestMode {
  static const _kKey = 'isGuest';

  // 화면이 listen해서 게스트 진입/이탈 시 UI 갱신 가능. _AuthGate 등은 그냥 매번 읽음.
  static final ValueNotifier<bool> isGuestNotifier = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isGuestNotifier.value = prefs.getBool(_kKey) ?? false;
  }

  static Future<bool> isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKey) ?? false;
  }

  // 동기적으로 현재 상태 — load() 이후 또는 setGuest/clear 이후엔 정확함.
  static bool get currentlyGuest => isGuestNotifier.value;

  static Future<void> setGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
    isGuestNotifier.value = true;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
    isGuestNotifier.value = false;
  }
}
