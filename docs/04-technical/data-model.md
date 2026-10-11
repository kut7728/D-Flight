# 데이터 모델 (Firestore)

## 1. 컬렉션 구조

```
users/{uid}                              사용자 설정
  ├─ devices/{deviceId}                  푸시 토큰
  └─ trackedFlights/{trackedId}          내가 등록한 항공편

flights/{flightKey}                      공유 항공편 정보 (모든 사용자 공통)
  └─ reportHistory/{historyId}           제보 수정 이력 (서버 전용)

system/quota_{yyyyMMdd}                  공공 API 일일 호출 수 (서버 전용)

config/app                               최소 버전 (공개 읽기)
notices/{noticeId}                       공지사항 (공개 읽기)
```

- 앱은 `users/{자기 uid}` 아래와 `flights/*`만 **읽는다.** 쓰기는 모두 서버 함수가 한다.
- 시각은 모두 **UTC 타임스탬프 + 공항 시간대(IANA, 예: `Asia/Tokyo`)**로 저장한다. 화면 표시 때 현지 시각으로 바꾼다.

## 2. `users/{uid}`

| 필드 | 타입 | 설명 |
|---|---|---|
| `language` | string | `system` / `ko` / `ja` / `en` |
| `pushLanguage` | string | 서버 푸시용 실제 언어 (`ko` / `ja` / `en`). `system`이면 앱이 기기 언어로 계산해 보낸다. |
| `notify.changes` | bool | 변경 알림 |
| `notify.dayBefore` | { enabled, minutes } | 하루 전 알림 (기본 1440분) |
| `notify.leaveForAirport` | { enabled, minutes } | 공항 출발 알림 (기본 180분) |
| `notify.boarding` | { enabled, minutes } | 탑승 임박 알림 (기본 40분) |
| `liveActivityEnabled` | bool | Live Activity 자동 시작 |
| `createdAt`, `updatedAt` | timestamp | |

임박 알림은 기기에서 예약하지만, 기기를 바꿔도 유지되도록 설정은 서버에 저장한다.

### `devices/{deviceId}`

| 필드 | 설명 |
|---|---|
| `fcmToken` | 푸시 알림 토큰 |
| `liveActivityStartToken` | Live Activity 서버 시작용 토큰 (push-to-start) |
| `appVersion`, `updatedAt` | |

## 3. `users/{uid}/trackedFlights/{trackedId}`

| 필드 | 타입 | 설명 |
|---|---|---|
| `flightKey` | string | 연결된 `flights` 문서 |
| `enteredFlightNumber` | string | 사용자가 입력한 편명 (코드쉐어 표시용) |
| `departureDate` | string | 출발 공항 현지 날짜 `yyyy-MM-dd` |
| `scheduledDepartureAt` | timestamp | 정렬·조회용 복사본 |
| `liveActivityUpdateToken` | string? | 진행 중인 Live Activity 갱신 토큰 |
| `createdAt` | timestamp | |

- '지난 항공편' 여부는 저장하지 않고 **앱이 시각으로 계산**한다. (도착 + 3시간, 도착 시각을 모르면 출발 + 24시간)
- 사용자가 지울 때까지 보관한다.
- 같은 사용자가 같은 `flightKey`를 두 번 등록할 수 없다.

## 4. `flights/{flightKey}`

### 키 규칙

```
{운항 편명}_{출발 현지 날짜}_{출발 공항}
예: OZ1075_2026-11-01_HND
```

- 운항 편명은 **실제 운항 편명**이다. 코드쉐어 편명으로 등록해도 같은 문서를 공유한다.
- 직접 입력 등록(S-05)은 운항 편명을 모르므로 입력한 편명으로 키를 만든다.

### 필드

| 필드 | 설명 |
|---|---|
| `operating` | { airline, flightNumber } 실제 운항 |
| `searchKeys` | [`OZ1075_2026-11-01`, `NH5701_2026-11-01`] 코드쉐어 포함 검색용 |
| `origin` | 직접 등록 여부. `airport_data` / `user` |
| `departure` | 공항 정보 (아래) |
| `arrival` | 공항 정보 (아래) |
| `status` | { value, source, updatedAt } — `scheduled` / `delayed` / `cancelled` / `departed` / `arrived` / `unknown` |
| `sync` | 서버 갱신 상태 (아래) |
| `trackerCount` | 등록한 사용자 수. 0이면 갱신하지 않는다. |

