import Foundation

#if MOCK_DATA

// 검색 마법 입력. 편명은 대문자로 바꾸고 공백은 뺀다.
// - XX5701 + 날짜: 그 날짜가 등록돼 있으면 alreadyTracked, 아니면 코드쉐어(YY1075 운항) 1건
// - XX100: 두 구간 found (ICN→HND, HND→ICN)
// - XX5702: 사용자 공유 1건 (origin user, 출발 터미널 source user)
// - XX999: notFound
// - XX000: 네트워크 오류
// - 그 외: notFound
// 실행 인자 -mockEmpty / -mockSignedOut / -mockForceUpdate 는 AppEnvironment.mock()가 읽는다.
// notices()는 미래·만료 공지도 포함한다. 화면은 visibleNotices로 거른다.

enum MockDataError: Error {
    case network
    case notFound
    case airportDataLocked
}

@MainActor
final class MockFlightRepository: FlightRepository {
    private let clock: Clock
    private let airports: [Airport]
    private var flightsByKey: [String: Flight] = [:]
    private var tracked: [TrackedFlight] = []

    init(includeTracked: Bool = true) {
        clock = Clock()
        airports = SampleAirports.all
        guard includeTracked else { return }
        let seeded = Self.samples(clock: clock)
        Self.validate(seeded, now: clock.now)
        for item in seeded {
            flightsByKey[item.flight.key] = item.flight
            tracked.append(item)
        }
    }

    func trackedFlights() async throws -> [TrackedFlight] {
        try await pause()
        return tracked
    }

    func refresh() async throws {
        try await pause()
    }

    func search(flightNumber: String, date: String) async throws -> FlightSearchResult {
        try await pause()
        let number = normalizeFlightNumber(flightNumber)
        if number == "XX000" { throw MockDataError.network }
        if number == "XX5701" {
            if let existing = tracked.first(where: {
                $0.departureDate == date && $0.enteredFlightNumber == "XX5701"
            }) {
                return .alreadyTracked(existing)
            }
            return .found([codeshare(on: date)])
        }
        if number == "XX100" {
            return .found(twoLegs(on: date))
        }
        if number == "XX5702" {
            return .found([sharedFlight(on: date)])
        }
        return .notFound
    }

    func track(flight: Flight, enteredFlightNumber: String) async throws -> TrackedFlight {
        try await pause()
        var flight = flight
        flight.isSample = true
        if let existing = tracked.first(where: { $0.flightKey == flight.key }) {
            return existing
        }
        flight.trackerCount = max(flight.trackerCount, 1)
        flightsByKey[flight.key] = flight
        let item = makeTracked(flight, entered: normalizeFlightNumber(enteredFlightNumber))
        tracked.append(item)
        return item
    }

    func createManual(_ input: ManualFlightInput) async throws -> TrackedFlight {
        try await pause()
        let number = normalizeFlightNumber(input.flightNumber)
        let depZone = zone(of: input.depAirport)
        let arrZone = zone(of: input.arrAirport)
        let departure = localDate(input.departureDate, time: input.scheduledDepartureLocal, timeZone: depZone, dayOffset: 0)
            ?? clock.now
        let arrival = input.scheduledArrivalLocal.flatMap {
            localDate(input.departureDate, time: $0, timeZone: arrZone, dayOffset: input.arrivalDayOffset)
        }
        let date = clock.dateString(departure, timeZone: depZone)
        let key = "\(number)_\(date)_\(input.depAirport)"
        if let existing = tracked.first(where: { $0.flightKey == key }) {
            return existing
        }
        let flight = flight(
            number: number,
            marketing: nil,
            depCode: input.depAirport,
            arrCode: input.arrAirport,
            departure: departure,
            arrival: arrival,
            origin: .user,
            status: .scheduled,
            sync: SyncInfo(phase: .done),
            depTerminal: userItem(input.terminal),
            depGate: userItem(input.gate),
            depCheckIn: input.checkInCounter.map { userItem($0) },
            arrBaggage: input.baggageBelt.map { userItem($0) },
            trackers: 1
        )
        flightsByKey[key] = flight
        let item = makeTracked(flight, entered: number)
        tracked.append(item)
        return item
    }

