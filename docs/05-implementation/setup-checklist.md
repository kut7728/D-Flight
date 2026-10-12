# 준비 체크리스트 (M0)

사용자가 직접 해야 하는 작업이다. 실제 키·토큰·계정 정보는 **채팅, 저장소, 문서에 적지 않는다.**

## 1. Apple Developer ✅ 가입 완료

| 작업 | 위치 | 상태 |
|---|---|---|
| App ID 등록 (`com.dflight`) | Certificates, Identifiers & Profiles → Identifiers | ✅ 2026-10-12 |
| 기능 켜기: Sign in with Apple, Push Notifications, App Groups, App Attest | App ID 설정 | ✅ 2026-10-12 |
| App Group 등록 (`group.com.dflight`) | Identifiers → App Groups | ✅ 2026-10-12 |
| 위젯용 App ID (`com.dflight.widgets`) + App Group | Identifiers | ☐ (M7 전까지) |
| APNs 인증 키(.p8) 생성 → **Firebase 콘솔에만 업로드** | Keys | ✅ 발급 (2026-10-12). Firebase 업로드는 M6 |

- .p8 파일은 한 번만 내려받을 수 있다. 저장소 밖 안전한 곳에 보관한다.

## 2. Firebase

| 작업 | 상태 |
|---|---|
| 개발 프로젝트 생성 | ✅ 2026-10-12 |
| Firestore 생성: **지역 `asia-northeast3` (서울)** — 변경 불가 | ✅ 2026-10-12 |
| Blaze 요금제 전환 (Functions·Secret Manager에 필요) | ✅ 2026-10-12 |
| 예산 알림 설정 (예: 월 500엔, 1,000엔에서 메일) | ✅ 2026-10-12 |
| Authentication: Apple, Google 로그인 사용 설정 | ☐ (M3) |
| App Check: App Attest 등록 | ☐ (M3) |
| `GoogleService-Info.plist` 내려받기 → 로컬에만 둠 (`.gitignore` 대상) | ☐ (M3) |

**운영 프로젝트**는 M9에서 따로 만든다. 개발 중에는 개발 프로젝트와 로컬 에뮬레이터를 쓴다. (기본값: 프로젝트 2개. 예약 작업이 무료 3개를 넘으면 월 약 15엔 추가)

## 3. 공공데이터포털 (data.go.kr)

| API | 번호 | 상태 |
|---|---|---|
| 인천국제공항공사 운항 현황 상세 | 15140153 | ✅ 개발 활용신청 승인 (2026-10-12) |
| 인천국제공항공사 정기운항편 일정 | 15095059 | ✅ 개발 활용신청 승인 (2026-10-12) |
| 한국공항공사 실시간 운항정보 조회 | 15158625 | ✅ 개발 활용신청 승인 (2026-10-12) |
| 한국공항공사 실시간 운항정보 검색 | 15160195 | ✅ 개발 활용신청 승인 (2026-10-12) |
| 한국공항공사 운항 스케줄 | 15158949 | ✅ 개발 활용신청 승인 (2026-10-12) |

- 개발 계정으로 활용 신청하면 개발 키가 발급된다.
- 키는 M1에서 **로컬 환경 파일**(`.gitignore` 대상)로만 쓰고, 서버에서는 Secret Manager에 넣는다.
- 운영 한도 신청은 M9에서 한다. (서비스 주소·활용 사례 필요)

## 4. GitHub

| 작업 | 상태 |
|---|---|
| 공개 저장소 생성: [kut7728/D-Flight](https://github.com/kut7728/D-Flight) | ✅ 2026-10-12 |
| 첫 푸시 전 비밀 정보 검사 | ✅ |
| 비공개 취약점 신고(Private vulnerability reporting) 켜기 | ✅ |
