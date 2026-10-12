import Foundation
import Testing
@testable import DFlight

@Suite("남은 시간")
struct CountdownTests {
    @Test("24시간 경계는 D-n, 1초 안쪽은 시:분")
    func dayBoundary() {
        let departure = at(2026, 11, 1, 10, 45, tz: "Asia/Tokyo")
        let flight = sample(departure: departure, timeZone: "Asia/Tokyo")
        let day = 24 * 60 * 60.0

        #expect(countdown(for: flight, now: departure.addingTimeInterval(-day)) == .days(1))
        #expect(countdown(for: flight, now: departure.addingTimeInterval(-day - 1)) == .days(1))
        #expect(countdown(for: flight, now: departure.addingTimeInterval(-day + 1)) == .remaining(hours: 23, minutes: 59))
        #expect(countdown(for: flight, now: departure.addingTimeInterval(-(80 * 60))) == .remaining(hours: 1, minutes: 20))
        #expect(countdown(for: flight, now: departure.addingTimeInterval(-(80 * 60 + 30))) == .remaining(hours: 1, minutes: 20))
    }

    @Test("지연은 예정 시각이 아니라 변경된 시각")
    func delayedUsesEstimatedTime() {
        let now = at(2026, 6, 1, 10, 0, tz: "Asia/Seoul")
        let scheduledSoon = at(2026, 6, 2, 9, 0, tz: "Asia/Seoul")
        let estimatedLater = at(2026, 6, 2, 11, 0, tz: "Asia/Seoul")
        let crosses = sample(
            departure: scheduledSoon,
            estimated: estimatedLater,
            timeZone: "Asia/Seoul",
            status: .delayed
        )
        #expect(countdown(for: crosses, now: now) == .days(1))

        let scheduled = now.addingTimeInterval(20 * 60 * 60)
        let estimated = scheduled.addingTimeInterval(45 * 60)
        let minutes = sample(departure: scheduled, estimated: estimated, status: .delayed)
        #expect(countdown(for: minutes, now: now) == .remaining(hours: 20, minutes: 45))

        let already = sample(
            departure: now.addingTimeInterval(-10 * 60),
            estimated: now.addingTimeInterval(45 * 60),
            status: .delayed
        )
        #expect(countdown(for: already, now: now) == .remaining(hours: 0, minutes: 45))
    }

    @Test("결항·도착·출발함은 남은 시간보다 앞선다")
    func terminalStatus() {
        let now = at(2026, 6, 1, 10, 0, tz: "Asia/Seoul")
        let future = at(2026, 6, 4, 10, 0, tz: "Asia/Seoul")
        #expect(countdown(for: sample(departure: future, status: .cancelled), now: now) == .cancelled)
        #expect(countdown(for: sample(departure: now.addingTimeInterval(-60), status: .cancelled), now: now) == .cancelled)
        #expect(countdown(for: sample(departure: future, status: .arrived), now: now) == .arrived)
        #expect(countdown(for: sample(departure: future, status: .departed), now: now) == .departed)
        #expect(countdown(for: sample(departure: now.addingTimeInterval(-60)), now: now) == .departed)
    }

    private func sample(
        departure: Date,
        estimated: Date? = nil,
        timeZone: String = "Asia/Seoul",
        status: FlightStatusValue = .scheduled
    ) -> Flight {
        Flight(
            key: "XX5701_2026-06-01_ICN",
            operating: OperatingFlight(airline: "XX", flightNumber: "XX5701"),
            searchKeys: ["XX5701_2026-06-01"],
            origin: .airportData,
            departure: AirportSide(
                airport: "ICN",
                timeZone: timeZone,
                scheduledAt: departure,
                estimatedAt: TimeItem(value: estimated),
                autoDataSupported: true
            ),
            arrival: AirportSide(
                airport: "HND",
                timeZone: timeZone,
                autoDataSupported: true
            ),
            status: FlightStatus(value: status),
            sync: SyncInfo(phase: .schedule),
            trackerCount: 1,
            isSample: true
        )
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, tz: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
