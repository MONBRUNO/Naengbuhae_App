# 카메라 식재료 인식 API 스펙

앱/웹에서 사진을 찍거나 선택하면 백엔드 AI가 인식해서 결과만 반환. **사진 자체는 저장하지 않음** (한 번 인식하고 끝).

## 엔드포인트: `POST /api/ingredients/recognize`

**Content-Type:** `multipart/form-data`

### 요청

| 필드 | 타입 | 설명 |
|---|---|---|
| `image` | file (jpg/png) | 사용자가 촬영/선택한 식재료 사진 |

헤더: `Authorization: Bearer <accessToken>` (기존 인증과 동일)

### 응답 (200 OK)

```json
{
  "recognized": {
    "name": "햄",
    "category": "육류",
    "storage": "냉장",
    "quantity": 1,
    "unit": "팩"
  }
}
```

- `recognized`: AI가 추정한 값. 사용자가 폼에서 확인 후 수정 가능
  - `name`: 식재료 이름 (필수)
  - `category`: 카테고리 (선택 — `채소/육류/유제품/곡물/해산물/과일/기타` 중 하나)
  - `storage`: 보관 상태 (선택 — `냉장/냉동/실온` 중 하나). 사용자가 잘못 알고 있을 수 있는 부분이라 AI 판단이 유용 (예: 햄은 보통 냉장)
  - `quantity`: 수량 (선택)
  - `unit`: 단위 (선택 — `개/g/kg/ml/L/팩` 중 하나)

### 인식 실패 시

도저히 못 알아볼 때:
```json
{ "recognized": null }
```
앱/웹은 빈 폼 상태에서 사용자가 직접 입력함.

## 저장 정책

- **사진 자체는 백엔드에 저장하지 않음.** 인식 처리 후 메모리에서 폐기.
- 식재료는 기존대로 `POST /api/ingredients`로 저장 (이름/카테고리/수량/단위/보관/유통기한). 사진 URL 같은 필드 없음.

## AI 모델

- 예) Claude Vision / GPT-4V / 직접 학습 모델 — 담당자 자유 선택
- 프롬프트 예시:
  ```
  사진 속 식재료를 분석해서 다음 JSON 형식으로 응답해줘:
  {
    "name": "한국어 식재료 이름",
    "category": "채소|육류|유제품|곡물|해산물|과일|기타",
    "storage": "냉장|냉동|실온",
    "quantity": 숫자,
    "unit": "개|g|kg|ml|L|팩"
  }
  여러 개면 가장 두드러진 하나만. 못 알아보겠으면 null.
  ```

## 클라이언트 동작

이미 구현되어 있음:
- **앱 (`Naengbuhae_App`)**: `lib/screens/ingredient_edit_screen.dart` — 카메라 버튼 → 카메라/갤러리 시트 → `/recognize` 호출 → 폼 자동 채움
- **웹 (`Naengbuhae_Team`)**: `src/app/pages/AddIngredient.tsx` — 사진 첨부 버튼 → 파일 선택 → `/recognize` 호출 → 폼 자동 채움

404 응답 받으면 "AI 인식 기능 준비 중" 안내, 사용자가 직접 입력.
