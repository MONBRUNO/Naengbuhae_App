# Naengbuhae_App

냉부해 모바일 앱 (Flutter).

> 백엔드: [`Naengbuhae_Team_backend`](https://github.com/impactice/Naengbuhae_Team_backend) (`chore/db-setting` 브랜치)
> 웹: [`Naengbuhae_Team`](https://github.com/impactice/Naengbuhae_Team)

---

## 🆕 이번 작업 정리 (2026-05-13)

이번 세션의 큰 줄기:
1. **메인 화면 5개 완성** — 홈/식재료/우선순위/장보기/마이페이지 + 하단 네비
2. **AI 사진 인식** — 식재료 단건 카메라 인식 + 영수증 OCR 화면
3. **다중 냉장고 + 가족 공유** — 헤더 칩으로 전환, 관리 화면에서 초대/멤버 관리
4. **비밀번호 찾기 화면**
5. **레시피 / 영양 분석 / 식단 추천** — 백엔드 기존 API와 연결

---

### 1) 메인 화면 5개 + 하단 네비게이션

`main_scaffold.dart`가 5개 탭(홈/식재료/우선순위/장보기/마이페이지)을 `IndexedStack`으로 묶어서 보관. 탭 전환 시 각 화면의 스크롤 위치/상태가 유지됨.

- `dashboard_screen.dart` — 홈. 우선순위 카드 + 레시피 추천 + 식단 추천 버튼
- `ingredients_screen.dart` — 식재료 목록. 카테고리 필터 + 검색
- `priority_screen.dart` — 유통기한 임박순 / 만료 식재료
- `shopping_screen.dart` — 장보기 리스트. 체크 토글, 냉장고로 이관
- `profile_screen.dart` — 마이페이지. 프로필/설정/로그아웃/탈퇴
- `recipes_screen.dart`, `recipe_detail_screen.dart` — 레시피 추천 + 상세
- `meal_plan_screen.dart` — 식단 추천 (백엔드 endpoint와 연결)
- `nutrition_screen.dart` — 영양 분석

**왜?**
- 앱이 reference 수준의 stub 상태였음 → 웹과 기능 패리티 확보. 백엔드 API는 이미 다 있어서 화면만 붙이면 됨
- `IndexedStack`을 쓴 이유: 탭 전환마다 화면이 dispose/init 되면 UX가 끊김 (스크롤이 위로 튐, fetch가 다시 발생)

---

### 2) AI 사진 인식 — 단건 + 영수증

`ingredient_edit_screen.dart` 카메라 버튼 → 갤러리/카메라 선택 → `POST /api/ingredients/recognize` → 폼 자동 채움.

영수증은 `receipt_recognition_screen.dart`에서 별도 흐름:
1. 영수증 사진 한 장 선택
2. `POST /api/ingredients/recognize-receipt` → 식재료 N건 추출
3. 편집 가능한 카드 리스트로 표시 (체크박스로 빼기, 수량/카테고리 수정)
4. 일괄 저장

**핵심 코드 (`api_client.dart` — uploadFile)**
```dart
// multipart 업로드. http.MultipartRequest는 fetch와 달리
// Content-Type을 자체적으로 boundary와 함께 설정한다 — 직접 설정 X.
Future<http.Response> uploadFile(String path, String fieldName, File file) async {
  Future<http.Response> send() async {
    final uri = Uri.parse('$baseUrl$path');
    final req = http.MultipartRequest('POST', uri);
    final token = await _storage.readAccessToken();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    final streamed = await req.send();
    return http.Response.fromStream(streamed);
  }

  var res = await send();
  if (res.statusCode == 401) {
    final refreshed = await _refreshAccessToken();
    if (refreshed) {
      res = await send();
    } else {
      _onLoggedOut.add(null);
    }
  }
  return res;
}
```

**알아둘 점**
- `image_picker` 패키지로 카메라/갤러리 동시 지원
- 백엔드는 사진을 저장하지 않음 — 인식 후 즉시 폐기
- 보관 방법(`storage`)은 AI가 추천 → 사용자 모르는 식재료에 합리적 기본값

---

### 3) 다중 냉장고 + 가족 공유

여러 냉장고에 속할 수 있고, 6자리 초대 코드로 다른 사용자를 끌어들임.

**`state/fridge_context.dart`**
앱 전역 싱글톤. `ValueNotifier`로 현재 선택된 냉장고와 목록을 관리. SharedPreferences에 선택 ID 캐싱.

```dart
class FridgeContext {
  static final FridgeContext instance = FridgeContext._();
  FridgeContext._();

  final ValueNotifier<List<Fridge>> fridges = ValueNotifier([]);
  final ValueNotifier<Fridge?> selected = ValueNotifier(null);

  Future<void> refresh() async {
    final res = await apiClient.get('/api/fridges');
    if (res.statusCode == 200) {
      fridges.value = (jsonDecode(res.body) as List).map((j) => Fridge.fromJson(j)).toList();
      // 마지막 선택 복원 또는 첫 번째 fridge로 폴백
      final lastId = await _prefs.then((p) => p.getInt('selectedFridgeId'));
      selected.value = fridges.value.firstWhere(
        (f) => f.id == lastId,
        orElse: () => fridges.value.first,
      );
    }
  }

  Future<void> select(Fridge f) async {
    selected.value = f;
    (await _prefs).setInt('selectedFridgeId', f.id);
  }
}
```

**`widgets/fridge_selector.dart`**
헤더에 표시되는 작은 칩 위젯. 탭하면 바텀시트로 냉장고 목록 + "냉장고 관리" 액션. `ValueListenableBuilder`로 자동 갱신.

**`screens/fridge_management_screen.dart`**
카드 그리드로 냉장고 목록 → 카드 탭 시 바텀시트에서 상세:
- 멤버 목록 (이메일/이름)
- 초대 코드 발급 + 클립보드 복사
- 이름 변경 / 삭제 / 나가기 액션
- 다른 코드 입력 → 새 냉장고 가입

**식재료 화면과의 연동**
- `ingredients_screen.dart`는 `FridgeContext.instance.selected`를 listen → 선택 바뀌면 자동 refetch
- `ingredient_edit_screen.dart`는 저장 시 현재 선택된 `fridgeId`를 body에 부착

**알아둘 점**
- 첫 로그인한 사용자는 백엔드가 자동으로 `<이름>의 냉장고`를 생성 → 앱은 빈 상태 처리 불필요
- 멤버 권한은 모두 동등 — 누구나 초대 가능, 누구나 떠날 수 있음

---

### 4) 비밀번호 찾기

`forgot_password_screen.dart` — 로그인 화면 하단의 "비밀번호를 잊으셨나요?" 링크에서 진입. 이메일 입력 → 백엔드가 메일 발송 → 메일 안의 링크는 일단 웹으로 (앱 딥링크는 추후).

**왜 웹으로?**
- iOS/Android 양쪽에 딥링크 등록(`AndroidManifest.xml`, `Info.plist`)이 필요한데 작업량 비례 가치가 낮음
- 비밀번호 재설정은 거의 안 일어남 → 웹 경유해도 사용자 마찰이 적음
- 시간 생기면 `uni_links` 패키지로 추가 예정 (추후 작업)

---

### 5) 레시피 / 영양 분석 / 식단 추천

백엔드의 기존 엔드포인트 그대로 사용:
- `recipes_screen.dart` — `GET /api/recipes/recommendations` (백엔드가 사용자 보유 재료로 매칭률 계산해서 정렬)
- `recipe_detail_screen.dart` — 재료 / 단계 / 영양 표시
- `nutrition_screen.dart` — 도넛 차트로 일/주 단위 영양 비율
- `meal_plan_screen.dart` — 보유 재료 기반 1주일 식단 추천

차트는 `widgets/donut_chart.dart`, `widgets/bar_chart.dart`로 자체 구현 — 외부 차트 라이브러리 안 씀 (gradle 의존 트리 깔끔하게 유지).

---

## 기술 스택

- Flutter 3.41.x / Dart 3.11
- 타깃: Android + iOS
- HTTP: `http` 패키지
- 토큰 저장: `flutter_secure_storage` (Android Keystore / iOS Keychain)
- 이미지: `image_picker` (카메라/갤러리)
- 캐시: `shared_preferences` (선택된 냉장고 등 가벼운 상태)
- 아이콘: `lucide_icons_flutter` (웹과 통일된 아이콘셋)

## 시작하기

### 사전 준비물

| 필요한 것 | 확인 명령 |
|---|---|
| Flutter SDK 3.41.x | `flutter --version` |
| Android SDK + Platform 35 | `flutter doctor` |
| JDK 17 (`android/app/build.gradle.kts`에서 강제) | `java -version` |
| Android 에뮬레이터 또는 실기기 | `flutter devices` |

`flutter doctor`로 부족한 항목을 한 번에 확인할 수 있다.

### 실행

```bash
flutter pub get
flutter run
```

### 트러블슈팅: `Error connecting to the service protocol`

Flutter SDK / Android SDK 업그레이드 직후 첫 빌드에서 가끔 VM Service 연결이 실패할 수 있다 (`flutter_secure_storage`의 네이티브 초기화와 핸드셰이크 타이밍 충돌). 다음 순서로 해결:

```bash
flutter clean
flutter pub get
flutter run --host-vmservice-port=8888 --disable-service-auth-codes
```

- `flutter clean`: 꼬인 빌드 캐시(`build/`, `.dart_tool/`) 비움
- `--host-vmservice-port=8888`: 랜덤 포트 대신 고정 포트 사용
- `--disable-service-auth-codes`: WebSocket 인증 토큰 협상 생략

두 번째 빌드부터는 캐시가 따뜻해져서 `flutter run`만으로 정상 동작한다. `--disable-service-auth-codes`는 보안상 같은 PC 개발 환경에서만 사용 (외부 네트워크 노출 X).

### 백엔드 URL

`lib/api/api_client.dart`의 `baseUrl`이 자동으로 환경에 맞게 결정됨:

| 환경 | baseUrl |
|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:8080` (호스트의 localhost) |
| iOS 시뮬레이터 | `http://localhost:8080` |
| 실기기 | 같은 네트워크의 PC IP 또는 ngrok URL — 코드 직접 수정 필요 |

> 실기기 테스트 시 PC IP로 변경하고 PC 방화벽에서 8080 허용 필요.

## 디렉토리 구조

```
lib/
├── main.dart                          # 진입점 + 테마 + AuthGate
├── api/
│   ├── api_client.dart                # 401 → refresh → retry, multipart 업로드 포함
│   └── auth_storage.dart              # OS 보안 저장소 (Keystore/Keychain)
├── state/
│   └── fridge_context.dart            # 전역 냉장고 상태 (ValueNotifier)
├── screens/
│   ├── login_screen.dart              # 로그인
│   ├── signup_screen.dart             # 회원가입
│   ├── forgot_password_screen.dart    # 비밀번호 찾기
│   ├── main_scaffold.dart             # 5탭 IndexedStack + 하단 네비
│   ├── dashboard_screen.dart          # 홈
│   ├── ingredients_screen.dart        # 식재료 목록
│   ├── ingredient_edit_screen.dart    # 식재료 추가/수정 (+카메라 AI 인식)
│   ├── receipt_recognition_screen.dart # 영수증 일괄 인식
│   ├── priority_screen.dart           # 우선순위
│   ├── shopping_screen.dart           # 장보기
│   ├── recipes_screen.dart            # 레시피 추천
│   ├── recipe_detail_screen.dart      # 레시피 상세
│   ├── meal_plan_screen.dart          # 식단 추천
│   ├── nutrition_screen.dart          # 영양 분석
│   ├── profile_screen.dart            # 마이페이지
│   ├── profile_edit_screen.dart       # 프로필 수정
│   └── fridge_management_screen.dart  # 냉장고 관리 (초대/멤버)
├── widgets/
│   ├── fridge_selector.dart           # 헤더 냉장고 칩
│   ├── donut_chart.dart               # 영양 비율 도넛
│   └── bar_chart.dart                 # 영양 막대
└── utils/
    ├── expiry.dart                    # D-day 계산
    ├── expiry_defaults.dart           # 식재료별 기본 보관/유통기한 매핑
    └── format.dart                    # 숫자/날짜 포맷
```

## 백엔드 인증 모델

웹 프론트와 동일:
- access token (JWT, 30분) + refresh token (UUID, 365일)
- access 만료 시 `ApiClient`가 자동으로 `/user/token/refresh` 호출 → 1회 재시도
- refresh도 실패하면 `onLoggedOut` 스트림으로 알리고 토큰 정리 (UI에서 듣고 로그인 화면으로)

웹의 sessionStorage/localStorage 분기는 모바일에선 불필요 — 앱은 자체 샌드박스라 secure_storage 하나로 통일.

## 추후 작업

- [ ] OAuth 소셜 로그인 (카카오/구글/네이버 WebView 또는 `flutter_appauth`)
- [ ] FCM 푸시 알림 (유통기한 임박 — D-1, 당일)
- [ ] 비밀번호 재설정 메일 링크 → 앱 딥링크 (`uni_links`)
- [ ] 이메일 인증 안 한 사용자에게 프로필 화면에서 배너 + 재발송 버튼
