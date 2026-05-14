import 'package:flutter/foundation.dart';

// MainScaffold가 표시할 탭 인덱스를 외부에서 바꿀 수 있게 노출.
// 알림 탭 핸들러가 ValueNotifier 값을 변경하면 MainScaffold가 listen해서 해당 탭으로 점프.
class TabIndex {
  static final ValueNotifier<int> current = ValueNotifier<int>(0);

  static void select(int index) {
    current.value = index;
  }
}
