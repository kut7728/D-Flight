# 공항 기본 데이터

출처는 [OurAirports](https://ourairports.com/data/) `airports.csv`다. 라이선스는 Unlicense(퍼블릭 도메인)다.

https://davidmegginson.github.io/ourairports-data/airports.csv

IATA 코드가 있고 `scheduled_service`가 `yes`인 large/medium/small airport만 넣는다. 시간대는 좌표로 계산한 IANA ID다. 한·일 이름, 터미널, 안내도는 `overrides.json`에 직접 적고, 이름이 없으면 영문을 세 언어에 그대로 쓴다. `korean`은 국가가 KR일 때 true다.

인천 `terminalCodes`(P01·P03 → T1·T2, P02 탑승동 → T1)는 공급자용이다. `airports.json`에는 앱에 보일 `T1`/`T2`만 넣는다. 김포·김해·제주 등 한국공항공사 공항은 터미널 필드가 없어 빈 목록이다.

CSV는 실행할 때마다 받고 저장소에 넣지 않는다. Python 3.9 이상이 필요하다.

```bash
python3 -m venv /tmp/dflight-airports-venv
/tmp/dflight-airports-venv/bin/pip install timezonefinder
/tmp/dflight-airports-venv/bin/python scripts/airports/generate.py
```

같은 내용이 `data/airports.json`, `functions/src/data/airports.json`, `DFlight/Resources/airports.json`에 쓰인다. 서버 빌드가 `functions/lib/data/`로 한 번 더 복사한다.