    func untrack(id: String) async throws {
        try await pause()
        guard let index = tracked.firstIndex(where: { $0.id == id }) else { return }
        let key = tracked[index].flightKey
        tracked.remove(at: index)
        guard var flight = flightsByKey[key] else { return }
        flight.trackerCount = max(0, flight.trackerCount - 1)
        flightsByKey[key] = flight
    }

    func updateFlightNotify(trackedId: String, _ notify: FlightNotify) async throws {
        try await pause()
        guard let index = tracked.firstIndex(where: { $0.id == trackedId }) else {
            throw MockDataError.notFound
        }
        tracked[index].notify = notify
    }

    func trackedFlight(id: String) async throws -> TrackedFlight? {
        try await pause()
        return tracked.first { $0.id == id }
    }

    func submitReport(flightKey: String, _ input: ReportInput) async throws {
        try await pause()
        guard let index = tracked.firstIndex(where: { $0.flightKey == flightKey }) else {
            throw MockDataError.airportDataLocked
        }
        var flight = tracked[index].flight
        if input.side == .departure {
            flight.departure = try reported(input, on: flight.departure, arrival: false)
        } else {
            flight.arrival = try reported(input, on: flight.arrival, arrival: true)
        }
        flight.isSample = true
        tracked[index].flight = flight
        flightsByKey[flightKey] = flight
    }

    func airports(matching query: String) async throws -> [Airport] {
        try await pause()
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return airports }
        return airports.filter { airport in
            airport.code.localizedCaseInsensitiveContains(keyword)
                || airport.nameKo.localizedCaseInsensitiveContains(keyword)
                || airport.nameJa.localizedCaseInsensitiveContains(keyword)
                || airport.nameEn.localizedCaseInsensitiveContains(keyword)
        }
    }

    func airport(code: String) async throws -> Airport? {
        let needle = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return airports.first { $0.code.caseInsensitiveCompare(needle) == .orderedSame }
    }

    func removeAllTracked() {
        let manual = Set(flightsByKey.values.filter { $0.origin == .user }.map(\.key))
        tracked.removeAll()
        for key in manual {
            flightsByKey[key] = nil
        }
        for key in flightsByKey.keys {
            flightsByKey[key]?.trackerCount = 0
        }
    }
}

@MainActor
final class MockAccountRepository: AccountRepository {
    private(set) var currentProvider: LoginProvider?
    private var stored = UserSettings.default
    var onDelete: () -> Void = {}

    init(startsSignedIn: Bool = true) {
        currentProvider = startsSignedIn ? .apple : nil
    }

    func signIn(_ provider: LoginProvider) async throws {
        try await pause()
        currentProvider = provider
    }

    func signOut() async throws {
        try await pause()
        currentProvider = nil
    }

    func deleteAccount() async throws {
        try await pause()
        stored = .default
        currentProvider = nil
        onDelete()
    }

    func settings() async throws -> UserSettings {
        try await pause()
        return stored
    }

    func updateSettings(_ settings: UserSettings) async throws {
        try await pause()
        stored = settings
    }
}

@MainActor
final class MockNoticeRepository: NoticeRepository {
    private let clock: Clock
    private let forceUpdate: Bool

    init(forceUpdate: Bool = false) {
        clock = Clock()
        self.forceUpdate = forceUpdate
    }

