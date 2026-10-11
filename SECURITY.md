# 보안 정책

이 저장소는 공개되어 있으며 앱 파일도 분석될 수 있다는 전제로 설계한다. 설계 기준은 [보안 설계](docs/04-technical/security.md)에 있다.

> 현재 상태: 설계 확정, 구현 전. 아래 보호 장치는 구현·검증 전까지 **완료되지 않았다.**

## 취약점 신고

- 공개 이슈로 올리지 말고 GitHub의 **Private vulnerability reporting**(Security 탭 → Report a vulnerability)으로 알려 주세요.
- 앱 전용 문의 이메일이 생기면 여기에 추가한다.

## 저장소에 넣지 않는 것

| 항목 | 보관 위치 |
|---|---|
| 공공데이터포털 서비스 키 | Google Cloud Secret Manager |
| APNs 인증 키 (.p8), 서명 인증서·프로비저닝 프로파일 | 개발자 로컬 / Firebase 콘솔 / Apple Developer |
| Firebase 서비스 계정 JSON | 사용하지 않음 (관리형 자격 사용) |
| `GoogleService-Info.plist` | 개발자 로컬 |
| App Check 디버그 토큰, 인증·푸시 토큰 | 개발자 로컬 |
| 실제 여행 정보, 예약번호, 실제 API 응답 | 저장하지 않음 |

`GoogleService-Info.plist`는 비밀 키가 아니며, 숨기는 것만으로 서비스가 보호되지 않는다. 보호는 아래 장치가 함께 담당한다.
- 로그인 인증
- Firestore Security Rules
- 서버 함수 권한 검사
- App Check
- 호출 한도

## 비밀 정보가 커밋된 경우

1. 해당 키를 즉시 **폐기하고 새로 발급**한다.
2. 그다음 저장소에서 제거한다. 파일 삭제나 기록 정리만으로는 해결되지 않는다.
