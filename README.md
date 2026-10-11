# D-Flight

> 예매한 비행기, 놓치지 않게.

예매한 항공편을 등록해 두면 출발일까지 **D-Day**로 알려 주고, **터미널·게이트·체크인 카운터·수하물 수취대**를 한눈에 보여 주는 iOS 앱입니다.

**상태**: 설계 확정, 구현 준비 중 (마일스톤 M0)

## 주요 기능 (계획)

- 편명과 날짜로 항공편 등록, 내 항공편 D-Day
- 출발 시각 변경·지연·결항, 터미널·게이트 변경 알림
- 출발 하루 전, 공항 출발, 탑승 임박 알림
- 홈 화면 위젯, 잠금 화면 Live Activity
- 사용자 제보로 공항 정보 공유
- 한국어 · 日本語 · English

## 기술

| 영역 | 사용 |
|---|---|
| 앱 | Swift, SwiftUI, WidgetKit, ActivityKit (iOS 18+) |
| 서버 | Firebase: Auth, Firestore, Cloud Functions (TypeScript), FCM, App Check |
| 데이터 | 공공데이터포털: 인천국제공항공사, 한국공항공사 |

## 문서

기획부터 출시 준비까지의 설계 문서는 [docs/](docs/README.md)에 단계별로 정리되어 있습니다.

| 단계 | 문서 |
|---|---|
| 01 | [기획서](docs/01-planning/product-requirements.md) |
| 02 | [조사](docs/02-research/README.md) |
| 03 | [화면 설계 · 시각 디자인](docs/03-design/README.md) |
| 04 | [기술 설계](docs/04-technical/README.md) |
| 05 | [구현 계획](docs/05-implementation/README.md) |
| 06 | [테스트 계획](docs/06-testing/README.md) |
| 07 | [출시 준비](docs/07-release/README.md) |

## 데이터 출처

항공편 정보는 공공데이터포털(data.go.kr)의 인천국제공항공사·한국공항공사 데이터를 사용합니다. 정보는 참고용이며, 최종 정보는 항공사와 공항 안내를 확인해 주세요.

## 보안

[SECURITY.md](SECURITY.md)

## 라이선스

미정입니다. 정해지기 전까지 이 저장소의 코드와 문서는 별도 허락 없이 재사용할 수 없습니다.