    func notices() async throws -> [Notice] {
        try await pause()
        let now = clock.now
        return [
            Notice(
                id: "notice-important",
                title: [
                    "ko": "샘플 중요 공지",
                    "ja": "サンプル重要なお知らせ",
                    "en": "Sample important notice"
                ],
                body: [
                    "ko": "가상 본문입니다. 실제 운항·공항 운영과 관계없습니다.",
                    "ja": "架空の本文です。実際の運航とは関係ありません。",
                    "en": "Virtual body. It is not a real operation notice."
                ],
                important: true,
                publishedAt: now.addingTimeInterval(-24 * 60 * 60),
                expiresAt: nil
            ),
            Notice(
                id: "notice-normal",
                title: [
                    "ko": "샘플 일반 공지",
                    "ja": "サンプル通常のお知らせ",
                    "en": "Sample notice"
                ],
                body: [
                    "ko": "목록에만 보이는 가상 공지입니다.",
                    "ja": "一覧だけに出る架空のお知らせです。",
                    "en": "A virtual notice that stays in the list."
                ],
                important: false,
                publishedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
                expiresAt: nil
            ),
            Notice(
                id: "notice-no-ja",
                title: [
                    "ko": "일본어가 없는 샘플 공지",
                    "en": "Sample notice without Japanese"
                ],
                body: [
                    "ko": "일본어가 없으면 영어, 그다음 한국어로 대신합니다.",
                    "en": "Missing Japanese falls back to English, then Korean."
                ],
                important: false,
                publishedAt: now.addingTimeInterval(-5 * 24 * 60 * 60),
                expiresAt: nil
            ),
            Notice(
                id: "notice-future",
                title: [
                    "ko": "아직 게시 전인 샘플",
                    "ja": "未公開のサンプル",
                    "en": "Unpublished sample"
                ],
                body: [
                    "ko": "게시 시각이 미래라 보이면 안 됩니다.",
                    "ja": "公開時刻が未来なので表示してはいけません。",
                    "en": "Hidden because publishedAt is in the future."
                ],
                important: false,
                publishedAt: now.addingTimeInterval(7 * 24 * 60 * 60),
                expiresAt: nil
            ),
            Notice(
                id: "notice-expired",
                title: [
                    "ko": "만료된 샘플 공지",
                    "ja": "期限切れのサンプル",
                    "en": "Expired sample notice"
                ],
                body: [
                    "ko": "만료 시각이 지나 보이면 안 됩니다.",
                    "ja": "期限が過ぎたので表示してはいけません。",
                    "en": "Hidden because it has expired."
                ],
                important: true,
                publishedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
                expiresAt: now.addingTimeInterval(-24 * 60 * 60)
            )
        ]
    }

    func minimumVersion() async -> (version: String, appStoreURL: URL)? {
        try? await Task.sleep(for: .milliseconds(300))
        guard forceUpdate, let url = URL(string: "https://apps.apple.com/app/id0000000000") else { return nil }
        return ("99.0.0", url)
    }
}

private func pause() async throws {
    try await Task.sleep(for: .milliseconds(300))
}

extension MockFlightRepository {
    fileprivate func zone(of code: String) -> String {
        airports.first { $0.code == code }?.timeZone ?? "Etc/UTC"
    }

    fileprivate func userItem(_ value: String?) -> InfoItem {
        guard let value, !value.isEmpty else { return InfoItem() }
        return InfoItem(value: value, source: .user, updatedAt: Date(), previousValue: nil)
    }

    fileprivate func makeTracked(_ flight: Flight, entered: String) -> TrackedFlight {
        TrackedFlight(
            id: UUID().uuidString,
            flightKey: flight.key,
            enteredFlightNumber: entered,
            departureDate: clock.dateString(flight.departure.scheduledAt ?? clock.now, timeZone: flight.departure.timeZone),
            scheduledDepartureAt: flight.departure.scheduledAt ?? clock.now,
            createdAt: Date(),
            isSample: true,
            notify: FlightNotify(),
            flight: flight
        )
    }

    fileprivate func codeshare(on date: String) -> Flight {
        let departure = clock.date(on: date, hour: 10, minute: 45, timeZone: "Asia/Tokyo") ?? clock.now
        return flight(
            number: "YY1075",
            marketing: "XX5701",
            depCode: "HND",
            arrCode: "ICN",
            departure: departure,
            arrival: departure.addingTimeInterval(150 * 60),
            origin: .airportData,
            status: .scheduled,
            sync: SyncInfo(phase: .schedule, lastSuccessAt: clock.now)
        )
    }

    fileprivate func twoLegs(on date: String) -> [Flight] {
        let outbound = clock.date(on: date, hour: 8, minute: 30, timeZone: "Asia/Seoul") ?? clock.now
        let inbound = clock.date(on: date, hour: 19, minute: 10, timeZone: "Asia/Tokyo") ?? clock.now
        return [
            flight(
                number: "XX100",
                depCode: "ICN",
                arrCode: "HND",
                departure: outbound,
                arrival: outbound.addingTimeInterval(140 * 60),
                origin: .airportData,
                status: .scheduled,
                sync: SyncInfo(phase: .schedule, lastSuccessAt: clock.now)
            ),
            flight(
                number: "XX100",
                depCode: "HND",
                arrCode: "ICN",
                departure: inbound,
                arrival: inbound.addingTimeInterval(150 * 60),
                origin: .airportData,
                status: .scheduled,
                sync: SyncInfo(phase: .schedule, lastSuccessAt: clock.now)
            )
        ]
    }

