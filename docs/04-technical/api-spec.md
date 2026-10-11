# 서버 함수 API 명세

## 1. 공통

- 모두 Firebase **호출형 함수**(callable)다. 앱은 Firebase Functions SDK로 호출한다.
- 지역: `asia-northeast1`
- **로그인 필수**, **App Check 필수**. 둘 중 하나라도 없으면 거부한다.
- 입력은 서버에서 다시 검증한다. 앱의 검증은 사용자 편의용이다.

### 에러 코드

| 코드 | 의미 | 앱 표시 예 |
|---|---|---|
| `unauthenticated` | 로그인 안 됨 | 로그인 화면으로 이동 |
| `invalid-argument` | 입력 형식 오류 | 입력란 아래 안내 |
| `not-found` | 대상 없음 | '항공편을 찾을 수 없습니다' |
| `already-exists` | 이미 등록함 | '이미 등록된 항공편입니다' |
| `permission-denied` | 권한 없음 | '수정할 수 없는 항목입니다' |
| `resource-exhausted` | 사용자 한도·API 일일 한도 초과 | '잠시 후 다시 시도해 주세요' |
| `unavailable` | 공공 API 장애 | '지금은 확인할 수 없습니다' |
| `failed-precondition` | Apple 토큰 해지 등 선행 조건 미충족 | 단계별 안내 |

### 사용자별 한도 (기본값)

| 항목 | 한도 |
|---|---|
| 검색 | 시간당 30회 |
| 다가오는 등록 항공편 | 30편 |
| 제보 저장 | 하루 50회 |

악용 방지용 기본값이다. 운영하며 조정한다.

---

## 2. `searchFlight`

편명과 날짜로 항공편 후보를 찾는다. 외부 API를 부를 수 있다. (등록 시 1회)

**입력**
```json
{ "flightNumber": "NH5701", "departureDate": "2026-11-01" }
```

| 필드 | 규칙 |
|---|---|
| `flightNumber` | `^[A-Z0-9]{2}[A-Z]?[0-9]{1,4}[A-Z]?$` (대문자 변환·공백 제거 후) |
| `departureDate` | `yyyy-MM-dd`, 오늘(출발지 기준 -1일 허용) ~ 1년 뒤 |

**출력**
```json
{
  "candidates": [
    {
      "flightKey": "OZ1075_2026-11-01_HND",
      "operating": { "airline": "OZ", "flightNumber": "OZ1075" },
      "departure": { "airport": "HND", "scheduledAt": "2026-11-01T01:00:00Z", "timeZone": "Asia/Tokyo" },
      "arrival":   { "airport": "ICN", "scheduledAt": "2026-11-01T03:30:00Z", "timeZone": "Asia/Seoul" },
      "dataLevel": "schedule",
      "alreadyTracked": false
    }
  ],
  "notFoundReason": null
}
```

| 필드 | 설명 |
|---|---|
| `dataLevel` | `realtime`(운항 현황) / `schedule`(시간표 기준) / `user`(다른 사용자가 직접 등록) |
| `notFoundReason` | 후보가 없을 때: `no_korean_airport_data` / `not_in_schedule` |

검색 순서: ① `flights`의 `searchKeys`에서 이미 있는 항공편 → ② 공공 API → ③ 없으면 `notFoundReason`.

---

## 3. `trackFlight`

검색 결과 후보를 내 항공편으로 등록한다.

**입력** `{ "flightKey": "...", "enteredFlightNumber": "NH5701" }`
**출력** `{ "trackedId": "..." }`

- `flights` 문서가 없으면 검색 결과로 만든다. (검색 결과는 서버가 10분간 임시 보관)
- `trackerCount` 증가, 다음 조회 시각 계산.
- 에러: `already-exists`, `resource-exhausted`(30편 초과), `not-found`(임시 보관 만료 → 다시 검색)

---

## 4. `createManualFlight`

검색으로 못 찾은 항공편을 직접 입력해 등록한다. (S-05)

**입력**
```json
{
  "flightNumber": "MM101",
  "departureDate": "2026-11-01",
  "departureAirport": "NRT",
  "arrivalAirport": "KIX",
  "departureTime": "08:30",
  "arrivalTime": "10:05",
  "arrivalDayOffset": 0,
  "fields": { "departure.terminal": "T3" }
}
```

