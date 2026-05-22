# Naengbuhae_App

냉부해 모바일 앱 (Flutter).

> 백엔드: [`Naengbuhae_Team_backend`](https://github.com/impactice/Naengbuhae_Team_backend) (`develop` 브랜치, Render 배포: `https://naengbuhae.onrender.com`)
> 웹: [`Naengbuhae_Team`](https://github.com/impactice/Naengbuhae_Team)

---

## 🆕 이번 작업 정리 (2026-05-20)

### AI 통합 (capstone-ai FastAPI 서버 결합)

AI 담당자의 별도 서버(`Wldgyu/capstone-ai`, 포트 8000)에 있는 3개 endpoint를 앱에 통합. 백엔드에 프록시가 새로 생겨서(`/api/nutrition/analyze`, `/api/recipes/ai-for-food`, `POST /api/recipes/ai-recommendations`) 앱은 백엔드만 호출.

**AI 영양 검색 (`/analyze` 프록시)**
- `nutrition_screen.dart` 하단에 "다른 음식 영양 검색" 카드 — TextField + 검색 + 사진 업로드, 결과 카드 리스트
- `http.MultipartRequest` 직접 구성(text/file 필드). 토큰은 `AuthStorage.readAccessToken()`로 부착
- `ImagePicker(source: gallery)` → multipart `file`
- 에러 분기: 503(AI 서버 다운) / 429(rate limit)

**단일 식재료 요리 추천 (`/fdmake` 프록시)**
- 영양 검색 결과 카드에 "이 재료로 요리 추천" 버튼 — `/analyze → /fdmake` 파이프라인
- 카드별 인덱스 키로 추천/에러 상태 관리(`_recommendations` / `_recommendError` Map)
- 동시에 한 카드만 추천 받기(`_recommendingIdx`) — UX/Rate 보호

**AI 레시피 추천 페이지 분리 + 즐겨찾기 + 영속화**
- 기존 모달 → 별도 페이지 `ai_recommend_screen.dart` (Step 1: 식재료 선택 / Step 2: 요리 스타일 / 로딩 / 결과)
- 결과 클릭 시 `ai_recipe_detail_screen.dart` 상세 페이지 (기존 레시피 상세와 동일 흐름)
- 상세에 하트 아이콘으로 즐겨찾기 토글
- `state/ai_recipe_store.dart` (SharedPreferences) — `SavedAiRecipe(toJson/fromJson)` 저장. 결과 한 번 보면 날아가던 문제 해결
- `recipes_screen.dart` "전체" 탭 최상단에 AI 추천 섹션 — AppBar action `✨` 버튼으로 추천 화면 진입

**"1~3분 소요" 안내 + 그대로 노출**
- AI 서버 응답이 평균 1-2분(공공데이터 3페이지 + Gemini 2회). 정확도 위해 줄이기 어렵다는 담당자 의견 → "오래 걸리는 기능"으로 노출
- `_aiNutritionEnabled = true` 복귀 + amber 안내 문구 "⏱️ AI 분석은 정확도를 위해 공공데이터 + Gemini를 거쳐서 1~3분 정도 소요됩니다"
- 로딩 메시지: "AI가 분석 중입니다... (최대 3분)" / 백엔드 readTimeout 180초

### 식재료 카드 — 1열 컴팩트 + D-day 왼쪽 + 이모지 chip

초기엔 웹 `[디자인수정]` 따라 2열 그리드 + bottom sheet로 갔다가, 사용자 피드백("긴 이름 삭제버튼 침범" / "한 줄에 카드 하나만") 으로 1열 컴팩트로 재설계.

- `ListView.builder` 1열 — 각 카드는 Row: [D-day badge(왼쪽)] + [이름 + dot-separated 정보 + chips] + [삭제(세로 가운데)]
- D-day badge를 이름 왼쪽에 둬서 만료 임박 한눈에 보임
- 삭제 버튼은 `crossAxisAlignment: center` — 이름 줄바꿈돼도 안 따라감
- 이름 오른쪽에 카테고리 + 보관 chip — `_withEmoji(category)` 헬퍼로 이모지 prefix (🥦 채소 / 🥩 육류 / ❄️ 냉장 / 🧊 냉동 / 🌡 실온)
- `nutritionDatabase` 100g 기준 그대로 표시 (`quantity factor` 제거) — 가공 식품 영양정보는 일관성 위해 100g 단위가 표준

### 장보기 — "냉장고에 추가" + 수량 카운터 + 키보드 편집

**라벨/UX 변경**
- "냉장고 이관" → "냉장고에 추가" + 누르면 "[식재료]을(를) 구매하셨나요? 구매 완료로 표시하고 냉장고에 추가됩니다" confirm 다이얼로그

**[-] 수량 [+] 카운터**
- 항목 카드 옆 `_QuantityCounter` StatefulWidget — `Container + IntrinsicHeight + Row [InkWell(-), TextField, unit, InkWell(+)]`
- 1에서 [-] 누르면 "삭제하시겠습니까?" confirm → 삭제
- `PATCH /api/shopping-list/{id}/quantity` 호출 (백엔드 신규 endpoint)

**키보드 직접 편집**
- TextField로 숫자 직접 입력 가능 (`numberWithOptions(decimal: true)`)
- onSubmitted(Enter) / focusNode unfocus 시 자동 commit
- 외부에서 quantity 갱신되면 `didUpdateWidget`에서 controller 동기화 (사용자 입력 중엔 X)

**순서 보존**
- `_updateQuantity`가 `_fetch()` 대신 `setState`로 `_items` 해당 항목만 patch — 수량 바꾼다고 카드가 밑으로 안 내려감 (사용자 어지러움 방지)

---

## 이전 작업 정리 (2026-05-18)

### 버그 / 안정성

**Fridge UUID 마이그레이션 대응 (서버 연결 크래시 수정)**
- 백엔드가 Fridge id를 Long→UUID(문자열)로 마이그레이션(IDOR 방어). 앱이 id를 `as int?`로 캐스팅해 `String is not a subtype of int?` 런타임 크래시
- `fridge_context.dart`: `selectedId` getter `int?`→`String?`, 게스트 id `-1`→`'guest'`, 선택 저장 `getInt/setInt`→`getString/setString`, 과거 int 저장값 마이그레이션 가드
- `ingredient_repo.dart`: `list({int? fridgeId})`→`{String? fridgeId}`
- 나머지 소비처는 URL 보간/JSON/문자열 비교라 타입만 맞으면 동작

### 다크모드 / 디자인 (웹 토큰 전면 통일)

**전수 토큰 스윕**
- 위젯이 색을 하드코딩해 다크가 깨지던 것(흰 카드/빨강글씨/쨍한 그라데이션)을 `theme_colors` 토큰으로 일괄 전환 — 웹 시맨틱 토큰 방식과 동일 (13파일 89건)
- 회색텍스트→`subText/hintText`, 보더→`borderColor`, 밝은배경→`cardBg`, accent 위 글자→`onAccent`. 브랜드색/이미지 오버레이/이미 분기된 상태색/차트색은 보존

**컴포넌트별 웹 스펙 정렬**
- 알림설정 카드: 하드코딩 흰색 → `cardBg/borderColor/textColor` (눈부심 해결)
- 알레르기 주의: 다크에서 빨강 배경+빨강 글씨 → 밝은 레드 분기 (`profile`/`nutrition`/`recipe_detail` 3곳)
- 홈 식재료 상태 카드 & 레시피/식단 추천 버튼: 보라 그라데이션/색박스 → `cardBg`+`borderColor`, 아이콘 sky/blue (웹 Home과 동일)
- 일일 권장 칼로리: `Colors.black`(다크서 안보임) → 웹 `bg-foreground text-background`(크림 카드)
- 알림 배너(홈/우선순위): 새빨간 블록 → 다크 카드 + 4px 컬러 좌측바 + 컬러 아이콘
- 우선순위 위험/주의/안전 pill: 진한 단색 → status색 12% 옅은 틴트
- 나의맞춤 프로필 카드: 웹 `gray-800→900` 그라데이션, 아바타 `skyAccent`+흰 아이콘, 스탯박스 `boxBg`
- 맞춤기능 아이콘 색 복구(레시피=accent, 식단=blue, 우선순위=orange, 영양=green)

**레이아웃 이동**
- 알림 설정: 중간 인라인 제거 → 헤더 로그아웃 왼쪽 알림 아이콘 → 바텀시트
- 테마 선택: 권장 영양소 비율 아래로 (웹과 동일 순서)

### 폰트

**Pretendard 전역 적용**
- `assets/fonts/`에 Pretendard 1.3.9 static OTF 4 weight(Regular/Medium/SemiBold/Bold) + `pubspec.yaml` fonts 블록
- `main.dart` 라이트/다크 ThemeData `fontFamily: 'Pretendard'` (OFL 라이선스, 디버그 빌드 검증)

### 브랜드 / 로고

**로그인 화면 로고**
- `assets/brand/logo_full.png`(아이콘+워드마크 락업), `logo_icon.png`(아이콘 단독) — 투명 배경본
- 로그인 화면: "스마트 냉장고" 텍스트 → 풀 로고. 폼 너비 꽉 채움(`BoxFit.contain`)

### 계정 관리

**비밀번호 변경 위치 이동**
- 계정 관리(회원 탈퇴 위) → 회원 카드 탭 시 `ProfileEditScreen` 하단으로. `provider == 'LOCAL'`만 노출. profile_screen엔 회원 탈퇴만 남음

### 빌드

**FCM google-services 플러그인 조건부 적용**
- `android/app/build.gradle.kts` — `google-services.json` 있을 때만 적용. 없어도 빌드 진행(알림 로컬만)

### 기타

- 기본 테마 = 라이트 확인 (`theme_mode_pref.dart` 저장값 없으면 light, `main.dart` notifier 바인딩)

---

## 이전 작업 정리 (2026-05-15)

### 계정 관리

**비로그인 게스트 모드**
- 로그인 화면 "로그인 없이 둘러보기" — 로그인 버튼 바로 아래
- `LocalIngredientStore` (SharedPreferences, id=음수)로 로컬 식재료 CRUD
- `IngredientRepo`가 `GuestMode.isGuest()` 검사 후 로컬/서버 자동 분기
- 가상 단일 냉장고(id=-1) — `FridgeContext.load()`가 서버 호출 없이 세팅
- 잠금 기능 진입 시 `LoginRequired` 다이얼로그
- `ProfileScreen` 게스트 변형 — `/user/me` 호출 없이 가입/로그인 CTA
- 로그인 시 `IngredientMigration.promptAndMigrate`가 `/api/ingredients/import` 호출

**회원가입 인라인 이메일 인증 (코드 방식)**
- 이메일 옆 "인증번호 받기" → 6자리 코드 메일
- 코드 입력 + "확인" → "인증완료" 뱃지 + 이메일 입력 잠금
- 이메일 변경 시 인증 상태 자동 무효화
- 엔드포인트: `POST /user/email/send-code`, `POST /user/email/verify-code`

**회원가입 직후 로그인 화면에 username 자동 채우기**
- `Navigator.pop<String>(_username.text.trim())` → LoginScreen이 controller에 set

**비밀번호 변경 화면**
- `screens/change_password_screen.dart` — 현재 비번 + 새 비번(확인) → `POST /user/me/password`
- ProfileScreen 회원 탈퇴 위, `provider == 'LOCAL'`일 때만 노출

**죽은 매직 링크 흔적 정리**
- `ProfileScreen._EmailVerificationBanner` + `LoginScreen._pendingEmail/_verificationSent/_resending` 상태/위젯/메서드 모두 제거

---

### 식재료 / 장보기

**다중 선택 일괄 삭제 (식재료 + 장보기 두 화면)**
- 헤더 우측 "선택" 버튼 → 진입 시 "취소" / 카드 탭으로 토글 / 액션 바 "전체 선택 + N개 삭제"
- `IngredientRepo.bulkDelete(List<int>)` — 게스트면 로컬 순차, 로그인이면 `/api/ingredients/bulk-delete` 단일 요청
- 장보기는 `/api/shopping-list/bulk-delete`. 미완료/완료 섹션 모두 선택 가능

**식재료 카드 스와이프 제스처 (앱 전용)**
- 왼쪽으로 스와이프 → 소비 확인 다이얼로그 → 삭제 (빨간 배경 + "소비")
- 오른쪽으로 스와이프 → 수정 화면 이동 (파란 배경 + "수정")
- 선택 모드에선 비활성화 — 카드 탭으로 토글하는 흐름과 충돌 방지

**장보기 자동 제안 ("이건 어때요?")**
- 가족이 자주 비웠는데 지금 냉장고/장보기 모두에 없는 식재료를 가로 chip 5개로
- `GET /api/shopping-list/suggestions?fridgeId=X&limit=5` — `ActivityLog.INGREDIENT_REMOVED`(최근 60일) 카운트
- chip 탭 시 1개 단위 추가, 추가 후 `_fetch()`가 장보기/제안 동시 갱신

**레시피 부족 재료 자동 다이얼로그**
- `recipe_detail_screen` 진입 시 `WidgetsBinding.addPostFrameCallback`로 AlertDialog 자동 노출
- 부족 재료 quantity/unit까지 묶어 목록으로 미리보기
- "장보기에 추가" → `POST /api/shopping-list/bulk-add` 단일 요청
- 같은 레시피 다시 봐도 안 묻도록 `static Set _dismissedAskIds` (앱 종료 시 초기화)

---

### 레시피 즐겨찾기
- 레시피 카드 우측에 하트 아이콘 — `GestureDetector`로 카드 탭과 분리
- 탭: 전체 / 만들 수 있는 (N) / **즐겨찾기 (N)** — `TabController` length 3
- `_recommended` 원본 유지 + `_matches`/`_favorites`는 getter로 필터
- `POST /api/recipes/{id}/favorite/toggle` 후 `_recommended` + `_all` 동기화

---

### 알림

**알림 탭 → 정확한 식재료 화면으로 직행**
- `NotificationRouter`가 `"ingredient:{id}"` 패턴 인식
- `IngredientRepo.list` 후 id로 찾아 `IngredientEditScreen(existing: item)` push
- 삭제된 식재료(가족이 비움)면 식재료 탭 폴백

**알림 배지 실시간 갱신 (FCM foreground +1)**
- `state/unread_notification_count.dart` — 전역 `ValueNotifier<int>`
- `FcmService.onMessage`가 푸시 도착 시 `UnreadNotificationCount.increment()`
- ProfileScreen 배지가 `ValueListenableBuilder` 구독 → 즉시 반영
- NotificationCenter 진입 후 pop 시 `reset()` 호출

---

### 시각화

**가족 활동 통계 차트**
- 멤버별 추가/비움 **그룹형 막대** (인라인 구현 — `SimpleBarChart`는 단일 막대만 가능해서 별도)
- 자주 추가/비운 TOP5 — `DonutChart` 위젯 + 색깔 범례 5단계 (`_pieGreens` / `_pieOranges`)
- 기존 멤버 행/랭크 리스트는 그대로 유지

**우선순위 화면: 막대 → 도넛 차트**
- 위험/주의/안전 비율을 `DonutChart`로 시각화 (Stack으로 가운데 총 개수)
- stat box는 가로형 재설계 — 색깔 점 + 라벨 + 개수 + %

---

### 디자인 시스템 / 다크모드 (웹 외주 디자인과 통일)

**색 토큰 — `utils/theme_colors.dart` `ThemeColorsContext` 익스텐션**
- 화면 코드는 `context.cardBg` / `boxBg` / `surfaceBg` / `borderColor` / `textColor` /
  `subTextColor` / `accentColor` / `accentDeep` / `onAccent` / `skyAccent` / `statusDanger…` 호출
- 다크 팔레트(웹 theme.css와 동일): 배경 `#08090A` · 카드 `#191C20` · 표면 `#23272D` ·
  텍스트 `#F2F3EE` · 보조텍스트 알파 `#9EF2F3EE`
- `accentColor` = primary CTA: 라이트 라임 `#CDFF00` / 다크 off-white `#F2F3EE`
- `skyAccent` = AI·추천·선택표시·활성탭: 다크 `#8BCEEA` / 라이트 `#2563EB`
- `statusDanger/Warning/Safe` 다크 튜닝값(`#FF5A5F`/`#F5C44A`/`#34D97A`)

**`main.dart` darkTheme**
- scaffold/appbar `#08090A`, `colorScheme` surface=`#191C20`·primary=off-white,
  ElevatedButton 배경 off-white + 어두운 글자, seed=sky

**테마 토글 — system 제거**
- `state/theme_mode_pref.dart` — `ThemeMode.light | dark` 만 (기본 라이트).
  기존 `'system'` 저장값은 load 시 light/dark로 확정 마이그레이션
- ProfileScreen 토글 칩 2개(라이트/다크)

**화면 적용**
- 그라데이션·하드코딩 라이트색 → `context.*` 토큰으로 분기 (대시보드/우선순위/영양/
  프로필/식재료/장보기/레시피/냉장고관리/영수증/회원가입 등 전반)
- 프로필 맞춤기능 4카드: 컬러 배경 제거 → `cardBg`+`borderColor`, 아이콘 `skyAccent`
- `main_scaffold` 하단 네비 활성 탭 `skyAccent`
- priority "외 N개 더 보기" → `TabIndex.select(1)` 식재료 탭 이동(sky)

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
| iOS 시뮬레이터 / 데스크톱 | `http://localhost:8080` |
| 실기기 / 배포 서버 | `--dart-define=API_BASE_URL=...` 로 주입 |

배포된 백엔드(또는 실기기)를 쓰려면 빌드 시 `--dart-define`으로 override:

```bash
flutter run --dart-define=API_BASE_URL=https://naengbuhae.onrender.com
flutter build apk --dart-define=API_BASE_URL=https://naengbuhae.onrender.com
```

`API_BASE_URL`이 비어있으면 위 표의 플랫폼별 기본값으로 폴백. 실기기를 로컬 PC 백엔드에 붙이려면 `--dart-define=API_BASE_URL=http://<PC_LAN_IP>:8080` (PC 방화벽 8080 허용 필요).

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