    fileprivate func sharedFlight(on date: String) -> Flight {
        let departure = clock.date(on: date, hour: 15, minute: 0, timeZone: "Asia/Tokyo") ?? clock.now
        return flight(
            number: "XX5702",
            depCode: "HND",
            arrCode: "GMP",
            departure: departure,
            arrival: departure.addingTimeInterval(140 * 60),
            origin: .user,
            status: .scheduled,
            sync: SyncInfo(phase: .done),
            depTerminal: InfoItem(value: "T3", source: .user, updatedAt: clock.now, previousValue: nil)
        )
    }

    fileprivate func reported(_ input: ReportInput, on side: AirportSide, arrival: Bool) throws -> AirportSide {
        var side = side
        side.terminal = try updated(input.terminal, side.terminal)
        side.gate = try updated(input.gate, side.gate)
        if arrival {
            if input.baggageBelt != nil {
                side.baggageBelt = try updated(input.baggageBelt, side.baggageBelt ?? InfoItem())
            }
        } else if input.checkInCounter != nil {
            side.checkInCounter = try updated(input.checkInCounter, side.checkInCounter ?? InfoItem())
        }
        return side
    }

    fileprivate func updated(_ change: String??, _ item: InfoItem) throws -> InfoItem {
        switch change {
        case nil:
            return item
        case .some(let value):
            if item.source == .airportData { throw MockDataError.airportDataLocked }
            var item = item
            item.value = value
            item.source = .user
            item.previousValue = nil
            item.updatedAt = Date()
            return item
        }
    }

    fileprivate func localDate(_ day: String, time: DateComponents, timeZone: String, dayOffset: Int) -> Date? {
        guard let base = clock.date(on: day, hour: time.hour ?? 0, minute: time.minute ?? 0, timeZone: timeZone) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        return calendar.date(byAdding: .day, value: dayOffset, to: base)
    }

