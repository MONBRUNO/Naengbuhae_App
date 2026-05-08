// 기본 스모크 테스트 — 앱이 빌드되는지만 확인.
// 본격 테스트는 백엔드 mock + Flutter integration test 도입 후.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naengbuhae_app/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const NaengbuhaeApp());
    // _AuthGate가 FutureBuilder로 시작 — 초기엔 로딩 인디케이터
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
