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

```bash
flutter pub get
flutter run
```

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