    fileprivate static func samples(clock: Clock) -> [TrackedFlight] {
        let now = clock.now
        let hnd = clock.at(days: 3, hour: 10, minute: 45, timeZone: "Asia/Tokyo")
        let delayed = hnd.addingTimeInterval(45 * 60)
        let codeshare = MockFlightRepository.flight(
            clock: clock,
            number: "YY1075",
            marketing: "XX5701",
            depCode: "HND",
            arrCode: "ICN",
            departure: hnd,
            arrival: hnd.addingTimeInterval(150 * 60),
            origin: .airportData,
            status: .delayed,
            sync: SyncInfo(phase: .frequent, lastSuccessAt: now),
            depTerminal: InfoItem(value: "T3", source: .user, updatedAt: now, previousValue: nil),
            depGate: InfoItem(),
            depCheckIn: InfoItem(),
            depEstimated: delayed,
            arrTerminal: InfoItem(value: "T1", source: .airportData, updatedAt: now, previousValue: nil),
            arrGate: InfoItem(
                value: "25",
                source: .airportData,
                updatedAt: now.addingTimeInterval(-2 * 60 * 60),
                previousValue: "23"
            ),
            arrBaggage: InfoItem(),
            arrEstimated: delayed.addingTimeInterval(150 * 60),
            trackers: 1
        )
        let awaiting = MockFlightRepository.flight(
            clock: clock,
            number: "XX712",
            depCode: "ICN",
            arrCode: "NRT",
            departure: clock.at(days: 10, hour: 9, minute: 0, timeZone: "Asia/Seoul"),
            arrival: clock.at(days: 10, hour: 11, minute: 30, timeZone: "Asia/Tokyo"),
            origin: .airportData,
            status: .scheduled,
            sync: SyncInfo(phase: .schedule, lastSuccessAt: now),
            depTerminal: InfoItem(value: "T2", source: .airportData, updatedAt: now),
            depGate: InfoItem(),
            trackers: 1
        )
        let cancelled = MockFlightRepository.flight(
            clock: clock,
            number: "YY91",
            depCode: "HND",
            arrCode: "GMP",
            departure: clock.at(days: 5, hour: 14, minute: 0, timeZone: "Asia/Tokyo"),
            arrival: clock.at(days: 5, hour: 16, minute: 30, timeZone: "Asia/Seoul"),
            origin: .airportData,
            status: .cancelled,
            sync: SyncInfo(phase: .frequent, lastSuccessAt: now),
            trackers: 1
        )
        let failed = MockFlightRepository.flight(
            clock: clock,
            number: "XX301",
            depCode: "ICN",
            arrCode: "KIX",
            departure: clock.at(days: 2, hour: 18, minute: 20, timeZone: "Asia/Seoul"),
            arrival: clock.at(days: 2, hour: 20, minute: 0, timeZone: "Asia/Tokyo"),
            origin: .airportData,
            status: .scheduled,
            sync: SyncInfo(
                phase: .frequent,
                lastSuccessAt: now.addingTimeInterval(-3 * 60 * 60),
                lastFailureAt: now.addingTimeInterval(-15 * 60),
                consecutiveFailures: 2
            ),
            depTerminal: InfoItem(value: "T1", source: .airportData, updatedAt: now.addingTimeInterval(-3 * 60 * 60)),
            depGate: InfoItem(value: "108", source: .airportData, updatedAt: now.addingTimeInterval(-3 * 60 * 60)),
            trackers: 1
        )
        let manual = MockFlightRepository.flight(
            clock: clock,
            number: "XX88",
            depCode: "NRT",
            arrCode: "BKK",
            departure: clock.at(days: 20, hour: 11, minute: 0, timeZone: "Asia/Tokyo"),
            arrival: clock.at(days: 20, hour: 16, minute: 0, timeZone: "Asia/Bangkok"),
            origin: .user,
            status: .scheduled,
            sync: SyncInfo(phase: .done),
            trackers: 1
        )
        let todayDeparture = clock.laterToday(hours: 5, timeZone: "Asia/Seoul")
        let today = MockFlightRepository.flight(
            clock: clock,
            number: "XX202",
            depCode: "GMP",
            arrCode: "CJU",
            departure: todayDeparture,
            arrival: todayDeparture.addingTimeInterval(75 * 60),
            origin: .airportData,
            status: .scheduled,
            sync: SyncInfo(phase: .frequent, lastSuccessAt: now),
            depGate: InfoItem(value: "12", source: .airportData, updatedAt: now),
            trackers: 1
        )
        let laxDeparture = clock.at(days: 30, hour: 1, minute: 20, timeZone: "Asia/Seoul")
        let overnight = MockFlightRepository.flight(
            clock: clock,
            number: "YY7",
            depCode: "ICN",
            arrCode: "LAX",
            departure: laxDeparture,
            arrival: laxDeparture.addingTimeInterval(12 * 60 * 60),
            origin: .airportData,
            status: .scheduled,
            sync: SyncInfo(phase: .schedule, lastSuccessAt: now),
            trackers: 1
        )
        let arrivedAt = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let arrived = MockFlightRepository.flight(
            clock: clock,
            number: "XX150",
            depCode: "ICN",
            arrCode: "GMP",
            departure: arrivedAt.addingTimeInterval(-2 * 60 * 60),
            arrival: arrivedAt,
            origin: .airportData,
            status: .arrived,
            sync: SyncInfo(phase: .done, lastSuccessAt: arrivedAt),
            depGate: InfoItem(value: "23", source: .airportData, updatedAt: arrivedAt),
            trackers: 1
        )
        let departedAt = now.addingTimeInterval(-30 * 60 * 60)
        let departed = MockFlightRepository.flight(
            clock: clock,
            number: "XX160",
            depCode: "PUS",
            arrCode: "FUK",
            departure: departedAt,
            arrival: nil,
            origin: .airportData,
            status: .departed,
            sync: SyncInfo(phase: .done, lastSuccessAt: departedAt),
            depGate: InfoItem(value: "5", source: .airportData, updatedAt: departedAt),
            arrBaggage: nil,
            trackers: 1
        )
        return [codeshare, awaiting, cancelled, failed, manual, today, overnight, arrived, departed].map { flight in
            var flight = flight
            flight.isSample = true
            let entered = flight.searchKeys.first(where: { !$0.hasPrefix(flight.operating.flightNumber) })
                .map { String($0.split(separator: "_").first ?? "") }
                ?? flight.operating.flightNumber
            var notify = FlightNotify()
            if flight.operating.flightNumber == "XX712" {
                notify.dayBefore = false
            }
            return TrackedFlight(
                id: "sample-\(flight.operating.flightNumber)",
                flightKey: flight.key,
                enteredFlightNumber: entered.isEmpty ? flight.operating.flightNumber : entered,
                departureDate: clock.dateString(flight.departure.scheduledAt ?? now, timeZone: flight.departure.timeZone),
                scheduledDepartureAt: flight.departure.scheduledAt ?? now,
                createdAt: now,
                isSample: true,
                notify: notify,
                flight: flight
            )
        }
    }

