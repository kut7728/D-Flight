import Foundation
import Testing
@testable import DFlight

@Suite("표시 규칙")
struct DisplayRulesTests {
    private let ko = Locale(identifier: "ko")
    private let us = Locale(identifier: "en_US")

    @Test("FlightNotify 기본값은 네 종류 모두 켜짐")
    func flightNotifyDefaultsAllOn() {
        let notify = FlightNotify()
        #expect(notify.changes)
        #expect(notify.dayBefore)
        #expect(notify.leaveForAirport)
        #expect(notify.boarding)
        #expect(ImminentTiming.dayBefore == 24 * 3600)
        #expect(ImminentTiming.leaveForAirport == 3 * 3600)
        #expect(ImminentTiming.boarding == 40 * 60)
        #expect(UserSettings.default.notificationsEnabled)
    }

    @Test("T-33 출발 공항 현지 날짜. 같은 시각이라도 공항 시간대에 따라 D-Day가 다르다")
    func dDayUsesOriginCalendar() {
        let now = utc(2026, 1, 16, 8, 0)
        let departure = utc(2026, 1, 16, 18, 0)
        let lax = sampleFlight(departure: departure, departureTimeZone: "America/Los_Angeles", departureAirport: "LAX")
        let tokyo = sampleFlight(departure: departure, departureTimeZone: "Asia/Tokyo", departureAirport: "HND")
        #expect(dDay(for: lax, now: now) == .today)
        #expect(dDay(for: tokyo, now: now) == .days(1))
    }

    @Test("D-n·당일·출발함·도착함. 결항은 날짜가 지나도 출발함이 아니다")
    func dDayCountsAndStatus() {
        let seoul = "Asia/Seoul"
        let now = at(2026, 1, 1, 15, 0, tz: seoul)
        #expect(dDay(for: sampleFlight(departure: at(2026, 1, 13, 9, 0, tz: seoul)), now: now) == .days(12))
        #expect(dDay(for: sampleFlight(departure: at(2026, 1, 2, 9, 0, tz: seoul)), now: now) == .days(1))

        let laterSameDay = at(2026, 1, 15, 22, 0, tz: seoul)
        let morning = at(2026, 1, 15, 8, 0, tz: seoul)
        #expect(dDay(for: sampleFlight(departure: morning), now: laterSameDay) == .today)

        let future = at(2026, 1, 20, 10, 0, tz: seoul)
        #expect(dDay(for: sampleFlight(departure: future, status: .departed), now: now) == .departed)
        #expect(dDay(for: sampleFlight(departure: future, status: .arrived), now: now) == .arrived)

        let departedDay = at(2026, 1, 16, 0, 30, tz: seoul)
        let yesterday = at(2026, 1, 15, 23, 0, tz: seoul)
        #expect(dDay(for: sampleFlight(departure: yesterday, status: .cancelled), now: departedDay) == .today)
        #expect(dDay(for: sampleFlight(departure: yesterday), now: departedDay) == .departed)
        #expect(dDay(for: sampleFlight(departure: at(2026, 1, 13, 9, 0, tz: seoul), status: .cancelled), now: now) == .days(12))

        // 자정을 넘는 지연이어도 D-Day는 예정 출발의 현지 날짜.
        let scheduled = at(2026, 1, 15, 23, 50, tz: seoul)
        let estimated = at(2026, 1, 16, 0, 20, tz: seoul)
        let noon = at(2026, 1, 15, 12, 0, tz: seoul)
        #expect(dDay(for: sampleFlight(departure: scheduled, departureEstimated: estimated), now: noon) == .today)
    }

    @Test("예정 시각이 없으면 departureDate의 출발 공항 날짜로 D-n을 센다")
    func dDayFromDepartureDateWhenTimeMissing() {
        let seoul = "Asia/Seoul"
        let now = at(2026, 1, 1, 15, 0, tz: seoul)
        var flight = sampleFlight(departure: nil, departureTimeZone: seoul, arrivalAuto: false)
        flight.origin = .pending
        #expect(dDay(for: flight, now: now, departureDate: "2026-01-13") == .days(12))
        #expect(dDay(for: flight, now: now, departureDate: "2026-01-01") == .today)
        #expect(dDay(for: flight, now: now) == .today)
        #expect(countdown(for: flight, now: now, departureDate: "2026-01-13") == .days(12))
        #expect(infoState(InfoItem(), side: flight.arrival, flight: flight, now: now) == .awaiting)
    }

