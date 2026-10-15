import Foundation

nonisolated enum DDay: Hashable, Sendable {
    /// D-n. n은 1 이상.
    case days(Int)
    case today
    case departed
    case arrived
}

nonisolated enum InfoItemState: Hashable, Sendable {
    case confirmedAirport(String, changed: Bool, previous: String?)
    case confirmedUser(String)
    case undetermined
    case awaiting
    case noAutoData
    case checkFailed(lastValue: String?, since: Date?)
}

nonisolated func dDay(for flight: Flight, now: Date, departureDate: String? = nil) -> DDay {
    switch flight.status.value {
    case .arrived:
        return .arrived
    case .departed:
        return .departed
    case .scheduled, .delayed, .cancelled, .unknown:
        break
    }
    guard let days = daysUntilOriginDeparture(flight, now: now, departureDate: departureDate) else { return .today }
    if days > 0 { return .days(days) }
    if days == 0 { return .today }
    // 결항은 날짜가 지나도 출발함이 아니다. 지난 목록 이동은 isPast가 맡는다.
    if flight.status.value == .cancelled { return .today }
    return .departed
}

nonisolated func localTime(_ date: Date, timeZone: String, locale: Locale) -> String {
    let zone = TimeZone(identifier: timeZone) ?? .gmt
    return date.formatted(
        .verbatim(
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: locale,
            timeZone: zone,
            calendar: Calendar(identifier: .gregorian)
        )
    )
}

nonisolated func dayOffset(departure: Date, depTZ: String, arrival: Date, arrTZ: String) -> Int {
    let departureDay = gregorian(depTZ).dateComponents([.year, .month, .day], from: departure)
    let arrivalDay = gregorian(arrTZ).dateComponents([.year, .month, .day], from: arrival)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    guard let start = utc.date(from: departureDay), let end = utc.date(from: arrivalDay) else { return 0 }
    return utc.dateComponents([.day], from: start, to: end).day ?? 0
}

nonisolated func needsLocalBadge(_ flight: Flight) -> Bool {
    flight.departure.timeZone != flight.arrival.timeZone
}

nonisolated func infoState(_ item: InfoItem, side: AirportSide, flight: Flight, now: Date) -> InfoItemState {
    // 연속 실패는 자동 정보가 있는 쪽에만 적용한다.
    if side.autoDataSupported, flight.sync.consecutiveFailures >= 2 {
        return .checkFailed(lastValue: item.value, since: flight.sync.lastSuccessAt)
    }
    if let value = item.value, !value.isEmpty {
        if item.source == .user {
            return .confirmedUser(value)
        }
        let changed = item.source == .airportData && item.previousValue != nil && changedWithin24Hours(item.updatedAt, now: now)
        return .confirmedAirport(value, changed: changed, previous: changed ? item.previousValue : nil)
    }
    // 시간표가 없으면 날짜와 상관없이 대기. 값이 생기면 위 분기에서 보여 준다.
    if flight.origin == .pending {
        return .awaiting
    }
    guard side.autoDataSupported else { return .noAutoData }
    // 출발 공항 현지 날짜로 3일보다 더 남았으면 정보 대기.
    if let days = daysUntilOriginDeparture(flight, now: now), days > 3 {
        return .awaiting
    }
    return .undetermined
}

nonisolated func isPast(_ flight: Flight, now: Date) -> Bool {
    if let arrival = flight.arrival.estimatedAt.value ?? flight.arrival.scheduledAt {
        return now >= arrival.addingTimeInterval(3 * 60 * 60)
    }
    if let departure = flight.departure.estimatedAt.value ?? flight.departure.scheduledAt {
        return now >= departure.addingTimeInterval(24 * 60 * 60)
    }
    return false
}

nonisolated func estimatedBoardingTime(_ flight: Flight) -> Date? {
    guard let departure = flight.departure.estimatedAt.value ?? flight.departure.scheduledAt else { return nil }
    return departure.addingTimeInterval(-40 * 60)
}

/// 양수는 지연, 음수는 조기. 시각이 없거나 같으면 nil.
nonisolated func delayMinutes(_ side: AirportSide) -> Int? {
    guard let scheduled = side.scheduledAt, let estimated = side.estimatedAt.value else { return nil }
    let minutes = Int((estimated.timeIntervalSince(scheduled) / 60).rounded())
    return minutes == 0 ? nil : minutes
}

nonisolated func isVersion(_ version: String, lowerThan minimum: String) -> Bool {
    let left = versionComponents(version)
    let right = versionComponents(minimum)
    let count = max(left.count, right.count)
    for index in 0..<count {
        let lhs = index < left.count ? left[index] : 0
        let rhs = index < right.count ? right[index] : 0
        if lhs != rhs { return lhs < rhs }
    }
    return false
}

nonisolated func localized(_ map: [String: String], language: String) -> String {
    if let value = nonempty(map[language]) { return value }
    if let value = nonempty(map["en"]) { return value }
    if let value = nonempty(map["ko"]) { return value }
    return ""
}

nonisolated func visibleNotices(_ list: [Notice], now: Date) -> [Notice] {
    Array(
        list.filter { notice in
            notice.publishedAt <= now && (notice.expiresAt.map { $0 > now } ?? true)
        }
        .sorted { $0.publishedAt > $1.publishedAt }
        .prefix(50)
    )
}

