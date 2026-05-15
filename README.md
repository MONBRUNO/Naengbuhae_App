# Naengbuhae_App

냉부해 모바일 앱 (Flutter).

> 백엔드: [`Naengbuhae_Team_backend`](https://github.com/impactice/Naengbuhae_Team_backend) (`chore/db-setting` 브랜치)
> 웹: [`Naengbuhae_Team`](https://github.com/impactice/Naengbuhae_Team)

---

## 🆕 이번 작업 정리 (2026-05-15)

### 1) 비로그인 게스트 모드

토큰 없이도 식재료 관리만 쓸 수 있게, 가입은 의향 있는 사람만.

- **진입**: 로그인 화면 **로그인 버튼 바로 아래** 작은 텍스트 버튼 "로그인 없이 둘러보기" (회원가입만 있는 줄 알고 이탈하지 않도록 노출 위치 조정)
- **로컬 식재료**: `LocalIngredientStore`가 SharedPreferences에 JSON으로 저장. id는 `-1, -2, ...` 음수로 발급해 서버 id와 충돌 회피
- **분기 레이어**: `IngredientRepo`가 모든 `/api/ingredients` 호출을 한 곳으로 모음 → `GuestMode.isGuest()` 검사 후 로컬 또는 API
- **가상 단일 냉장고**: `FridgeContext.load()`가 게스트면 서버 호출 없이 가상 냉장고(id=-1, "내 냉장고") 세팅
- **잠금 기능**: `LoginRequired` 다이얼로그로 영양 분석 / 레시피 / 식단 추천 / 영수증 인식 / 장보기 진입 차단
- **ProfileScreen 게스트 변형**: `/user/me` 호출 없이 가입/로그인 CTA + 잠금 기능 미리보기
- **로그인 시 마이그레이션**: `IngredientMigration.promptAndMigrate`가 `/api/ingredients/import` 호출 → 로컬 데이터 일괄 이전 후 로컬 정리

### 2) 회원가입 인라인 이메일 인증 (코드 방식)

매직 링크 → 6자리 코드 인라인 입력 방식으로 전환.

- 이메일 옆 "**인증번호 받기**" 버튼 → 6자리 코드 메일 발송
- 코드 입력 + "**확인**" → 검증 통과 시 "인증완료" 뱃지 표시 + 이메일 입력 칸 잠금
- 이메일을 바꾸면 `onChanged`에서 인증 상태 자동 무효화 (재발송 필요)
- 가입 폼 제출 시 `_verifiedEmail == _email.text.trim()` 재확인 가드
- 엔드포인트: `POST /user/email/send-code`, `POST /user/email/verify-code`

### 3) 회원가입 후 username 자동 채우기

가입 성공 → `Navigator.pop<String>(_username.text.trim())`로 username을 LoginScreen에 전달 → controller에 채워줌. 사용자는 비번만 치면 됨.

### 4) 비밀번호 변경 화면

- `screens/change_password_screen.dart`: 현재 비번 + 새 비번(확인) → `POST /user/me/password`
- ProfileScreen 회원 탈퇴 위에 진입 버튼 추가, `provider == 'LOCAL'`일 때만 노출 (소셜 가입자는 비번 변경 불가)

### 5) 식재료 / 장보기 다중 선택 일괄 삭제

- 두 화면 모두 같은 패턴: 헤더 우측 "선택" 버튼 → 진입 시 우측 "취소" / 카드 탭으로 토글 / 상단 액션 바 "전체 선택 + N개 삭제"
- `IngredientRepo.bulkDelete(List<int>)` — 게스트면 로컬 순차 삭제, 로그인이면 `/api/ingredients/bulk-delete` 단일 요청
- 장보기는 `/api/shopping-list/bulk-delete`. 미완료/완료 섹션 모두 선택 가능. 선택 모드에선 토글/이관/삭제 개별 버튼 숨김

### 6) 알림 탭 → 정확한 식재료로 이동

`NotificationRouter`가 `"ingredient:{id}"` 패턴 인식:

- `IngredientRepo.list`로 목록 fetch → 해당 id 찾기 → `IngredientEditScreen(existing: item)` push
- 이미 삭제된 식재료(가족이 비움)면 식재료 탭으로 폴백
- 기존 `expiry` / `ingredients` / `meal` / `fridge` 분기는 그대로

### 7) 가족 활동 통계 차트 시각화

- **멤버별 활동**: 한 멤버당 추가(녹색) / 비움(주황) **그룹형 막대 차트** (인라인 구현 — `SimpleBarChart`로는 단일 막대만 가능해서 별도)
- **자주 추가/비운 식재료 TOP5**: `DonutChart` 위젯 + 색깔 범례 5단계 (`_pieGreens` / `_pieOranges`)
- 차트 위, 기존 멤버 행/랭크 리스트는 그대로 유지 → 한눈에 + 상세 모두

### 8) 죽은 매직 링크 흔적 정리

코드 기반 가입 인증으로 전환되며 안 쓰이는 코드 제거:

- `ProfileScreen`의 `_EmailVerificationBanner` 위젯 + 분기 제거
- `LoginScreen`의 `_pendingEmail` / `_verificationSent` / `_resending` 상태 + 배너 위젯 + `_resendVerification` 메서드 제거

---

## 이전 작업 정리 (2026-05-14)

**알림 기능 + OAuth 소셜 로그인 + 식재료 검색 + 가족 활동 통계.**

알림:
1. **유통기한 임박 알림** — 매일 오전 9시, D-3 ~ D-0 항목을 본문에 묶어서 표시 (로컬 알림, 앱 안 열어도 동작)
2. **식단 추천 알림** — 사용자가 설정한 아침/점심/저녁 시각의 **10분 전**에 "오늘 점심 식단: ㅇㅇㅇ" 형태 (로컬 알림)
3. **멤버/초대 푸시** — 누가 내 냉장고에 합류하면 기존 멤버 전원에게, 본인이 제거되면 본인에게 (FCM)
4. **식재료 추가/삭제 푸시** — 가족 멤버 누가 사과 5개를 넣으면 나머지 전원에게, 다 떨어졌다고 지우면 나머지 전원에게 (FCM)
5. **프로필 화면 알림 설정** — 마스터/유통기한/식단 토글 + 식사 시간 3개 picker, 변경 즉시 재예약
6. **알림 탭 → 해당 화면 진입** — 유통기한·식재료 알림은 식재료 탭, 식단은 식단 화면, 멤버 알림은 냉장고 관리 화면으로
7. **인앱 알림 센터** — 받은 알림(FCM)을 DB에 영속화해서 마이페이지에서 히스토리 + 안읽은 수 뱃지

로그인:

8. **OAuth 소셜 로그인 (카카오/네이버/구글)** — placeholder 버튼을 실제 WebView 흐름으로 연결

식재료 화면:

9. **이름 검색 + 만료된 것만 보기 토글** — 카테고리·보관·정렬 위에 검색창, 아래에 만료 토글 chip (D-day < 0)

가족 공유:

10. **가족 활동 통계** — 멤버별 추가/소비 카운트 + 자주 추가/비우는 식재료 TOP 5. 7/30/90일 기간 토글

---

### 1) 로컬 알림 인프라

`flutter_local_notifications` + `timezone` + `flutter_timezone`.

- Android `POST_NOTIFICATIONS` (13+) / `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` / `RECEIVE_BOOT_COMPLETED` 권한
- 재부팅 후 자동 재예약 receiver 등록 (`AndroidManifest.xml`)
- `coreLibraryDesugaring` 활성 — `java.time` API를 Android 8 미만에서도 사용
- iOS는 `UIBackgroundModes`에 `remote-notification` + `fetch`

`lib/services/notification_service.dart`가 진입점. 호출 패턴은 "데이터 fetch 후 reschedule":

```dart
// 식재료 목록 fetch 직후
await NotificationService.rescheduleExpiryNotifications(items);

// 식단 fetch 직후 (오늘분)
await NotificationService.rescheduleMealNotifications(
  breakfast: todays?.breakfast,
  lunch: todays?.lunch,
  dinner: todays?.dinner,
);
```

내부 동작:
- 기존 예약 모두 cancel → 다음 7일치 새로 예약 (유통기한)
- 다음 7일치를 미리 잡아두는 이유: 앱 안 열어도 알림이 와야 하므로
- 식단은 오늘분만 — 다음 날엔 앱 열 때 갱신
- 정확 알람 권한 거부 시 `inexactAllowWhileIdle`로 자동 폴백

---

### 2) FCM (서버 트리거 푸시)

`firebase_core` + `firebase_messaging`.

`lib/services/fcm_service.dart`:
- 로그인 직후 `getToken()` → 서버 `POST /user/fcm-tokens` 등록
- 로그아웃 직전 `DELETE /user/fcm-tokens/{token}`
- `onTokenRefresh` 구독 → 갱신 시 자동 재등록
- 포그라운드 메시지는 로컬 알림으로 띄움 (FCM이 포그라운드에선 자동 표시 안 함)
- **`google-services.json` 미배치여도 앱은 정상 기동** — `Firebase.initializeApp()` 실패만 로깅하고 로컬 알림만 동작

서버 측은 [백엔드 README](https://github.com/impactice/Naengbuhae_Team_backend) 참고. 현재 발송 시점:

| 트리거 | 수신자 | 본문 예 | route |
|---|---|---|---|
| 멤버 합류 (`FridgeService.joinByCode`) | 기존 멤버 전원 | "OO님이 'XX'에 참여했습니다" | `fridge` |
| 멤버 제거 (`FridgeService.removeMember`) | 제거된 본인 | "'XX'에서 더 이상 멤버가 아닙니다" | `fridge` |
| 식재료 추가 (`IngredientService.saveIngredient`) | 같은 냉장고 다른 멤버 | "OO님이 'XX'에 사과 5개를 넣었어요" | `ingredients` |
| 식재료 삭제 (`IngredientService.deleteIngredient`) | 같은 냉장고 다른 멤버 | "OO님이 'XX'에서 사과를 비웠어요" | `ingredients` |

행위자 본인은 항상 제외 — 자기가 한 행동을 자기가 받을 필요 없음. 멤버가 본인 1명이면 발송 대상 0명이라 무음.

---

### 3) 프로필 알림 설정 섹션

`lib/widgets/notification_settings_section.dart` — 프로필 화면 안에 카드로 박혀있는 위젯.

- 전체 알림 마스터 토글 (Off 시 `cancelAll()`)
- 유통기한 알림 토글 (시간 고정: 매일 9시)
- 식단 알림 토글 + 아침/점심/저녁 시간 picker

설정 변경 시 `NotificationService.rescheduleFromCache()` 호출 — 마지막으로 fetch한 식재료/식단 데이터를 메모리 캐시에서 꺼내 즉시 재예약. 사용자가 토글하자마자 다음 알림이 새 설정대로 잡힘.

영속화는 `lib/state/notification_settings.dart` (SharedPreferences + ValueNotifier).

---

### 4) 트리거 지점

| 화면 / 시점 | 호출 |
|---|---|
| `main.dart` 진입 | `NotificationSettings.load()` + `NotificationService.init()` + `FcmService.init()` |
| `MainScaffold.initState` | 식재료 한 번 prefetch → expiry 예약 |
| `LoginScreen` 성공 직후 | 알림 권한 요청 + FCM 토큰 등록 |
| `IngredientsScreen._fetch` 후 | expiry 재예약 |
| `MealPlanScreen._fetch` 후 | meal 재예약 |
| 설정 토글/시간 변경 | `rescheduleFromCache()` |
| 로그아웃 | FCM 토큰 폐기 |

---

### 5) 알림 탭 라우팅

`lib/services/notification_router.dart`가 payload/route 키를 받아 화면 분기.

| 출처 | 키 | 이동 |
|---|---|---|
| 로컬 (유통기한) | payload `expiry` | 식재료 탭 (index 1) |
| 로컬 (식단) | payload `meal` | `MealPlanScreen` push |
| FCM (멤버/초대) | `data.route=fridge` | `FridgeManagementScreen` push |
| FCM (식재료 추가/삭제) | `data.route=ingredients` | 식재료 탭 (index 1) |

**진입 상태 3가지 모두 커버**:
- **포그라운드** — 사용자가 이미 앱 보고 있으므로 자동 라우팅 안 함 (알림만 띄움)
- **백그라운드** — `onDidReceiveNotificationResponse` (로컬) / `onMessageOpenedApp` (FCM)
- **콜드 스타트** — `getNotificationAppLaunchDetails()` (로컬) / `getInitialMessage()` (FCM). `microtask`로 미뤄서 navigator mount 이후 push

**탭 인덱스 외부 제어**

`lib/state/tab_index.dart`로 `MainScaffold`의 탭 인덱스를 ValueNotifier로 노출 — 알림 핸들러가 위젯 외부에서도 `TabIndex.select(1)`로 식재료 탭 점프 가능.

**서버 측 페이로드 형식**

```java
// FcmService.sendToUsers(users, title, body, route)
Message.builder()
    .setNotification(Notification.builder().setTitle(...).setBody(...).build())
    .putAllData(Map.of("route", "fridge"))   // 앱이 이 값으로 분기
    .build();
```

---

### 6) 인앱 알림 센터

FCM 푸시는 휘발성이라 놓치면 끝 — DB에 영속화해서 마이페이지에서 다시 볼 수 있게.

**`lib/screens/notification_center_screen.dart`**

- 진입 시 `GET /api/notifications` (최신 50개) + `POST /api/notifications/read-all` 자동 호출 (본 시점에 읽음 처리)
- 항목 탭 시 `route` 키로 `NotificationRouter.route()` 호출 → 해당 화면으로 점프
- 안읽은 항목은 lime-yellow 배경 + 좌측 dot로 구분

**진입점**

마이페이지 상단의 **"알림"** 카드. 안읽은 수 > 0일 때 우측에 빨간 뱃지 표시.

- 마이 탭 진입 시 `GET /api/notifications/unread-count` 호출
- 센터에서 돌아오면 자동으로 0 처리 (서버에서 이미 read-all 됨)

**서버 측 동작**

- `AppNotificationService`가 모든 FCM 발송의 단일 진입점 — DB row 영속화 + `FcmService.send*` 호출을 함께 수행
- `FridgeService` / `IngredientService`가 `fcmService`를 직접 부르지 않고 `appNotificationService`만 사용 → 푸시 누락 없이 히스토리에 남음
- 회원 탈퇴 시 `notificationRepository.deleteByUser`로 정리

---

### 7) OAuth 소셜 로그인

`webview_flutter`로 백엔드의 OAuth 흐름을 인앱 WebView에서 진행 — 토큰을 콜백 URL에서 가로채는 방식.

**`lib/screens/oauth_webview_screen.dart`**

```
1. <baseUrl>/oauth2/authorization/{provider} 로드
2. Spring이 카카오/구글/네이버 로그인 페이지로 302 redirect
3. 사용자 로그인 → 제공자가 <baseUrl>/login/oauth2/code/{provider} 콜백
4. OAuth2SuccessHandler가 frontend-redirect URL로
   ?token=...&refreshToken=...&needsAdditionalInfo=... 붙여 302
5. WebView가 그 URL을 로드하기 직전 NavigationDelegate에서 가로채서 토큰 추출 → pop
```

`oauth/callback` 패턴만 인식하므로 frontend-redirect URL 자체는 실제 도달 가능할 필요 없음 (localhost:5173이라도 무관).

**`lib/screens/login_screen.dart` 소셜 버튼 핸들러**

```dart
final result = await Navigator.push<OAuthResult>(...);
await AuthStorage.save(accessToken: result.accessToken, refreshToken: result.refreshToken);
NotificationService.requestPermission();
FcmService.registerCurrentToken();
Navigator.pushReplacement(MaterialScaffold(...));
```

**전제**

- 백엔드의 `KAKAO_CLIENT_ID` / `GOOGLE_CLIENT_ID` / `NAVER_CLIENT_ID` 등 `.env` 설정
- 각 제공자 개발자 콘솔에 redirect URI 등록: `<baseUrl>/login/oauth2/code/{provider}`
- 개발 시 안드로이드 에뮬레이터의 `10.0.2.2:8080`은 일부 제공자(특히 카카오)가 redirect URI로 거부 → ngrok HTTPS 터널 또는 배포된 서버 URL 사용 권장
- 추가 정보 미입력 시(신체정보 등) 백엔드가 `needsAdditionalInfo=true`로 알려줌 → 메인 진입 후 프로필 미완성 배너로 노출됨

---

### 8) 식재료 검색 + 만료 토글

`ingredients_screen.dart`에 `_searchQuery`와 `_showExpiredOnly` 상태 추가.

- **검색창**: 카테고리/보관/정렬 필터 위에 `TextField` + suffix clear 버튼. `name.toLowerCase().contains(query)` 부분 일치
- **만료 토글**: 필터 row 아래 체크 chip. `calculateDDay(...) < 0` 항목만 (오늘 만료는 제외)
- `_filtered` getter에 두 조건 합산 (카테고리 → 보관 → 검색 → 만료 → 정렬)

웹 프론트(`Naengbuhae_Team/Smart Ingredient Management App/src/app/pages/Ingredients.tsx`)도 동일 UX로 동시에 추가.

> 알림 센터·가족 활동 통계도 웹에 함께 붙임 (`/notifications`, `/family-activity`). [Naengbuhae_Team README](https://github.com/impactice/Naengbuhae_Team) 참고.

---

### 9) 가족 활동 통계

`lib/screens/family_activity_screen.dart`. 현재 선택된 냉장고 기준으로 백엔드에서 집계 가져옴.

**`GET /api/fridges/{id}/activity-stats?days=N`** 응답:

```json
{
  "fridgeId": 1,
  "fridgeName": "우리집 냉장고",
  "periodDays": 30,
  "members": [
    {"username": "alice", "name": "앨리스", "added": 12, "removed": 8},
    {"username": "bob", "name": "밥", "added": 5, "removed": 7}
  ],
  "topAdded": [{"name": "사과", "count": 5}],
  "topRemoved": [{"name": "우유", "count": 3}]
}
```

화면 구성:
- 헤더 카드 — 냉장고 이름 + 전체 추가/비움 카운트
- 기간 chips (7/30/90일) — 변경 시 즉시 refetch
- 멤버별 활동 row — `+N -N` 뱃지로 추가/소비 표시
- 자주 추가/비운 식재료 TOP 5 — 1~5 순위 + 막대 바 (`maxCount` 기준 비율)

**진입점**: 마이페이지 "가족 활동" 카드.

**데이터 소스**: 백엔드 `ActivityLog` 엔티티 (행위자/액션/식재료명/생성시각). `Notification`은 수신자 관점이라 통계에 부적합해서 별도 테이블로 분리.

---

## 더 이전 작업 정리 (2026-05-13)

이전 세션의 큰 줄기:
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
- 캐시: `shared_preferences` (선택된 냉장고 / 알림 설정)
- 아이콘: `lucide_icons_flutter` (웹과 통일된 아이콘셋)
- 알림: `flutter_local_notifications` + `timezone` (로컬) / `firebase_messaging` (푸시)
- OAuth: `webview_flutter` (카카오/구글/네이버 인앱 WebView)

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
├── main.dart                          # 진입점 + 테마 + AuthGate + 알림 초기화
├── api/
│   ├── api_client.dart                # 401 → refresh → retry, multipart 업로드 포함
│   └── auth_storage.dart              # OS 보안 저장소 (Keystore/Keychain)
├── services/
│   ├── notification_service.dart      # 로컬 알림 스케줄 (유통기한 9시 / 식단 10분 전)
│   ├── fcm_service.dart               # FCM 초기화 + 토큰 서버 등록
│   └── notification_router.dart       # 알림 탭 시 화면 분기 (전역 navigatorKey)
├── state/
│   ├── fridge_context.dart            # 전역 냉장고 상태 (ValueNotifier)
│   ├── notification_settings.dart     # 알림 설정 (SharedPreferences + ValueNotifier)
│   └── tab_index.dart                 # MainScaffold 탭 인덱스 외부 제어용
├── screens/
│   ├── login_screen.dart              # 로그인 (+ OAuth 소셜 버튼)
│   ├── signup_screen.dart             # 회원가입
│   ├── forgot_password_screen.dart    # 비밀번호 찾기
│   ├── oauth_webview_screen.dart      # OAuth 인앱 WebView (콜백 URL에서 토큰 가로챔)
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
│   ├── profile_screen.dart            # 마이페이지 (+ 알림 진입점 + 알림 설정 섹션)
│   ├── profile_edit_screen.dart       # 프로필 수정
│   ├── notification_center_screen.dart # 인앱 알림 센터 (히스토리)
│   ├── family_activity_screen.dart    # 가족 활동 통계 (멤버 카운트 + TOP)
│   └── fridge_management_screen.dart  # 냉장고 관리 (초대/멤버)
├── widgets/
│   ├── fridge_selector.dart           # 헤더 냉장고 칩
│   ├── notification_settings_section.dart # 프로필 안 알림 설정 카드
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

## Firebase 셋업 (FCM 푸시용)

`google-services.json` 없어도 앱 빌드/실행은 가능 — 단 멤버/초대 푸시는 동작 안 함 (로컬 알림은 정상). 활성화하려면:

1. [Firebase Console](https://console.firebase.google.com)에서 프로젝트 생성
2. **Android 앱 추가** — 패키지명 `com.naengbuhae.naengbuhae_app` → `google-services.json` 다운로드 → `android/app/google-services.json`에 배치
3. **iOS 앱 추가** (필요 시) — `GoogleService-Info.plist` 다운로드 → Xcode에서 `Runner` 타깃에 추가
4. 백엔드 측 service account JSON 셋업은 [백엔드 README](https://github.com/impactice/Naengbuhae_Team_backend) 참고

## 추후 작업

- [x] OAuth 소셜 로그인 (카카오/구글/네이버 WebView)
- [x] FCM 푸시 알림 (~~유통기한 임박 — D-1, 당일~~ → 유통기한은 로컬로 전환, FCM은 멤버/초대 이벤트 전용)
- [x] 알림 탭 시 해당 화면으로 진입 (payload + FCM data.route 분기)
- [x] 이메일 인증 안 한 사용자에게 프로필 화면에서 배너 + 재발송 버튼 (`_EmailVerificationBanner`)
- [ ] 비밀번호 재설정 메일 링크 → 앱 딥링크 (`uni_links`)