    @Test("T-30·T-31 날짜 차이. 인천→로스앤젤레스 장거리와 하네다→인천 당일은 0")
    func dayOffsetCases() {
        let scheduled = at(2026, 1, 15, 23, 50, tz: "Asia/Seoul")
        let estimated = at(2026, 1, 16, 0, 20, tz: "Asia/Seoul")
        #expect(dayOffset(departure: scheduled, depTZ: "Asia/Seoul", arrival: estimated, arrTZ: "Asia/Seoul") == 1)

        let tokyo = at(2026, 1, 16, 10, 0, tz: "Asia/Tokyo")
        let losAngeles = at(2026, 1, 15, 18, 0, tz: "America/Los_Angeles")
        #expect(dayOffset(departure: tokyo, depTZ: "Asia/Tokyo", arrival: losAngeles, arrTZ: "America/Los_Angeles") == -1)

        let incheonNight = at(2026, 1, 15, 21, 0, tz: "Asia/Seoul")
        let laxAfternoon = at(2026, 1, 15, 14, 0, tz: "America/Los_Angeles")
        #expect(dayOffset(departure: incheonNight, depTZ: "Asia/Seoul", arrival: laxAfternoon, arrTZ: "America/Los_Angeles") == 0)

        let haneda = at(2026, 1, 15, 10, 0, tz: "Asia/Tokyo")
        let incheon = at(2026, 1, 15, 12, 30, tz: "Asia/Seoul")
        #expect(dayOffset(departure: haneda, depTZ: "Asia/Tokyo", arrival: incheon, arrTZ: "Asia/Seoul") == 0)
    }

    @Test("T-32 현지 시각은 기기 시간대와 무관하고 24시 HH:mm")
    func localTimeIsOriginClock() {
        let afternoon = utc(2026, 1, 15, 14, 50)
        #expect(localTime(afternoon, timeZone: "Asia/Seoul", locale: us) == "23:50")
        #expect(localTime(afternoon, timeZone: "America/Los_Angeles", locale: us) == "06:50")
        #expect(localTime(utc(2026, 1, 15, 15, 20), timeZone: "Asia/Seoul", locale: us) == "00:20")
        #expect(localTime(utc(2026, 1, 15, 0, 5), timeZone: "Asia/Seoul", locale: ko) == "09:05")
    }

    @Test("T-34·T-35 지난 항공편 경계. 도착은 변경 시각, 없으면 출발 + 24시간")
    func pastBoundary() {
        let arrival = at(2026, 6, 1, 10, 0, tz: "Asia/Seoul")
        let estimatedArrival = at(2026, 6, 1, 12, 0, tz: "Asia/Seoul")
        let withEstimate = sampleFlight(arrival: arrival, arrivalEstimated: estimatedArrival)
        #expect(!isPast(withEstimate, now: estimatedArrival.addingTimeInterval(3 * 3600 - 1)))
        #expect(isPast(withEstimate, now: estimatedArrival.addingTimeInterval(3 * 3600)))
        #expect(!isPast(withEstimate, now: arrival.addingTimeInterval(3 * 3600)))

        let scheduledOnly = sampleFlight(arrival: arrival)
        #expect(!isPast(scheduledOnly, now: arrival.addingTimeInterval(3 * 3600 - 1)))
        #expect(isPast(scheduledOnly, now: arrival.addingTimeInterval(3 * 3600)))

        let departure = at(2026, 6, 1, 10, 0, tz: "Asia/Seoul")
        let estimatedDeparture = at(2026, 6, 1, 12, 0, tz: "Asia/Seoul")
        let noArrival = sampleFlight(departure: departure, departureEstimated: estimatedDeparture)
        #expect(!isPast(noArrival, now: departure.addingTimeInterval(24 * 3600)))
        #expect(!isPast(noArrival, now: estimatedDeparture.addingTimeInterval(24 * 3600 - 1)))
        #expect(isPast(noArrival, now: estimatedDeparture.addingTimeInterval(24 * 3600)))

        let scheduledDeparture = sampleFlight(departure: departure)
        #expect(!isPast(scheduledDeparture, now: departure.addingTimeInterval(24 * 3600 - 1)))
        #expect(isPast(scheduledDeparture, now: departure.addingTimeInterval(24 * 3600)))
        #expect(!isPast(sampleFlight(), now: departure))
    }