| 필드 | 필수 | 규칙 |
|---|---|---|
| 편명, 날짜 | ✅ | `searchFlight`와 같음 |
| 출발·도착 공항 | ✅ | 공항 기본 데이터에 있는 IATA 코드, 서로 달라야 함 |
| 출발 시각 | ✅ | `HH:mm`, 출발 공항 현지 |
| 도착 시각, 날짜 차이 | | `HH:mm`, `-1`~`2` |
| `fields` | | `submitReport`와 같은 규칙 |

**출력** `{ "trackedId": "...", "flightKey": "..." }`

- 같은 키의 문서가 이미 있으면 새로 만들지 않고 그 문서에 등록한다.

---

## 5. `untrackFlight`

**입력** `{ "trackedId": "..." }` → **출력** `{}`

- 본인 문서만 삭제할 수 있다. `trackerCount` 감소. 진행 중인 Live Activity 종료.

---

## 6. `submitReport`

공유 항공편 정보를 제보·수정한다. (S-07)

**입력**
```json
{
  "flightKey": "OZ1075_2026-11-01_HND",
  "changes": {
    "departure.gate": "108",
    "departure.checkInCounter": null
  }
}
```

| 항목 | 형식 |
|---|---|
| `*.terminal` | 공항 기본 데이터의 터미널 목록 중 하나. 목록이 없으면 `^T?[0-9A-Z]{1,2}$` |
| `*.gate` | `^[0-9A-Z]{1,5}$` |
| `departure.checkInCounter` | `^[0-9A-Z-]{1,7}$` |
| `arrival.baggageBelt` | `^[0-9A-Z]{1,3}$` |
| `departure.scheduledAt`, `arrival.scheduledAt` | 직접 등록 항공편만. ISO 8601 |
| `null` | 값 지우기 |

**권한·규칙**
- 요청자가 이 항공편을 **등록한 사용자**여야 한다. 아니면 `permission-denied`.
- `source`가 `airport_data`인 항목은 수정할 수 없다. `permission-denied`.
- 지난 항공편(도착 + 3시간 이후)은 수정할 수 없다.
- 변경마다 `reportHistory`에 기록한다. 알림은 보내지 않는다.

**출력** `{ "flight": { ...갱신된 항목 } }`

---

## 7. `updateSettings`

**입력** `users/{uid}`의 설정 필드 중 바꿀 것만 보낸다. **출력** `{}`

| 필드 | 규칙 |
|---|---|
| `language` | `system` / `ko` / `ja` / `en` |
| `pushLanguage` | `ko` / `ja` / `en` |
| `notify.*.minutes` | 화면 설계의 선택 범위 값만 허용 |

---

## 8. `registerDevice`

앱 실행 시와 토큰이 바뀔 때 호출한다.

**입력** `{ "deviceId": "...", "fcmToken": "...", "liveActivityStartToken": "...", "appVersion": "1.0.0" }`

- 같은 `fcmToken`이 다른 사용자에게 등록돼 있으면 그쪽에서 지운다. (기기에서 계정을 바꾼 경우)
- 로그아웃 시 `{ "deviceId": "...", "fcmToken": null }`로 호출해 토큰을 지운다.

---

## 9. `registerLiveActivity`

앱이 Live Activity 갱신 토큰을 받으면 보낸다.

**입력** `{ "trackedId": "...", "updateToken": "..." }` (종료 시 `null`)

---

## 10. `deleteAccount`

**입력** `{}` → **출력** `{}`

**앱에서 먼저 할 일**
1. Apple 로그인 사용자: Apple 재인증 → `Auth.auth().revokeToken(withAuthorizationCode:)`로 Apple 토큰 해지
2. `deleteAccount` 호출

**서버가 하는 일**
1. 등록 항공편마다 `trackerCount` 감소
2. `reportHistory`의 `authorUid`를 `null`로 변경 (제보 값은 유지)
3. `users/{uid}` 아래 전체 삭제
4. Firebase Auth 사용자 삭제

중간에 실패하면 같은 요청을 다시 보내도 안전하게 이어서 처리한다.
