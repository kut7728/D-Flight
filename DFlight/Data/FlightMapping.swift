import Foundation

/// 검색 응답을 화면 결과로 바꾸기 전의 값. 이미 등록한 편은 키만 있다.
nonisolated enum SearchMapping: Equatable, Sendable {
    case found([Flight])
    case notFound(NotFoundReason?)
    case alreadyTracked(flightKey: String)
}

/// Firestore `flights` 문서. `Timestamp`는 호출 전에 `Date`로 바꾼다.
nonisolated func mapFlightDocument(key: String, data: [String: Any]) -> Flight? {
    guard let operating = data["operating"] as? [String: Any],
          let airline = text(operating["airline"]),
          let flightNumber = text(operating["flightNumber"]),
          let origin = (data["origin"] as? String).flatMap(FlightOrigin.init(rawValue:)),
          let departure = mapSide(data["departure"]),
          let arrival = mapSide(data["arrival"]),
          let status = mapStatus(data["status"]),
          let sync = mapSync(data["sync"]) else { return nil }
    return Flight(
        key: key,
        operating: OperatingFlight(airline: airline, flightNumber: flightNumber),
        searchKeys: stringList(data["searchKeys"]),
        origin: origin,
        departure: departure,
        arrival: arrival,
        status: status,
        sync: sync,
        trackerCount: wholeNumber(data["trackerCount"]) ?? 0,
        isSample: false
    )
}

/// `users/{uid}/trackedFlights` 문서. 샘플이 아니다.
nonisolated func mapTrackedDocument(id: String, data: [String: Any], flight: Flight) -> TrackedFlight? {
    guard let flightKey = text(data["flightKey"]),
          let entered = text(data["enteredFlightNumber"]),
          let departureDate = text(data["departureDate"]),
          let scheduled = parseTimestamp(data["scheduledDepartureAt"]),
          let created = parseTimestamp(data["createdAt"]) else { return nil }
    return TrackedFlight(
        id: id,
        flightKey: flightKey,
        enteredFlightNumber: entered,
        departureDate: departureDate,
        scheduledDepartureAt: scheduled,
        createdAt: created,
        isSample: false,
        notify: mapNotify(data["notify"]),
        flight: flight
    )
}

/// `searchFlight` 응답. 후보가 있는데 하나도 읽지 못하면 nil.
nonisolated func mapSearchResponse(_ data: [String: Any]) -> SearchMapping? {
    guard let rawList = candidateList(data["candidates"]) else { return nil }
    var fresh: [Flight] = []
    var trackedKeys: [String] = []
    var sawCandidate = false
    for item in rawList {
        guard let candidate = item as? [String: Any] else { return nil }
        sawCandidate = true
        let alreadyTracked = candidate["alreadyTracked"] as? Bool ?? false
        if alreadyTracked, let key = text(candidate["flightKey"]) {
            trackedKeys.append(key)
            continue
        }
        if let flight = mapSearchFlight(candidate) {
            fresh.append(flight)
        }
    }
    if fresh.isEmpty {
        if let key = trackedKeys.first {
            return .alreadyTracked(flightKey: key)
        }
        if sawCandidate { return nil }
        return .notFound(notFoundReason(data["notFoundReason"]))
    }
    return .found(fresh)
}

/// `createManualFlight` 본문. 시각은 `HH:mm`, 없으면 생략. 선택 항목은 `fields`.
nonisolated func manualFlightPayload(_ input: ManualFlightInput) -> [String: any Sendable] {
    var payload: [String: any Sendable] = [
        "flightNumber": normalizeFlightNumber(input.flightNumber),
        "departureDate": input.departureDate,
        "departureAirport": input.depAirport.uppercased(),
        "arrivalAirport": input.arrAirport.uppercased(),
    ]
    if let departure = input.scheduledDepartureLocal {
        payload["departureTime"] = clock(departure)
    }
    if input.awaitAutoData {
        payload["awaitAutoData"] = true
    }
    if let arrival = input.scheduledArrivalLocal {
        payload["arrivalTime"] = clock(arrival)
        payload["arrivalDayOffset"] = input.arrivalDayOffset
    }
    var fields: [String: String] = [:]
    if let terminal = input.terminal { fields["departure.terminal"] = terminal }
    if let gate = input.gate { fields["departure.gate"] = gate }
    if let counter = input.checkInCounter { fields["departure.checkInCounter"] = counter }
    if let belt = input.baggageBelt { fields["arrival.baggageBelt"] = belt }
    if !fields.isEmpty {
        payload["fields"] = fields
    }
    return payload
}

nonisolated func parseTimestamp(_ value: Any?) -> Date? {
    switch value {
    case let date as Date:
        return date
    case let text as String:
        return parseISO8601(text)
    case let map as [String: Any]:
        guard let seconds = finiteNumber(map["seconds"] ?? map["_seconds"]) else { return nil }
        let nanos = finiteNumber(map["nanoseconds"] ?? map["_nanoseconds"]) ?? 0
        return Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
    default:
        return finiteNumber(value).map { Date(timeIntervalSince1970: $0) }
    }
}

