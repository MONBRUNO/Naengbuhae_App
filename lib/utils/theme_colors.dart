import 'package:flutter/material.dart';

// 다크 모드 분기용 헬퍼. 화면 코드에서 `context.cardBg` 같이 호출.
// 웹(theme.css)의 디자인 외주 토큰과 동일한 팔레트 — warm-neutral 다크,
// off-white primary CTA, sky 액센트. 라이트는 브랜드 라임 유지.
extension ThemeColorsContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // 카드 표면 (웹 --card #191C20)
  Color get cardBg => isDark ? const Color(0xFF191C20) : const Color(0xFFF5F5F5);

  // 더 옅은/배경 박스 (웹 --background #08090A)
  Color get boxBg => isDark ? const Color(0xFF08090A) : const Color(0xFFF9FAFB);

  // 떠 있는 표면 / 카드 안 카드 (웹 --secondary #23272D)
  Color get surfaceBg => isDark ? const Color(0xFF23272D) : Colors.white;

  // 보더 (웹 --border rgba(255,255,255,0.05) ≈ 표면 위 옅은 선)
  Color get borderColor => isDark ? const Color(0xFF2A2E33) : const Color(0xFFE5E7EB);

  // 옅은 보더
  Color get lightBorderColor => isDark ? const Color(0xFF1F2227) : const Color(0xFFF3F4F6);

  // 메인 텍스트 (웹 --foreground #F2F3EE)
  Color get textColor => isDark ? const Color(0xFFF2F3EE) : Colors.black;

  // 보조 텍스트 (웹 --muted-foreground rgba(242,243,238,0.62))
  Color get subTextColor => isDark ? const Color(0x9EF2F3EE) : const Color(0xFF6B7280);

  // 더 옅은 텍스트
  Color get hintTextColor => isDark ? const Color(0x73F2F3EE) : const Color(0xFF9CA3AF);

  // primary CTA 배경 (식재료 추가하기 등)
  // 라이트: #CDFF00 형광 라임 (브랜드) / 다크: off-white #F2F3EE (네온 제거, 외주 디자인)
  Color get accentColor => isDark ? const Color(0xFFF2F3EE) : const Color(0xFFCDFF00);

  // primary 그라데이션 깊은 쪽
  Color get accentDeep => isDark ? const Color(0xFFD8D9D2) : const Color(0xFFB8E600);

  // primary 위 글자 (라이트=라임 위 검정 / 다크=off-white 위 진한색)
  Color get onAccent => isDark ? const Color(0xFF0A0B0A) : Colors.black;

  // sky 소프트 액센트 (AI/추천 아이콘·진행바 전용 — 웹 --accent #8BCEEA)
  Color get skyAccent => isDark ? const Color(0xFF8BCEEA) : const Color(0xFF2563EB);

  // 상태색 (웹 --status-* 다크 튜닝값과 통일)
  Color get statusDanger => isDark ? const Color(0xFFFF5A5F) : const Color(0xFFFF3B30);
  Color get statusWarning => isDark ? const Color(0xFFF5C44A) : const Color(0xFFFFD60A);
  Color get statusSafe => isDark ? const Color(0xFF34D97A) : const Color(0xFF34C759);
}
