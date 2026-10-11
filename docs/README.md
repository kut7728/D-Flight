# D-Flight 문서

번호 순서대로 작성하고 읽는다. 각 폴더의 `README.md`에 그 단계의 결정 사항이 모여 있다.

| 폴더 | 단계 | 상태 |
|---|---|---|
| [01-planning](01-planning/product-requirements.md) | 기획: 왜·누구를·무엇을 | 확정 |
| [02-research](02-research/README.md) | 조사: 항공 데이터, 공항 지도, iOS 제약, 심사, 비용 | 확정 |
| [03-design](03-design/README.md) | 화면 설계: 화면 목록, 흐름, 화면별 상세, 표시 규칙, 알림 | 확정 |
| [04-technical](04-technical/README.md) | 기술 설계: 구조, 데이터 모델, API, 갱신, 보안 | 확정 |
| [05-implementation](05-implementation/README.md) | 구현 계획: 마일스톤 M0~M9, 준비 체크리스트 | 확정 |
| [06-testing](06-testing/README.md) | 테스트 계획: 전략, 시나리오 | 확정 |
| [07-release](07-release/README.md) | 출시 준비: 스토어 정보, 개인정보, 체크리스트 | 확정 |

## 결정 ID

| 접두어 | 단계 |
|---|---|
| F-xx | 기획 기능 |
| D-xx | 조사 결정 |
| DS-xx | 화면 설계 결정 |
| TD-xx | 기술 설계 결정 |
| IM-xx | 구현 계획 결정 |
| TS-xx | 테스트 결정 |
| RL-xx | 출시 결정 |
| S-xx / T-xx | 화면 / 테스트 시나리오 |

## 문서 변경 규칙

- 확정 문서와 다르게 구현해야 하면 **문서를 먼저 고치고** 결정을 기록한다.
- 결정은 해당 단계 `README.md`의 결정 표에 ID를 붙여 추가한다.
- 미정 항목은 임의로 확정하지 않고 '결정 대기'에 남긴다.