**공항 정보 (`departure`, `arrival` 공통)**

| 필드 | 설명 |
|---|---|
| `airport` | IATA 코드 |
| `timeZone` | IANA 시간대 |
| `scheduledAt` | 예정 시각 |
| `estimatedAt` | 변경 시각 (항목) |
| `terminal` | 항목 |
| `gate` | 항목 |
| `checkInCounter` | 항목 (출발만) |
| `baggageBelt` | 항목 (도착만) |
| `autoDataSupported` | 이 공항 쪽 자동 정보 제공 여부 |

**항목 형식** — 모든 정보 항목은 같은 구조다.

```json
{ "value": "T2", "source": "airport_data", "updatedAt": "..." }
```

| `source` | 화면 표시 ([정보 표시 규칙](../03-design/display-rules.md)) |
|---|---|
| `airport_data` | 확정 (공항 데이터) |
| `user` | 확정 (사용자 제보) |
| 값 `null` + 자동 정보 지원 공항 | 미정 또는 정보 대기 |
| 값 `null` + 미지원 공항 | 자동 정보 없음 |

**`sync`**

| 필드 | 설명 |
|---|---|
| `phase` | `schedule` / `hourly` / `frequent` / `done` |
| `nextPollAt` | 다음 조회 예정 시각 |
| `lastSuccessAt`, `lastFailureAt` | 마지막 성공·실패 |
| `consecutiveFailures` | 연속 실패 수. 2회 이상이면 앱에 '확인 실패' 표시 |
| `provider` | 사용 중인 데이터 공급원 |

## 5. `flights/{flightKey}/reportHistory/{historyId}`

| 필드 | 설명 |
|---|---|
| `field` | 예: `departure.gate` |
| `oldValue`, `newValue` | |
| `authorUid` | 작성자. **계정 삭제 시 `null`로 바꾼다.** |
| `createdAt` | |
| `expireAt` | 출발 + 30일. 이후 삭제 |

앱은 읽을 수 없다. 악용 확인용이다.

## 5-1. `config/app`

운영자가 Firebase 콘솔에서 직접 수정한다.

| 필드 | 설명 |
|---|---|
| `minimumVersion` | 이 버전 미만이면 강제 업데이트 (예: `1.2.0`). 비교는 숫자 단위(`1.10.0` > `1.9.0`) |
| `appStoreUrl` | 업데이트 버튼이 열 App Store 주소 |

- 앱은 실행·포그라운드 복귀 시 읽는다. **읽기 실패·오프라인이면 막지 않는다.**
- 로그인 전에 읽어야 하므로 로그인 없이 읽을 수 있다. (App Check는 적용)

## 5-2. `notices/{noticeId}`

운영자가 Firebase 콘솔에서 직접 추가한다. 앱은 읽기만 한다.

| 필드 | 타입 | 설명 |
|---|---|---|
| `title` | map | `{ ko, ja, en }` |
| `body` | map | `{ ko, ja, en }` 텍스트와 링크만 |
| `important` | bool | 중요 공지 (실행 시 1회 팝업) |
| `publishedAt` | timestamp | 게시 시각. 이 시각 이후에만 보인다 |
| `expiresAt` | timestamp? | 지나면 목록에서 숨김 |

- 앱은 `publishedAt ≤ 지금`인 공지를 최신순 최대 50개 읽는다.
- **읽음 여부는 기기에 저장**한다. (서버 쓰기 없음)
- 공지 작성 시 세 언어를 모두 채운다. 빠진 언어는 앱이 영어 → 한국어 순으로 대신 보여 준다.

## 6. 삭제 규칙

| 대상 | 시점 | 방법 |
|---|---|---|
| 등록 항공편 | 사용자가 삭제 | 서버 함수가 삭제하고 `trackerCount` 감소 |
| `flights` 문서 | `trackerCount`가 0이 되고 출발 30일이 지남 | 매일 정리 함수 |
| 제보 이력 | 출발 + 30일 | 매일 정리 함수 (TTL은 최대 24시간 지연이 있어 직접 삭제) |
| 일일 호출 수 | 30일 후 | 매일 정리 함수 |
| 계정 | 사용자가 삭제 | `users/{uid}` 전체 삭제, 제보 이력의 `authorUid` 제거, 제보 값은 유지 |