    @Test("T-01·T-20 정보 대기·미정·자동 정보 없음. 3일은 출발 공항 달력 기준")
    func infoWaitingAndNoAutoData() {
        let now = utc(2026, 1, 17, 8, 0)
        let departure = utc(2026, 1, 20, 18, 0)
        let lax = sampleFlight(departure: departure, departureTimeZone: "America/Los_Angeles", departureAirport: "LAX")
        let tokyo = sampleFlight(departure: departure, departureTimeZone: "Asia/Tokyo", departureAirport: "HND")
        #expect(infoState(InfoItem(), side: lax.departure, flight: lax, now: now) == .undetermined)
        #expect(infoState(InfoItem(), side: tokyo.departure, flight: tokyo, now: now) == .awaiting)

        let seoul = "Asia/Seoul"
        let evening = at(2026, 1, 17, 23, 0, tz: seoul)
        let threeDays = sampleFlight(departure: at(2026, 1, 20, 1, 0, tz: seoul))
        #expect(infoState(InfoItem(), side: threeDays.departure, flight: threeDays, now: evening) == .undetermined)

        let early = at(2026, 1, 17, 1, 0, tz: seoul)
        let fourDays = sampleFlight(departure: at(2026, 1, 21, 23, 0, tz: seoul))
        #expect(infoState(InfoItem(), side: fourDays.departure, flight: fourDays, now: early) == .awaiting)

        let registered = at(2026, 1, 1, 10, 0, tz: seoul)
        let tenDaysOut = sampleFlight(departure: at(2026, 1, 11, 10, 0, tz: seoul))
        #expect(infoState(InfoItem(value: ""), side: tenDaysOut.departure, flight: tenDaysOut, now: registered) == .awaiting)
        let sameDay = sampleFlight(departure: registered)
        #expect(infoState(InfoItem(), side: sameDay.departure, flight: sameDay, now: registered) == .undetermined)

        let haneda = sampleFlight(
            departure: at(2026, 4, 20, 10, 0, tz: "Asia/Tokyo"),
            departureTimeZone: "Asia/Tokyo",
            departureAirport: "HND",
            departureAuto: false,
            arrivalAuto: true
        )
        let before = at(2026, 4, 1, 10, 0, tz: "Asia/Tokyo")
        #expect(infoState(InfoItem(), side: haneda.departure, flight: haneda, now: before) == .noAutoData)
        #expect(infoState(InfoItem(), side: haneda.arrival, flight: haneda, now: before) == .awaiting)
        let reported = InfoItem(value: "T3", source: .user, updatedAt: before)
        #expect(infoState(reported, side: haneda.departure, flight: haneda, now: before) == .confirmedUser("T3"))
    }

    @Test("변경 칩은 공항 데이터가 24시간 안에 바뀐 경우만")
    func changedChipWindow() {
        let now = utc(2026, 3, 10, 12, 0)
        let flight = sampleFlight(departure: now)
        let within = now.addingTimeInterval(-(24 * 3600 - 1))
        let exact = now.addingTimeInterval(-24 * 3600)
        let older = now.addingTimeInterval(-(24 * 3600 + 1))

        #expect(state(value: "T2", source: .airportData, updated: within, previous: "T1", flight: flight, now: now) == .confirmedAirport("T2", changed: true, previous: "T1"))
        #expect(state(value: "T2", source: .airportData, updated: exact, previous: "T1", flight: flight, now: now) == .confirmedAirport("T2", changed: false, previous: nil))
        #expect(state(value: "T2", source: .airportData, updated: older, previous: "T1", flight: flight, now: now) == .confirmedAirport("T2", changed: false, previous: nil))
        #expect(state(value: "T2", source: .airportData, updated: within, previous: nil, flight: flight, now: now) == .confirmedAirport("T2", changed: false, previous: nil))
        #expect(state(value: "T3", source: .user, updated: within, previous: "T1", flight: flight, now: now) == .confirmedUser("T3"))
    }