private nonisolated func mapSearchFlight(_ data: [String: Any]) -> Flight? {
    guard let key = text(data["flightKey"]),
          let operating = data["operating"] as? [String: Any],
          let airline = text(operating["airline"]),
          let flightNumber = text(operating["flightNumber"]),
          let level = data["dataLevel"] as? String,
          level == "realtime" || level == "schedule" || level == "user" else { return nil }
    let user = level == "user"
    let origin: FlightOrigin = user ? .user : .airportData
    guard let departure = mapSearchSide(data["departure"], auto: !user),
          let arrival = mapSearchSide(data["arrival"], auto: !user) else { return nil }
    return Flight(
        key: key,
        operating: OperatingFlight(airline: airline, flightNumber: flightNumber),
        searchKeys: [],
        origin: origin,
        departure: departure,
        arrival: arrival,
        status: FlightStatus(value: .scheduled, source: user ? .user : .airportData),
        sync: SyncInfo(phase: user ? .done : .schedule),
        trackerCount: 0,
        isSample: false
    )
}

private nonisolated func mapSearchSide(_ value: Any?, auto: Bool) -> AirportSide? {
    guard let map = value as? [String: Any],
          let airport = text(map["airport"]),
          let timeZone = text(map["timeZone"]) else { return nil }
    return AirportSide(
        airport: airport,
        timeZone: timeZone,
        scheduledAt: parseTimestamp(map["scheduledAt"]),
        autoDataSupported: auto
    )
}

private nonisolated func mapSide(_ value: Any?) -> AirportSide? {
    guard let map = value as? [String: Any],
          let airport = text(map["airport"]),
          let timeZone = text(map["timeZone"]) else { return nil }
    return AirportSide(
        airport: airport,
        timeZone: timeZone,
        scheduledAt: parseTimestamp(map["scheduledAt"]),
        estimatedAt: mapTimeItem(map["estimatedAt"]),
        terminal: mapInfoItem(map["terminal"]),
        gate: mapInfoItem(map["gate"]),
        checkInCounter: optionalItem(map["checkInCounter"]),
        baggageBelt: optionalItem(map["baggageBelt"]),
        autoDataSupported: map["autoDataSupported"] as? Bool ?? false
    )
}

private nonisolated func optionalItem(_ value: Any?) -> InfoItem? {
    guard let value, !(value is NSNull) else { return nil }
    return mapInfoItem(value)
}

private nonisolated func mapInfoItem(_ value: Any?) -> InfoItem {
    guard let map = value as? [String: Any] else { return InfoItem() }
    return InfoItem(
        value: map["value"] as? String,
        source: (map["source"] as? String).flatMap(DataSource.init(rawValue:)),
        updatedAt: parseTimestamp(map["updatedAt"]),
        previousValue: map["previousValue"] as? String
    )
}

private nonisolated func mapTimeItem(_ value: Any?) -> TimeItem {
    guard let map = value as? [String: Any] else { return TimeItem() }
    return TimeItem(
        value: parseTimestamp(map["value"]),
        source: (map["source"] as? String).flatMap(DataSource.init(rawValue:)),
        updatedAt: parseTimestamp(map["updatedAt"])
    )
}

private nonisolated func mapStatus(_ value: Any?) -> FlightStatus? {
    guard let map = value as? [String: Any],
          let raw = map["value"] as? String,
          let status = FlightStatusValue(rawValue: raw) else { return nil }
    return FlightStatus(
        value: status,
        source: (map["source"] as? String).flatMap(DataSource.init(rawValue:)),
        updatedAt: parseTimestamp(map["updatedAt"])
    )
}

private nonisolated func mapSync(_ value: Any?) -> SyncInfo? {
    guard let map = value as? [String: Any],
          let raw = map["phase"] as? String,
          let phase = SyncPhase(rawValue: raw) else { return nil }
    return SyncInfo(
        phase: phase,
        nextPollAt: parseTimestamp(map["nextPollAt"]),
        lastSuccessAt: parseTimestamp(map["lastSuccessAt"]),
        lastFailureAt: parseTimestamp(map["lastFailureAt"]),
        consecutiveFailures: wholeNumber(map["consecutiveFailures"]) ?? 0,
        provider: map["provider"] as? String
    )
}

private nonisolated func mapNotify(_ value: Any?) -> FlightNotify {
    guard let map = value as? [String: Any] else { return FlightNotify() }
    return FlightNotify(
        changes: map["changes"] as? Bool ?? true,
        dayBefore: map["dayBefore"] as? Bool ?? true,
        leaveForAirport: map["leaveForAirport"] as? Bool ?? true,
        boarding: map["boarding"] as? Bool ?? true
    )
}

/// `[[String: Any]]`는 `[Any]`로 캐스팅되지 않는다.
private nonisolated func candidateList(_ value: Any?) -> [Any]? {
    if let list = value as? [[String: Any]] { return list.map { $0 as Any } }
    if let list = value as? [Any] { return list }
    return nil
}

private nonisolated func notFoundReason(_ value: Any?) -> NotFoundReason? {
    guard let raw = value as? String else { return nil }
    return NotFoundReason(rawValue: raw)
}

private nonisolated func text(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else { return nil }
    return value
}

private nonisolated func stringList(_ value: Any?) -> [String] {
    if let list = value as? [String] { return list }
    if let list = value as? [Any] { return list.compactMap { $0 as? String } }
    return []
}

private nonisolated func wholeNumber(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let number = value as? Int64 { return Int(number) }
    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.intValue
    }
    return nil
}

private nonisolated func finiteNumber(_ value: Any?) -> Double? {
    switch value {
    case let number as Double:
        return number
    case let number as Int:
        return Double(number)
    case let number as Int64:
        return Double(number)
    case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.doubleValue
    default:
        return nil
    }
}

private nonisolated func parseISO8601(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text)
}

private nonisolated func clock(_ components: DateComponents) -> String {
    String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
}