nonisolated func normalizeFlightNumber(_ text: String) -> String {
    text.uppercased().filter { !$0.isWhitespace }
}

/// 항공사 2~3자(두 글자가 둘 다 숫자는 아님) + 숫자 1~4자리 + 선택 접미 영문.
nonisolated func isValidFlightNumber(_ text: String) -> Bool {
    let normalized = normalizeFlightNumber(text)
    return normalized.wholeMatch(of: /^(?:[A-Z]{2}[A-Z]?|[A-Z][0-9]|[0-9][A-Z])[0-9]{1,4}[A-Z]?$/) != nil
}

nonisolated func isValidGate(_ text: String) -> Bool {
    text.wholeMatch(of: /^[A-Za-z0-9]{1,5}$/) != nil
}

nonisolated func isValidCheckInCounter(_ text: String) -> Bool {
    text.wholeMatch(of: /^[A-Za-z0-9-]{1,7}$/) != nil
}

nonisolated func isValidBaggageBelt(_ text: String) -> Bool {
    text.wholeMatch(of: /^[A-Za-z0-9]{1,3}$/) != nil
}

/// 다가오는 편은 예정 출발이 빠른 순, 지난 편은 최근 출발이 먼저.
nonisolated func partitionFlights(_ list: [TrackedFlight], now: Date) -> (upcoming: [TrackedFlight], past: [TrackedFlight]) {
    let upcoming = list
        .filter { !isPast($0.flight, now: now) }
        .sorted { $0.scheduledDepartureAt < $1.scheduledDepartureAt }
    let past = list
        .filter { isPast($0.flight, now: now) }
        .sorted { $0.scheduledDepartureAt > $1.scheduledDepartureAt }
    return (upcoming, past)
}

nonisolated func shareText(
    for tracked: TrackedFlight,
    airportName: (String) -> String,
    locale: Locale
) -> String {
    let entered = normalizeFlightNumber(tracked.enteredFlightNumber)
    let operating = operatingFlightNumber(tracked.flight.operating)
    let title = entered == operating
        ? String(format: appString("✈ %@", locale: locale), locale: locale, entered)
        : String(format: appString("✈ %@ (운항 %@)", locale: locale), locale: locale, entered, operating)

    let departure = tracked.flight.departure
    let arrival = tracked.flight.arrival
    let depClock = localClock(departure.estimatedAt.value ?? departure.scheduledAt, timeZone: departure.timeZone, locale: locale)
    let arrClock = localClock(arrival.estimatedAt.value ?? arrival.scheduledAt, timeZone: arrival.timeZone, locale: locale)
    let route = String(
        format: appString("%1$@ %2$@ %3$@ %4$@ → %5$@ %6$@ %7$@ (현지 시각)", locale: locale),
        locale: locale,
        airportName(departure.airport),
        departure.airport,
        monthSlashDay(tracked.departureDate),
        depClock,
        airportName(arrival.airport),
        arrival.airport,
        arrClock
    )

    let terminal = shareValue(departure.terminal.value, locale: locale)
    let gate = shareValue(departure.gate.value, locale: locale)
    let place = String(
        format: appString("출발 터미널 %@ · 게이트 %@", locale: locale),
        locale: locale,
        terminal,
        gate
    )
    return "\(title)\n\(route)\n\(place)\nD-Flight"
}

private nonisolated func daysUntilOriginDeparture(_ flight: Flight, now: Date, departureDate: String? = nil) -> Int? {
    let calendar = gregorian(flight.departure.timeZone)
    let instant = flight.departure.scheduledAt ?? flight.departure.estimatedAt.value
    let target = instant ?? departureDate.flatMap { civilDate($0, calendar: calendar) }
    guard let target else { return nil }
    return calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: now),
        to: calendar.startOfDay(for: target)
    ).day
}

/// `yyyy-MM-dd`를 출발 공항 시간대의 그 날로 읽는다.
private nonisolated func civilDate(_ ymd: String, calendar: Calendar) -> Date? {
    let parts = ymd.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

private nonisolated func changedWithin24Hours(_ updatedAt: Date?, now: Date) -> Bool {
    guard let updatedAt else { return false }
    let age = now.timeIntervalSince(updatedAt)
    return age >= 0 && age < 24 * 60 * 60
}

private nonisolated func versionComponents(_ version: String) -> [Int] {
    version.split(separator: ".").map { Int($0) ?? 0 }
}

private nonisolated func nonempty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

private nonisolated func gregorian(_ timeZoneID: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
    return calendar
}

private nonisolated func operatingFlightNumber(_ operating: OperatingFlight) -> String {
    let number = normalizeFlightNumber(operating.flightNumber)
    let airline = normalizeFlightNumber(operating.airline)
    if number.hasPrefix(airline) { return number }
    return airline + number
}

private nonisolated func monthSlashDay(_ departureDate: String) -> String {
    let parts = departureDate.split(separator: "-")
    guard parts.count == 3 else { return departureDate }
    return "\(parts[1])/\(parts[2])"
}

private nonisolated func localClock(_ date: Date?, timeZone: String, locale: Locale) -> String {
    guard let date else { return "" }
    return localTime(date, timeZone: timeZone, locale: locale)
}

private nonisolated func shareValue(_ value: String?, locale: Locale) -> String {
    if let value, !value.isEmpty { return value }
    return appString("미정", locale: locale)
}