    @Test("T-10 연속 실패 2회면 마지막 값과 마지막 성공 시각")
    func checkFailedKeepsLastValue() {
        let now = utc(2026, 3, 10, 12, 0)
        let success = utc(2026, 3, 10, 9, 30)
        let gate = InfoItem(value: "108", source: .airportData, updatedAt: now, previousValue: "100")
        let failed = sampleFlight(departure: now, failures: 2, lastSuccess: success)
        #expect(infoState(gate, side: failed.departure, flight: failed, now: now) == .checkFailed(lastValue: "108", since: success))

        let once = sampleFlight(departure: now, failures: 1, lastSuccess: success)
        #expect(infoState(gate, side: once.departure, flight: once, now: now) == .confirmedAirport("108", changed: true, previous: "100"))
    }

    @Test("자동 정보가 없는 쪽은 연속 실패여도 확인 실패가 아니다")
    func checkFailedRequiresAutoData() {
        let now = utc(2026, 3, 10, 12, 0)
        let success = utc(2026, 3, 10, 9, 30)
        let flight = sampleFlight(
            departure: now,
            arrivalAirport: "KIX",
            arrivalAuto: false,
            failures: 2,
            lastSuccess: success,
            gate: "108"
        )
        let reported = InfoItem(value: "T1", source: .user, updatedAt: now)
        #expect(infoState(InfoItem(), side: flight.arrival, flight: flight, now: now) == .noAutoData)
        #expect(infoState(reported, side: flight.arrival, flight: flight, now: now) == .confirmedUser("T1"))
        #expect(infoState(flight.departure.gate, side: flight.departure, flight: flight, now: now) == .checkFailed(lastValue: "108", since: success))
    }

    @Test("탑승 추정은 출발 40분 전. 지연 분은 양수·음수·없음")
    func boardingAndDelay() {
        let scheduled = at(2026, 6, 1, 10, 0, tz: "Asia/Seoul")
        let estimated = at(2026, 6, 1, 10, 45, tz: "Asia/Seoul")
        let delayed = sampleFlight(departure: scheduled, departureEstimated: estimated)
        #expect(estimatedBoardingTime(delayed) == estimated.addingTimeInterval(-40 * 60))
        #expect(estimatedBoardingTime(sampleFlight(departure: scheduled)) == scheduled.addingTimeInterval(-40 * 60))
        #expect(estimatedBoardingTime(sampleFlight()) == nil)

        #expect(delayMinutes(delayed.departure) == 45)
        let early = sampleFlight(departure: scheduled, departureEstimated: at(2026, 6, 1, 9, 40, tz: "Asia/Seoul"))
        #expect(delayMinutes(early.departure) == -20)
        #expect(delayMinutes(sampleFlight(departure: scheduled, departureEstimated: scheduled).departure) == nil)
        #expect(delayMinutes(sampleFlight(departure: scheduled).departure) == nil)
    }

    @Test("T-93 버전은 숫자 단위로 비교")
    func versionOrder() {
        #expect(!isVersion("1.10.0", lowerThan: "1.9.0"))
        #expect(isVersion("1.9.0", lowerThan: "1.10.0"))
        #expect(!isVersion("1.2", lowerThan: "1.2.0"))
        #expect(!isVersion("1.2.0", lowerThan: "1.2"))
        #expect(isVersion("2.0.0", lowerThan: "10.0.0"))
        #expect(!isVersion("10.0.0", lowerThan: "2.0.0"))
    }

