# R-3. iOS 플랫폼 제약

| 항목 | 내용 |
|---|---|
| 조사일 | 2026-10-12 |
| 관련 기획 | F-05, F-06, F-08, F-09 |

## 1. Live Activity (F-09)

| 항목 | 내용 |
|---|---|
| 최대 표시 시간 | 활성 **8시간** + 종료 후 잠금 화면에 최대 4시간 = 최대 12시간 |
| 데이터 크기 | 4KB 이하 |
| 앱이 시작 | 앱이 화면에 떠 있을 때만 시작할 수 있다. |
| 서버가 시작 | **iOS 17.2+**. 앱을 열지 않아도 서버 푸시로 시작할 수 있다. |
| 서버가 갱신 | Apple 푸시(APNs)로 갱신한다. **Firebase Cloud Messaging(FCM)으로도 시작·갱신·종료 가능.** |
| 갱신 횟수 제한 | 시간당 예산이 있지만 숫자는 비공개. 우선순위 5 푸시는 예산을 쓰지 않는다. |
| 같은 내용 일괄 갱신 (broadcast) | iOS 18+. 같은 항공편을 보는 사용자 전체에게 한 번에 보낼 수 있다. |

**8시간 제한의 영향**: 출발 3시간 전에 시작하면 비행 5시간 이하 항공편만 도착까지 표시된다. 장거리 항공편은 도착 전에 끝난다. 시작 시점과 장거리 처리는 03-design에서 정한다.

## 2. 위젯 (F-08)

- 갱신 예산: 자주 보는 위젯은 하루 **약 40~70회**.
- **미래 시점 표시 목록(타임라인)**을 미리 넘겨 둘 수 있다. D-Day처럼 시간이 지나며 바뀌는 값은 갱신 없이 표시된다.
- 앱과 위젯은 **App Group**이라는 공유 저장소로 데이터를 주고받는다. 위젯이 서버를 직접 호출하지 않는다.
- 푸시로 위젯을 갱신하는 기능은 iOS 26+에서만 된다.

> Flutter로 비유하면 위젯은 별도 `main()`을 가진 작은 앱이고, App Group은 두 앱이 함께 쓰는 `SharedPreferences`다.

## 3. 시간 임박 알림 (F-06)

| | 로컬 알림 (기기에서 예약) | 서버 알림 (푸시) |
|---|---|---|
| 인터넷·서버 비용 | 불필요 | 필요 |
| 출발 시각 변경 반영 | 앱이 실행돼 다시 예약해야 반영 | 서버가 최신 시각으로 계산 |
| 제한 | **앱당 대기 알림 64개** (항공편당 3개 → 약 21편) | 사실상 없음 |

- 화면에 보이지 않는 백그라운드 푸시(silent push)는 **전달이 보장되지 않는다.** 시간당 2~3회 이하 권장. 사용자가 앱을 강제 종료하면 전달되지 않는다.
- **권장 조합**: 임박 알림은 로컬로 예약한다. 시각 변경은 서버가 **보이는 알림**으로 보내고, 앱이 열릴 때 로컬 알림을 다시 맞춘다.

## 4. 최소 iOS 버전

| 기준 | 내용 |
|---|---|
| App Store 제출 조건 | 2026-04-28부터 **Xcode 26 + iOS 26 SDK**로 빌드해야 한다. |
| iOS 17.2 | 서버에서 Live Activity 시작 가능 |
| iOS 18 | Live Activity 일괄 갱신(broadcast) |
| iOS 26 | 푸시로 위젯 갱신 |

후보: **iOS 17.2** (지원 기기 범위 넓음, 18 기능은 버전 분기) 또는 **iOS 18** (분기 코드 감소).

## 출처

- [Live Activity 표시](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) · [Live Activity 푸시](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications) · [FCM Live Activity](https://firebase.google.com/docs/cloud-messaging/customize-messages/live-activity)
- [위젯 갱신](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) · [위젯 푸시](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications)
- [백그라운드 푸시](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) · [로컬 알림 64개 제한](https://developer.apple.com/forums/thread/811171)
- [App Store 제출 요구 사항](https://developer.apple.com/news/upcoming-requirements/)