    fileprivate static func validate(_ items: [TrackedFlight], now: Date) {
        func one(_ entered: String) -> TrackedFlight {
            guard let item = items.first(where: { $0.enteredFlightNumber == entered }) else {
                assertionFailure("샘플 \(entered) 없음")
                return items[0]
            }
            return item
        }
        let codeshare = one("XX5701")
        let awaiting = one("XX712")
        let cancelled = one("YY91")
        let failed = one("XX301")
        let manual = one("XX88")
        let today = one("XX202")
        let overnight = one("YY7")
        let arrived = one("XX150")
        let departed = one("XX160")
        for item in items {
            assert(item.isSample && item.flight.isSample, "isSample 유지")
            let airline = item.flight.operating.airline
            assert(airline == "XX" || airline == "YY", "항공사 코드는 XX/YY")
            for code in [item.flight.departure.airport, item.flight.arrival.airport] {
                let airport = SampleAirports.all.first { $0.code == code }
                assert(airport?.nameKo.isEmpty == false, "공항 이름 \(code)")
            }
        }
        assert(codeshare.flight.operating.flightNumber == "YY1075")
        assert(delayMinutes(codeshare.flight.departure) == 45)
        assert(dDay(for: codeshare.flight, now: now) == .days(3))
        assert(infoState(codeshare.flight.departure.checkInCounter ?? InfoItem(), side: codeshare.flight.departure, flight: codeshare.flight, now: now) == .noAutoData)
        if case .confirmedAirport(let gate, let changed, _) = infoState(codeshare.flight.arrival.gate, side: codeshare.flight.arrival, flight: codeshare.flight, now: now) {
            assert(gate == "25" && changed)
        } else {
            assertionFailure("도착 게이트 변경")
        }
        assert(infoState(codeshare.flight.arrival.baggageBelt ?? InfoItem(), side: codeshare.flight.arrival, flight: codeshare.flight, now: now) == .undetermined)
        assert(!awaiting.notify.dayBefore && awaiting.notify.changes && awaiting.notify.leaveForAirport && awaiting.notify.boarding)
        assert(codeshare.notify == FlightNotify())
        assert(infoState(awaiting.flight.departure.gate, side: awaiting.flight.departure, flight: awaiting.flight, now: now) == .awaiting)
        assert(dDay(for: awaiting.flight, now: now) == .days(10))
        assert(cancelled.flight.status.value == .cancelled)
        assert(dDay(for: cancelled.flight, now: now) == .days(5))
        if case .checkFailed(let last, _) = infoState(failed.flight.departure.gate, side: failed.flight.departure, flight: failed.flight, now: now) {
            assert(last == "108")
        } else {
            assertionFailure("확인 실패")
        }
        assert(failed.flight.sync.consecutiveFailures == 2)
        assert(manual.flight.origin == .user)
        assert(manual.flight.sync.provider == nil)
        assert(!manual.flight.departure.autoDataSupported && !manual.flight.arrival.autoDataSupported)
        assert(codeshare.flight.sync.provider == "iiac" && codeshare.flight.sync.lastSuccessAt != nil)
        assert(awaiting.flight.sync.provider == "iiac")
        assert(cancelled.flight.sync.provider == "kac" && cancelled.flight.sync.lastSuccessAt != nil)
        assert(failed.flight.sync.provider == "iiac")
        assert(today.flight.sync.provider == "kac")
        assert(overnight.flight.sync.provider == "iiac")
        assert(arrived.flight.sync.provider == "iiac")
        assert(departed.flight.sync.provider == "kac")
        assert(dDay(for: today.flight, now: now) == .today)
        assert(today.flight.departure.gate.value == "12")
        assert(needsLocalBadge(overnight.flight))
        assert(dayOffset(
            departure: overnight.flight.departure.scheduledAt ?? now,
            depTZ: overnight.flight.departure.timeZone,
            arrival: overnight.flight.arrival.scheduledAt ?? now,
            arrTZ: overnight.flight.arrival.timeZone
        ) != 0)
        assert(isPast(arrived.flight, now: now) && arrived.flight.status.value == .arrived)
        assert(isPast(departed.flight, now: now))
        assert(departed.flight.arrival.scheduledAt == nil && departed.flight.arrival.estimatedAt.value == nil)
    }

