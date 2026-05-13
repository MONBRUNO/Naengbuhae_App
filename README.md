# Naengbuhae_App

냉부해 모바일 앱 (Flutter).

> 백엔드: [`Naengbuhae_Team_backend`](https://github.com/MONBRUNO/re_test) (`chore/db-setting` 브랜치)
> 웹: [`Naengbuhae_Team`](https://github.com/MONBRUNO/front)

---

## 기술 스택

- Flutter 3.41.x / Dart 3.11
- 타깃: Android + iOS
- HTTP: `http` 패키지
- 토큰 저장: `flutter_secure_storage` (Android Keystore / iOS Keychain)

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
├── main.dart              # 진입점 + 테마 + AuthGate
├── api/
│   ├── api_client.dart    # 401 → refresh → retry, 토큰 헤더 자동 부착
│   └── auth_storage.dart  # OS 보안 저장소 (Keystore/Keychain)
└── screens/
    ├── login_screen.dart  # 로그인 + 소셜 placeholder
    └── home_screen.dart   # 식재료 목록 (allergyWarnings 포함)
```

## 백엔드 인증 모델

웹 프론트와 동일:
- access token (JWT, 30분) + refresh token (UUID, 365일)
- access 만료 시 `ApiClient`가 자동으로 `/user/token/refresh` 호출 → 1회 재시도
- refresh도 실패하면 `onLoggedOut` 스트림으로 알리고 토큰 정리 (UI에서 듣고 로그인 화면으로)

웹의 sessionStorage/localStorage 분기는 모바일에선 불필요 — 앱은 자체 샌드박스라 secure_storage 하나로 통일.

## 추후 작업

- [ ] 회원가입 화면
- [ ] OAuth 소셜 로그인 (WebView 또는 `flutter_appauth`)
- [ ] 식재료 추가/수정/삭제 화면
- [ ] 레시피 추천 화면
- [ ] 장보기 리스트
- [ ] 영양 분석 / 우선순위
- [ ] 회원 정보 수정 / 탈퇴
- [ ] FCM 푸시 알림 (유통기한 임박)
- [ ] 카메라/갤러리로 식재료 사진 등록
