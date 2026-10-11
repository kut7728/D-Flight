# R-5. 운영비

| 항목 | 내용 |
|---|---|
| 조사일 | 2026-10-12 |
| 환율 가정 | 1달러 = 150엔 |
| 관련 기획 | 제약 조건(월 1,000엔 목표) |

## 1. Firebase / Google Cloud

| 서비스 | 무료 범위 | 비고 |
|---|---|---|
| Firestore (DB) | 저장 1GiB, 하루 읽기 5만·쓰기 2만·삭제 2만 | 프로젝트당 DB 1개만 무료 |
| Cloud Functions (서버 코드) | 월 호출 200만 회 등 | **유료 요금제(Blaze)에서만 사용 가능** |
| Cloud Scheduler (정기 실행) | 결제 계정당 작업 3개 | 이후 작업당 $0.10/월 |
| Secret Manager (비밀키 보관) | 비밀 버전 6개, 접근 1만 회 | |
| FCM (푸시), Auth (로그인) | 무료 (Auth는 월 5만 명) | |
| Cloud Logging | 월 50GiB | |

- 외부 항공 API 호출과 Secret Manager 때문에 **Blaze 요금제가 필수**다. Blaze는 무료 범위를 넘은 만큼만 청구된다.
- 사용자 100~1,000명 규모에서는 **무료 범위 안**일 가능성이 높다. (실측 필요)

## 2. 예상 월 비용 (사용자 100명, 월 200편)

| 항목 | 비용 |
|---|---|
| AeroDataBox Pro | $7.50 ≈ **1,125엔** |
| Firebase | ≈ 0엔 (무료 범위 안 가정) |
| **합계** | **≈ 1,125엔** → 목표 1,000엔 초과 |

## 3. 비용 상한

- Google Cloud **예산 알림은 지출을 멈추지 않는다.** 알림만 보낸다.
- 자동 차단은 '예산 알림 → 결제 비활성화 함수'를 직접 만들어야 한다.
- 새로 생긴 자동 지출 상한(spend cap)은 Cloud Run·Functions 등에만 적용되고 **Firestore는 대상이 아니다.**
- AeroDataBox는 요금제 유닛을 다 쓰면 호출이 실패하는 구조로 보인다. (가입 후 확인 필요)
- 따라서 1,000엔은 **목표**이며 절대 상한으로 보장하지 않는다.

## 출처

- [Firebase 가격](https://firebase.google.com/pricing) · [Firestore 할당량](https://firebase.google.com/docs/firestore/quotas)
- [Cloud Scheduler 가격](https://cloud.google.com/scheduler/pricing) · [Secret Manager 가격](https://cloud.google.com/secret-manager/pricing) · [Cloud Logging 가격](https://cloud.google.com/stackdriver/pricing)
- [예산 알림](https://docs.cloud.google.com/billing/docs/how-to/budgets) · [지출 상한](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps)
