# R-2. 공항 지도

| 항목 | 내용 |
|---|---|
| 조사일 | 2026-10-12 |
| 관련 기획 | F-04 공항 안내, 다음 버전 후보 '앱 안 공항 지도' |

## 1. 결론

- **첫 출시**: 공항 공식 안내도 링크와 지도 앱 링크로 충분하다. 비용 0원, API 키 불필요.
- **앱 안 지도**: 개인 앱이 싸게 쓸 수 있는 게이트 단위 공항 지도는 **없다.** 다음 버전에서도 공항별 계약이나 직접 데이터 구축이 필요하다.

## 2. 선택지별 조사 결과

| 방법 | 가능 여부 | 내용 |
|---|---|---|
| Apple 지도 실내 지도를 앱에 표시 | ❌ | Apple 공식 FAQ: Apple 지도의 실내 지도는 MapKit으로 제공되지 않는다. |
| Apple 지도 앱으로 연결 | ✅ 공항·터미널까지 | iOS 18.4+ 지도 URL로 장소를 열 수 있다. 게이트·층 지정 파라미터는 없다. |
| Google 지도 SDK | 🔸 | 실내 지도를 자동으로 보여 주지만 게이트 강조 불가. 결제 계정과 API 키가 필요하다. 한국 공항 실내 지도는 불확실하다. |
| Google 지도 앱으로 연결 | ✅ | URL로 장소 검색 화면을 연다. API 키 불필요. |
| 실내 지도 업체 (Mappedin, Atrius 등) | ❌ | 공항이 직접 계약하는 B2B 서비스. Mappedin Pro는 지도 1개당 $165/월. |
| OpenStreetMap 실내 데이터 | 🔸 | 무료지만 공항별 품질이 불확실하다(조사 서버 오류로 미검증). 사용 시 출처 표기 의무가 있다(ODbL). |

## 3. 공항 공식 안내도

| 공항 | 주소 | 언어 | 게이트 표시 |
|---|---|---|---|
| 하네다 (HND) | https://tokyo-haneda.com/en/floor/index.html | 일·영·한·중 | 가능성 높음 (미검증) |
| 나리타 (NRT) | https://www.narita-airport.jp/en/map/ | 일·영·한·중 | 가능성 높음 (미검증) |
| 간사이 (KIX) | https://www.kansai-airport.or.jp/en/map | 일·영 | 미검증 |
| 인천 (ICN) | https://www.airport.kr/geomap/ap_en/view.do?type=2&alertType=0&tmnlId=P01 | 한·영·일 | 가능성 높음 (미검증) |
| 김포 (GMP) | https://www.airport.co.kr/gimpoeng/cms/frCon/index.do?MENU_ID=320&acd=A1101 | 한·영 | 미검증 |

**이용 조건**
- 하네다·나리타: 링크는 자유롭게 걸 수 있다. 내용이나 이미지를 복사하려면 사전 허가가 필요하다. 깊은 링크는 예고 없이 바뀔 수 있다.
- 간사이·인천·김포: 약관을 확인하지 못했다. 링크만 사용하고 이미지는 복사하지 않는다.

## 4. 첫 출시 적용 방향

- 공항 코드·터미널·언어별 안내도 주소를 표로 관리하고 앱 안 브라우저로 연다.
- '지도 앱에서 열기'로 터미널 위치까지 안내한다.
- 안내도 이미지를 저장하거나 앱에 포함하지 않는다.
- 안내도 주소가 없는 공항은 공항 이름으로 지도 앱 검색을 연다.

## 5. 앱 안 지도 (다음 버전 후보)

선호 순서:
1. 공항 운영사와 계약해 지도 데이터(IMDF/GeoJSON)를 받아 MapKit 위에 그린다. 품질이 가장 좋지만 공항마다 계약이 필요하다.
2. OpenStreetMap 게이트·실내 데이터를 MapKit 위에 그린다. 무료지만 공항별 품질 확인과 데이터 보완이 필요하다.
3. Google 지도 SDK를 넣는다. 게이트 강조가 안 되고 실내 지도 제공이 보장되지 않는다.

## 출처

- [Apple 실내 지도 FAQ](https://register.apple.com/resources/indoor/program/faq) · [MapKit 실내 지도 표시](https://developer.apple.com/documentation/mapkit/displaying-an-indoor-map) · [Apple 지도 URL](https://developer.apple.com/documentation/mapkit/unified-map-urls)
- [Google 지도 SDK 설정](https://developers.google.com/maps/documentation/ios-sdk/configure-map) · [Google 지도 URL](https://developers.google.com/maps/documentation/urls/guide)
- [Mappedin 가격](https://mappedin.com/pricing) · [OSM 실내 태그](https://wiki.openstreetmap.org/wiki/Simple_Indoor_Tagging) · [OSM 저작권](https://www.openstreetmap.org/copyright)
- [하네다 사이트 정책](https://tokyo-haneda.com/en/site_policy/index.html) · [나리타 사이트 정책](https://www.narita-airport.jp/en/company/sitepolicy/)
