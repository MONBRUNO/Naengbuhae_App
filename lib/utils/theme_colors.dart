import 'package:flutter/material.dart';

// 다크 모드 분기용 헬퍼. 화면 코드에서 `context.cardBg` 같이 호출.
// Material 3 colorScheme로 다 가는 게 이상적이지만 기존 색이 명시적으로 박혀있어
// 점진적 이행 단계에서 라이트/다크 두 값을 분기.
extension ThemeColorsContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // 카드 배경 (Color(0xFFF5F5F5) 대체)
  Color get cardBg => isDark ? const Color(0xFF1F2937) : const Color(0xFFF5F5F5);

  // 더 옅은 박스 (Color(0xFFF9FAFB) 대체)
  Color get boxBg => isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);

  // 흰 박스 (Colors.white 대체) — 카드 안 카드 같은 경우
  Color get surfaceBg => isDark ? const Color(0xFF374151) : Colors.white;

  // 보더 (Color(0xFFE5E7EB) 대체)
  Color get borderColor => isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);

  // 옅은 보더 (Color(0xFFF3F4F6) 대체)
  Color get lightBorderColor => isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);

  // 메인 텍스트 (Colors.black 대체)
  Color get textColor => isDark ? Colors.white : Colors.black;

  // 보조 텍스트 (Color(0xFF6B7280) 대체) — 다크에서도 잘 보이도록 조금 밝게
  Color get subTextColor => isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);

  // 더 옅은 텍스트 (Color(0xFF9CA3AF) 대체)
  Color get hintTextColor => isDark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF);

  // 브랜드 액센트 (식재료 추가하기 같은 primary 버튼 배경)
  // 라이트: #CDFF00 형광 라임 (브랜드), 다크: 채도/명도 낮춘 라임 — 눈피로 감소
  Color get accentColor => isDark ? const Color(0xFFA3CC0E) : const Color(0xFFCDFF00);

  // 액센트 위 글자 (둘 다 검정 — 라임 배경에서 검정이 가독성 최고)
  Color get onAccent => Colors.black;
}
