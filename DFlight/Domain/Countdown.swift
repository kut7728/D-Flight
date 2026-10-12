import Foundation

/// 상세 배너에 쓰는 남은 시간. 24시간 전까지는 D-n, 그 안은 시:분.
nonisolated enum Countdown: Hashable, Sendable {
    /// 출발까지 24시간 이상. 숫자는 `dDay`와 같은 출발 공항 현지 날짜.
    case days(Int)
    /// 출발까지 24시간 미만.
    case remaining(hours: Int, minutes: Int)
    case departed
    case arrived
    case cancelled
}

nonisolated func countdown(for flight: Flight, now: Date) -> Countdown {
    switch flight.status.value {
    case .cancelled:
        return .cancelled
    case .arrived:
        return .arrived
    case .departed:
        return .departed
    case .scheduled, .delayed, .unknown:
        break
    }

    // 지연·조기는 예정 시각이 아니라 변경된 시각까지 센다.
    guard let departure = flight.departure.estimatedAt.value ?? flight.departure.scheduledAt else {
        return countdown(matching: dDay(for: flight, now: now))
    }
    let interval = departure.timeIntervalSince(now)
    if interval <= 0 {
        return .departed
    }
    if interval >= 24 * 60 * 60 {
        switch dDay(for: flight, now: now) {
        case .days(let count) where count > 0:
            return .days(count)
        case .arrived:
            return .arrived
        case .days, .today, .departed:
            // 예정일은 지났어도 변경 시각이 24시간 이상 남으면 그 날짜의 D-n.
            let days = originDayDistance(to: departure, timeZone: flight.departure.timeZone, now: now)
            return .days(max(days, 1))
        }
    }
    let minutes = Int(interval / 60)
    return .remaining(hours: minutes / 60, minutes: minutes % 60)
}

private nonisolated func countdown(matching day: DDay) -> Countdown {
    switch day {
    case .days(let count):
        .days(count)
    case .today:
        .days(0)
    case .departed:
        .departed
    case .arrived:
        .arrived
    }
}

private nonisolated func originDayDistance(to date: Date, timeZone: String, now: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
    return calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: now),
        to: calendar.startOfDay(for: date)
    ).day ?? 0
}