    fileprivate static func flight(
        clock: Clock,
        number: String,
        marketing: String? = nil,
        depCode: String,
        arrCode: String,
        departure: Date,
        arrival: Date?,
        origin: FlightOrigin,
        status: FlightStatusValue,
        sync: SyncInfo,
        depTerminal: InfoItem = InfoItem(),
        depGate: InfoItem = InfoItem(),
        depCheckIn: InfoItem? = InfoItem(),
        depEstimated: Date? = nil,
        arrTerminal: InfoItem = InfoItem(),
        arrGate: InfoItem = InfoItem(),
        arrBaggage: InfoItem? = InfoItem(),
        arrEstimated: Date? = nil,
        trackers: Int = 0
    ) -> Flight {
        let depZone = SampleAirports.zone(of: depCode)
        let arrZone = SampleAirports.zone(of: arrCode)
        let day = clock.dateString(departure, timeZone: depZone)
        var keys = ["\(number)_\(day)"]
        if let marketing, marketing != number {
            keys.append("\(marketing)_\(day)")
        }
        return Flight(
            key: "\(number)_\(day)_\(depCode)",
            operating: OperatingFlight(airline: airlineCode(of: number), flightNumber: number),
            searchKeys: keys,
            origin: origin,
            departure: AirportSide(
                airport: depCode,
                timeZone: depZone,
                scheduledAt: departure,
                estimatedAt: timeItem(depEstimated, at: clock.now),
                terminal: depTerminal,
                gate: depGate,
                checkInCounter: depCheckIn,
                baggageBelt: nil,
                autoDataSupported: SampleAirports.auto(depCode)
            ),
            arrival: AirportSide(
                airport: arrCode,
                timeZone: arrZone,
                scheduledAt: arrival,
                estimatedAt: timeItem(arrEstimated, at: clock.now),
                terminal: arrTerminal,
                gate: arrGate,
                checkInCounter: nil,
                baggageBelt: arrBaggage,
                autoDataSupported: SampleAirports.auto(arrCode)
            ),
            status: FlightStatus(
                value: status,
                source: origin == .user ? .user : .airportData,
                updatedAt: clock.now
            ),
            sync: stamped(sync, origin: origin, dep: depCode, arr: arrCode, now: clock.now),
            trackerCount: trackers,
            isSample: true
        )
    }

    fileprivate func flight(
        number: String,
        marketing: String? = nil,
        depCode: String,
        arrCode: String,
        departure: Date,
        arrival: Date?,
        origin: FlightOrigin,
        status: FlightStatusValue,
        sync: SyncInfo,
        depTerminal: InfoItem = InfoItem(),
        depGate: InfoItem = InfoItem(),
        depCheckIn: InfoItem? = InfoItem(),
        depEstimated: Date? = nil,
        arrTerminal: InfoItem = InfoItem(),
        arrGate: InfoItem = InfoItem(),
        arrBaggage: InfoItem? = InfoItem(),
        arrEstimated: Date? = nil,
        trackers: Int = 0
    ) -> Flight {
        Self.flight(
            clock: clock,
            number: number,
            marketing: marketing,
            depCode: depCode,
            arrCode: arrCode,
            departure: departure,
            arrival: arrival,
            origin: origin,
            status: status,
            sync: sync,
            depTerminal: depTerminal,
            depGate: depGate,
            depCheckIn: depCheckIn,
            depEstimated: depEstimated,
            arrTerminal: arrTerminal,
            arrGate: arrGate,
            arrBaggage: arrBaggage,
            arrEstimated: arrEstimated,
            trackers: trackers
        )
    }
}