    @Test("T-96 빈 문자열은 건너뛰고 ja → en → ko")
    func localizedFallback() {
        #expect(localized(["ja": "日本語", "en": "English", "ko": "한국어"], language: "ja") == "日本語")
        #expect(localized(["ja": "", "en": "English", "ko": "한국어"], language: "ja") == "English")
        #expect(localized(["ja": "", "en": "", "ko": "한국어"], language: "ja") == "한국어")
        #expect(localized(["en": "English"], language: "ja") == "English")
        #expect(localized(["ko": "한국어"], language: "en") == "한국어")
        #expect(localized(["ja": "", "en": "", "ko": ""], language: "ja") == "")
    }

    @Test("T-97 미래·만료 공지는 숨기고 최신 50개")
    func visibleNoticeWindow() {
        let now = utc(2026, 5, 1, 12, 0)
        var list = (0..<51).map { index in
            notice(id: "n\(index)", publishedAt: now.addingTimeInterval(-Double(index) * 3600))
        }
        list.append(notice(id: "future", publishedAt: now.addingTimeInterval(3600)))
        list.append(notice(id: "expired", publishedAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(-1)))

        let visible = visibleNotices(list, now: now)
        #expect(visible.map(\.id) == (0..<50).map { "n\($0)" })
    }

    @Test("편명은 항공사 2~3자와 숫자 1~4자리다. 숫자만·다섯 자리는 거절한다")
    func flightNumberFormat() {
        #expect(normalizeFlightNumber(" xx 5701 ") == "XX5701")
        for text in ["XX5701", "YY1", "XXX1234", " xx 5701 ", "7C101", "NH5701A", "C7101"] {
            #expect(isValidFlightNumber(text), "\(text)는 통과해야 한다")
        }
        for text in ["5701", "1234", "12345", "12A345", "X1", "XX12345", "XX123456", "XX", "대한5701", "XX5701가", "XXXX1"] {
            #expect(!isValidFlightNumber(text), "\(text)는 거절해야 한다")
        }
    }

    @Test("T-44 게이트·체크인·수하물 형식")
    func placeFieldFormat() {
        for text in ["108", "C24", "52A"] {
            #expect(isValidGate(text))
        }
        for text in ["123456", "게이트", "10 8", "https://x.test/a", ""] {
            #expect(!isValidGate(text))
        }
        for text in ["K", "A-C", "L10-15"] {
            #expect(isValidCheckInCounter(text))
        }
        for text in ["12345678", "카운터", "A C", "https://x.test/a", ""] {
            #expect(!isValidCheckInCounter(text))
        }
        for text in ["3", "12A"] {
            #expect(isValidBaggageBelt(text))
        }
        for text in ["1234", "수하", "1 2", "https://x.test/a", ""] {
            #expect(!isValidBaggageBelt(text))
        }
    }

    @Test("다가오는 편은 출발 순, 지난 편은 최근 출발이 먼저")
    func partitionsByDeparture() {
        let now = utc(2026, 6, 1, 12, 0)
        let result = partitionFlights([
            sampleTracked(id: "later", departure: now.addingTimeInterval(5 * 3600)),
            sampleTracked(id: "older", departure: now.addingTimeInterval(-50 * 3600)),
            sampleTracked(id: "soon", departure: now.addingTimeInterval(-10 * 3600)),
            sampleTracked(id: "recent", departure: now.addingTimeInterval(-30 * 3600)),
        ], now: now)
        #expect(result.upcoming.map(\.id) == ["soon", "later"])
        #expect(result.past.map(\.id) == ["recent", "older"])
    }

