# 전체 구조

## 1. 구성도

```
┌──────────────── iPhone ────────────────┐
│  D-Flight 앱 (SwiftUI)                   │
│   ├─ 읽기: Firestore 직접 구독 (오프라인 캐시) │
│   ├─ 쓰기: Cloud Functions 호출           │
│   └─ 로컬 알림 예약 (임박 알림)              │
│  위젯 확장 (WidgetKit + Live Activity)     │
│   └─ App Group 공유 저장소에서 읽기           │
└───────────────┬─────────────────────────┘
                │ Firebase Auth 토큰 + App Check
┌───────────────▼──── Firebase (서울 asia-northeast3) ──┐
│  Cloud Functions (TypeScript)                        │
│   ├─ 호출형 함수: 검색, 등록, 제보, 설정, 계정 삭제         │
│   └─ 예약 함수: 15분마다 항공편 갱신, 매일 정리            │
│  Firestore: 사용자, 등록 항공편, 공유 항공편 정보           │
│  Secret Manager: 공공 API 서비스 키                     │
│  FCM: 푸시 알림, Live Activity 시작·갱신                 │
└───────────────┬──────────────────────────────────────┘
                │ HTTPS
┌───────────────▼──────────────┐
│ 공공데이터포털 (data.go.kr)      │
│  인천국제공항공사, 한국공항공사      │
└──────────────────────────────┘
```

**핵심 원칙**
- 외부 항공 API는 **서버만** 호출한다. 앱에는 서비스 키가 없다.
- 같은 항공편은 서버가 **한 번만** 조회해 `flights` 문서에 저장하고, 등록한 모든 사용자가 같은 문서를 읽는다.
- 앱은 Firestore에 **직접 쓰지 않는다.** 모든 쓰기는 서버 함수가 검증한 뒤 처리한다.

## 2. iOS 앱

### 타깃

| 타깃 | 역할 |
|---|---|
| `DFlight` | 앱 본체 |
| `DFlightWidgets` | 홈·잠금 화면 위젯 + Live Activity 화면 |
| `DFlightTests` | 단위 테스트 |

앱과 위젯은 **App Group**(`group.com.kut7728.dflight`)으로 데이터를 공유한다. 앱이 항공편 요약을 JSON 파일로 저장하면 위젯이 읽는다.

### 계층 (MVVM)

```
View (SwiftUI)            화면 그리기만 담당
   ↕
ViewModel (@Observable)   화면 상태와 사용자 동작 처리
   ↕
Repository (protocol)     데이터 접근 창구. Live / Mock 구현 교체
   ↕
Firebase SDK / Mock 데이터
```

| Flutter | 이 앱 |
|---|---|
| `StatelessWidget` | SwiftUI `View` |
| `ChangeNotifier` + Provider | `@Observable` 클래스 + `@Environment` |
| Repository 패턴 | 같음 (Swift `protocol`) |
| `flutter_localizations` + arb | String Catalog (`.xcstrings`) |

### 폴더 구조

```
DFlight/
├── App/            앱 시작, 탭, 의존성 조립
├── Features/       화면별 폴더 (View + ViewModel)
│   ├── Login/
│   ├── MyFlights/
│   ├── Register/
│   ├── FlightDetail/
│   ├── Report/
│   ├── PastFlights/
│   └── Settings/
├── Domain/         모델, 표시 규칙 계산 (D-Day, 상태, 시각)
├── Data/           Repository 구현 (Live / Mock)
├── Services/       로그인, 푸시, 로컬 알림, Live Activity, 위젯 공유
├── Resources/      String Catalog, 공항 기본 데이터
└── Shared/         앱과 위젯이 함께 쓰는 코드
```

### 주요 라이브러리

| 라이브러리 | 용도 |
|---|---|
| Firebase iOS SDK | Auth, Firestore, Functions, Messaging, App Check |
| GoogleSignIn | Google 로그인 |

그 외 외부 라이브러리는 넣지 않는다.

### 빌드 구성

| 구성 | scheme | 데이터 | Firebase |
|---|---|---|---|
| Debug | `DFlight` | 실제 서버 (개발 프로젝트) | 사용 |
| Mock | `DFlight-Mock` | 앱 안 목데이터 | **초기화하지 않음**. 외부 통신·실제 푸시 없음 |
| Release | `DFlight` (Archive) | 실제 서버 | 사용. **목데이터 미포함**, `MOCK_DATA` 플래그 단독 사용 시 빌드 실패 |

- 목데이터 항공편은 모든 화면에서 `샘플 데이터` 표시를 붙인다.
- Mock 빌드에서는 로그인 화면 대신 샘플 사용자로 시작하지만 **서버 인증 우회는 없다.** (서버와 통신하지 않음)

### 화면 모드·공지·버전 확인

| 기능 | 저장·출처 | 비고 |
|---|---|---|
| 화면 모드 (시스템·라이트·다크) | 기기 (`@AppStorage`) | 서버에 저장하지 않음. 바꿀 때 창 전체 크로스페이드 |
| 공지 읽음 여부 | 기기 | 공지 본문은 Firestore `notices` |
| 최소 버전 확인 | Firestore `config/app` | 앱 실행·포그라운드 복귀 시. 실패하면 통과 |

> Flutter 비유: 화면 모드는 `MaterialApp`의 `themeMode`를 `SharedPreferences`에 저장해 바꾸는 것과 같다. 강제 업데이트는 앱 시작 시 원격 설정의 최소 버전을 읽어 라우트를 막는 가드다.

### 앱 안 언어 전환

iOS 기본 동작은 기기 언어를 따른다. 앱 안 메뉴로 바꾸려면 앱이 직접 언어 번들을 고르는 처리가 필요하다. **구현 방법은 05에서 시제품으로 검증한다.** 날짜·시각 형식도 선택한 언어를 따른다.

## 3. 서버 (Cloud Functions, TypeScript)

```
functions/src/
├── callable/       앱이 호출하는 함수 (api-spec.md)
├── scheduled/      예약 실행 함수 (data-sync.md)
├── providers/      공공 API 연결 (인천, 한국공항공사) — 공급원 교체 가능 구조
├── domain/         항공편 정규화, 변경 감지, 입력 검증
├── notify/         FCM 알림, Live Activity 푸시, 문구 번역
└── store/          Firestore 읽기·쓰기
```

- `providers/`는 공통 인터페이스로 만든다. 나중에 유료 데이터를 붙일 때 구현만 추가한다. (조사 결정 D-04)
- Node.js 22, Cloud Functions 2세대.

## 4. 공항 기본 데이터

공항 코드, 이름(한·일·영), 시간대, 터미널 목록, 안내도 주소를 담은 표가 앱과 서버 모두에 필요하다.

| 항목 | 출처 |
|---|---|
| 공항 코드·이름·좌표 | 공개 데이터 (후보: OurAirports, 퍼블릭 도메인) — 05에서 확정 |
| 시간대 | 좌표 기반 변환 또는 수동 입력 — 05에서 확정 |
| 터미널 목록·안내도 주소 | 주요 공항만 직접 작성 ([공항 지도 조사](../02-research/airport-maps.md)) |

첫 출시는 전 세계 공항 코드·이름·시간대를 넣고, 터미널 목록·안내도는 한국·일본 주요 공항부터 채운다.