/// 한국 공항이 있으면 공급원을 붙인다. 직접 입력·사용자 공유는 공급원 없음.
private func stamped(_ sync: SyncInfo, origin: FlightOrigin, dep: String, arr: String, now: Date) -> SyncInfo {
    var sync = sync
    guard origin != .user else {
        sync.provider = nil
        return sync
    }
    let codes = [dep, arr]
    if codes.contains("ICN") {
        sync.provider = "iiac"
    } else if codes.contains(where: { ["GMP", "PUS", "CJU"].contains($0) }) {
        sync.provider = "kac"
    } else {
        return sync
    }
    if sync.lastSuccessAt == nil {
        sync.lastSuccessAt = now
    }
    return sync
}

private func airlineCode(of flightNumber: String) -> String {
    let number = normalizeFlightNumber(flightNumber)
    let letters = number.prefix { $0.isLetter }
    if (2...3).contains(letters.count), number.dropFirst(letters.count).allSatisfy(\.isNumber) {
        return String(letters)
    }
    return String(number.prefix(2))
}

private func timeItem(_ date: Date?, at updated: Date) -> TimeItem {
    guard let date else { return TimeItem() }
    return TimeItem(value: date, source: .airportData, updatedAt: updated)
}

private struct Clock {
    let now = Date()

    func at(days: Int, hour: Int, minute: Int, timeZone: String) -> Date {
        let calendar = gregorian(timeZone)
        let start = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: days, to: start) ?? start
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? day
    }

    func laterToday(hours: TimeInterval, timeZone: String) -> Date {
        let calendar = gregorian(timeZone)
        let candidate = now.addingTimeInterval(hours * 60 * 60)
        if calendar.isDate(candidate, inSameDayAs: now) { return candidate }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? candidate
        return max(now.addingTimeInterval(60), end.addingTimeInterval(-60))
    }

    func date(on day: String, hour: Int, minute: Int, timeZone: String) -> Date? {
        let pieces = day.split(separator: "-")
        guard pieces.count == 3, let year = Int(pieces[0]), let month = Int(pieces[1]), let date = Int(pieces[2]) else {
            return nil
        }
        let calendar = gregorian(timeZone)
        return calendar.date(from: DateComponents(year: year, month: month, day: date, hour: hour, minute: minute))
    }

    func dateString(_ date: Date, timeZone: String) -> String {
        let parts = gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func gregorian(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        return calendar
    }
}

private enum SampleAirports {
    static let all: [Airport] = [
        airport("ICN", "인천", "仁川", "Incheon", "Asia/Seoul", ["T1", "T2"], "https://www.airport.kr/geomap/ap_en/view.do?type=2&alertType=0&tmnlId=P01"),
        airport("GMP", "김포", "金浦", "Gimpo", "Asia/Seoul", [], nil),
        airport("PUS", "김해", "金海", "Gimhae", "Asia/Seoul", [], nil),
        airport("CJU", "제주", "済州", "Jeju", "Asia/Seoul", [], nil),
        airport("HND", "하네다", "羽田", "Haneda", "Asia/Tokyo", ["T1", "T2", "T3"], "https://tokyo-haneda.com/en/floor/index.html"),
        airport("NRT", "나리타", "成田", "Narita", "Asia/Tokyo", ["T1", "T2", "T3"], "https://www.narita-airport.jp/en/map/"),
        airport("KIX", "간사이", "関西", "Kansai", "Asia/Tokyo", [], nil),
        airport("FUK", "후쿠오카", "福岡", "Fukuoka", "Asia/Tokyo", [], nil),
        airport("BKK", "방콕", "バンコク", "Bangkok", "Asia/Bangkok", [], nil),
        airport("LAX", "로스앤젤레스", "ロサンゼルス", "Los Angeles", "America/Los_Angeles", [], nil)
    ]

    static func zone(of code: String) -> String {
        all.first { $0.code == code }?.timeZone ?? "Etc/UTC"
    }

    static func auto(_ code: String) -> Bool {
        ["ICN", "GMP", "PUS", "CJU"].contains(code)
    }

    private static func airport(
        _ code: String,
        _ ko: String,
        _ ja: String,
        _ en: String,
        _ timeZone: String,
        _ terminals: [String],
        _ map: String?
    ) -> Airport {
        Airport(
            code: code,
            nameKo: ko,
            nameJa: ja,
            nameEn: en,
            timeZone: timeZone,
            terminals: terminals,
            mapURL: map.flatMap(URL.init(string:))
        )
    }
}

#endif
