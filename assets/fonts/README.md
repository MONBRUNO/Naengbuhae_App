# Pretendard 폰트

앱 전역 폰트로 Pretendard 사용 (`main.dart` ThemeData `fontFamily: 'Pretendard'`).
**아래 파일을 받아 이 폴더에 넣어야 실제 적용**됨. 없으면 시스템 기본 폰트로 폴백(빌드는 정상).

## 받는 곳

Pretendard (OFL 라이선스, 무료 — 상업적 사용 가능):
https://github.com/orioncactus/pretendard/releases  → `Pretendard-x.x.x.zip`

zip 안의 `public/static/` 에서 아래 4개 weight를 받아 **이 폴더(`assets/fonts/`)** 에 그대로:

| 파일명 | weight |
|---|---|
| `Pretendard-Regular.ttf` | 400 |
| `Pretendard-Medium.ttf` | 500 |
| `Pretendard-SemiBold.ttf` | 600 |
| `Pretendard-Bold.ttf` | 700 |

## 파일 넣은 뒤 (Claude가 처리)

`pubspec.yaml` `flutter:` 섹션에 아래 블록 추가하면 자동 적용:

```yaml
  fonts:
    - family: Pretendard
      fonts:
        - asset: assets/fonts/Pretendard-Regular.ttf
        - asset: assets/fonts/Pretendard-Medium.ttf
          weight: 500
        - asset: assets/fonts/Pretendard-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Pretendard-Bold.ttf
          weight: 700
```

> 파일이 없는 채로 위 블록을 pubspec에 넣으면 빌드가 깨지므로,
> 파일을 먼저 넣었는지 확인한 뒤 블록을 추가할 것.