    @Test("S-06 공유 텍스트. 코드쉐어일 때만 운항 편명")
    func shareTextFormat() {
        let names = ["HND": "하네다", "ICN": "인천"]
        let codeshare = sampleTracked(
            id: "cs",
            departure: at(2026, 11, 1, 10, 45, tz: "Asia/Tokyo"),
            arrival: at(2026, 11, 1, 13, 15, tz: "Asia/Seoul"),
            entered: "XX5701",
            airline: "YY",
            number: "YY1075",
            terminal: "T3"
        )
        #expect(shareText(for: codeshare, airportName: { names[$0] ?? $0 }, locale: ko) == """
        ✈ XX5701 (운항 YY1075)
        하네다 HND 11/01 10:45 → 인천 ICN 13:15 (현지 시각)
        출발 터미널 T3 · 게이트 미정
        D-Flight
        """)

        let direct = sampleTracked(
            id: "direct",
            departure: at(2026, 11, 1, 10, 45, tz: "Asia/Tokyo"),
            arrival: at(2026, 11, 1, 13, 15, tz: "Asia/Seoul"),
            entered: "xx 5701",
            airline: "XX",
            number: "XX5701",
            terminal: "T3"
        )
        #expect(shareText(for: direct, airportName: { names[$0] ?? $0 }, locale: ko) == """
        ✈ XX5701
        하네다 HND 11/01 10:45 → 인천 ICN 13:15 (현지 시각)
        출발 터미널 T3 · 게이트 미정
        D-Flight
        """)
    }

    private func state(
        value: String,
        source: DataSource,
        updated: Date,
        previous: String?,
        flight: Flight,
        now: Date
    ) -> InfoItemState {
        let item = InfoItem(value: value, source: source, updatedAt: updated, previousValue: previous)
        return infoState(item, side: flight.departure, flight: flight, now: now)
    }

    private func notice(id: String, publishedAt: Date, expiresAt: Date? = nil) -> Notice {
        Notice(id: id, title: ["ko": "제목"], body: ["ko": "본문"], important: false, publishedAt: publishedAt, expiresAt: expiresAt)
    }
}

private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    at(year, month, day, hour, minute, tz: "UTC")
}

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, second: Int = 0, tz: String) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: tz)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func sampleFlight(
    departure: Date? = nil,
    departureEstimated: Date? = nil,
    departureTimeZone: String = "Asia/Seoul",
    departureAirport: String = "ICN",
    arrival: Date? = nil,
    arrivalEstimated: Date? = nil,
    arrivalTimeZone: String = "Asia/Seoul",
    arrivalAirport: String = "HND",
    status: FlightStatusValue = .scheduled,
    departureAuto: Bool = true,
    arrivalAuto: Bool = true,
    failures: Int = 0,
    lastSuccess: Date? = nil,
    airline: String = "XX",
    number: String = "XX5701",
    terminal: String? = nil,
    gate: String? = nil
) -> Flight {
    Flight(
        key: "\(number)_2026-01-15_\(departureAirport)",
        operating: OperatingFlight(airline: airline, flightNumber: number),
        searchKeys: ["\(number)_2026-01-15"],
        origin: .airportData,
        departure: AirportSide(
            airport: departureAirport,
            timeZone: departureTimeZone,
            scheduledAt: departure,
            estimatedAt: TimeItem(value: departureEstimated),
            terminal: InfoItem(value: terminal),
            gate: InfoItem(value: gate),
            autoDataSupported: departureAuto
        ),
        arrival: AirportSide(
            airport: arrivalAirport,
            timeZone: arrivalTimeZone,
            scheduledAt: arrival,
            estimatedAt: TimeItem(value: arrivalEstimated),
            autoDataSupported: arrivalAuto
        ),
        status: FlightStatus(value: status),
        sync: SyncInfo(phase: .schedule, lastSuccessAt: lastSuccess, consecutiveFailures: failures),
        trackerCount: 1,
        isSample: true
    )
}

private func sampleTracked(
    id: String,
    departure: Date,
    arrival: Date? = nil,
    entered: String = "XX5701",
    airline: String = "XX",
    number: String = "XX5701",
    departureDate: String = "2026-11-01",
    terminal: String? = nil,
    depTZ: String = "Asia/Tokyo",
    arrTZ: String = "Asia/Seoul",
    depAirport: String = "HND",
    arrAirport: String = "ICN"
) -> TrackedFlight {
    let flight = sampleFlight(
        departure: departure,
        departureTimeZone: depTZ,
        departureAirport: depAirport,
        arrival: arrival,
        arrivalTimeZone: arrTZ,
        arrivalAirport: arrAirport,
        airline: airline,
        number: number,
        terminal: terminal
    )
    return TrackedFlight(
        id: id,
        flightKey: flight.key,
        enteredFlightNumber: entered,
        departureDate: departureDate,
        scheduledDepartureAt: departure,
        createdAt: utc(2026, 1, 1, 0, 0),
        isSample: true,
        flight: flight
    )
}
