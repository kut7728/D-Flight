import Foundation
import Testing
@testable import DFlight

@Suite("항공편 문서·검색 매핑")
struct FlightMappingTests {
    @Test("Firestore 문서를 도메인 모델로 바꾼다")
    func flightDocument() {
        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = Date(timeIntervalSince1970: 1_700_000_100)
        let estimated = scheduled.addingTimeInterval(600)
        let data: [String: Any] = [
            "operating": ["airline": "OZ", "flightNumber": "OZ1075"],
            "searchKeys": ["OZ1075_2026-11-01", "NH5701_2026-11-01"],
            "origin": "airport_data",
            "departure": [
                "airport": "HND",
                "timeZone": "Asia/Tokyo",
                "scheduledAt": scheduled,
                "estimatedAt": [
                    "value": estimated,
                    "source": "airport_data",
                    "updatedAt": updated,
                ],
                "terminal": [
                    "value": "T2",
                    "source": "airport_data",
                    "updatedAt": updated,
                    "previousValue": "T1",
                ],
                "gate": ["value": NSNull(), "source": NSNull()],
                "checkInCounter": ["value": "A", "source": "user", "updatedAt": updated],
                "autoDataSupported": true,
            ],
            "arrival": [
                "airport": "ICN",
                "timeZone": "Asia/Seoul",
                "scheduledAt": ["seconds": 1_700_003_000, "nanoseconds": 0],
                "baggageBelt": ["value": "3", "source": "airport_data", "updatedAt": updated],
                "autoDataSupported": true,
            ],
            "status": ["value": "delayed", "source": "airport_data", "updatedAt": updated],
            "sync": [
                "phase": "frequent",
                "nextPollAt": updated,
                "lastSuccessAt": updated,
                "consecutiveFailures": 2,
                "provider": "iiac",
            ],
            "trackerCount": 3,
        ]

        let flight = mapFlightDocument(key: "OZ1075_2026-11-01_HND", data: data)
        #expect(flight?.key == "OZ1075_2026-11-01_HND")
        #expect(flight?.isSample == false)
        #expect(flight?.operating == OperatingFlight(airline: "OZ", flightNumber: "OZ1075"))
        #expect(flight?.searchKeys == ["OZ1075_2026-11-01", "NH5701_2026-11-01"])
        #expect(flight?.origin == .airportData)
        #expect(flight?.departure.terminal == InfoItem(
            value: "T2",
            source: .airportData,
            updatedAt: updated,
            previousValue: "T1"
        ))
        #expect(flight?.departure.gate.value == nil)
        #expect(flight?.departure.estimatedAt == TimeItem(value: estimated, source: .airportData, updatedAt: updated))
        #expect(flight?.departure.checkInCounter == InfoItem(value: "A", source: .user, updatedAt: updated))
        #expect(flight?.departure.baggageBelt == nil)
        #expect(flight?.arrival.scheduledAt == Date(timeIntervalSince1970: 1_700_003_000))
        #expect(flight?.arrival.baggageBelt?.value == "3")
        #expect(flight?.arrival.checkInCounter == nil)
        #expect(flight?.status == FlightStatus(value: .delayed, source: .airportData, updatedAt: updated))
        #expect(flight?.sync == SyncInfo(
            phase: .frequent,
            nextPollAt: updated,
            lastSuccessAt: updated,
            consecutiveFailures: 2,
            provider: "iiac"
        ))
        #expect(flight?.trackerCount == 3)

        let trackedData: [String: Any] = [
            "flightKey": "OZ1075_2026-11-01_HND",
            "enteredFlightNumber": "NH5701",
            "departureDate": "2026-11-01",
            "scheduledDepartureAt": scheduled,
            "createdAt": updated,
            "notify": ["changes": false],
        ]
        let tracked = flight.flatMap { mapTrackedDocument(id: "t1", data: trackedData, flight: $0) }
        #expect(tracked?.isSample == false)
        #expect(tracked?.enteredFlightNumber == "NH5701")
        #expect(tracked?.notify == FlightNotify(changes: false, dayBefore: true, leaveForAirport: true, boarding: true))
        #expect(tracked?.flight.isSample == false)
    }

    @Test("검색 후보의 dataLevel·이미 등록·못 찾음 이유")
    func searchResponse() {
        let schedule = candidate(level: "schedule", key: "OZ1075_2026-11-01_HND", tracked: false)
        let user = candidate(level: "user", key: "MM101_2026-11-01_NRT", tracked: false)
        let realtime = candidate(level: "realtime", key: "KE001_2026-11-01_ICN", tracked: true)
        let mixed = mapSearchResponse(["candidates": [schedule, user, realtime], "notFoundReason": NSNull()])
        guard case .found(let flights) = mixed else {
            Issue.record("찾은 결과가 아님")
            return
        }
        #expect(flights.map(\.key) == ["OZ1075_2026-11-01_HND", "MM101_2026-11-01_NRT"])
        #expect(flights[0].origin == .airportData)
        #expect(flights[0].isSample == false)
        #expect(flights[0].departure.autoDataSupported)
        #expect(flights[0].departure.scheduledAt == iso("2026-11-01T01:00:00Z"))
        #expect(flights[0].arrival.scheduledAt == iso("2026-11-01T03:30:00Z"))
        #expect(flights[1].origin == .user)
        #expect(flights[1].departure.autoDataSupported == false)

        let onlyTracked = mapSearchResponse(["candidates": [realtime]])
        #expect(onlyTracked == .alreadyTracked(flightKey: "KE001_2026-11-01_ICN"))

        #expect(mapSearchResponse([
            "candidates": [],
            "notFoundReason": "no_korean_airport_data",
        ]) == .notFound(.noKoreanAirportData))
        #expect(mapSearchResponse([
            "candidates": [],
            "notFoundReason": "not_in_schedule",
        ]) == .notFound(.notInSchedule))
        #expect(mapSearchResponse([
            "candidates": [],
            "notFoundReason": "outside_schedule_season",
        ]) == .notFound(.outsideScheduleSeason))
        #expect(mapSearchResponse(["candidates": [], "notFoundReason": NSNull()]) == .notFound(nil))
        #expect(mapSearchResponse(["candidates": [["flightKey": "bad"]]]) == nil)
    }

    @Test("직접 입력은 api-spec 필드로 바꾼다")
    func manualPayload() {
        let input = ManualFlightInput(
            flightNumber: "mm101",
            departureDate: "2026-11-01",
            depAirport: "nrt",
            arrAirport: "kix",
            scheduledDepartureLocal: DateComponents(hour: 8, minute: 30),
            scheduledArrivalLocal: DateComponents(hour: 10, minute: 5),
            arrivalDayOffset: 0,
            terminal: "T3",
            checkInCounter: "A1"
        )
        let payload = manualFlightPayload(input)
        #expect(payload["flightNumber"] as? String == "MM101")
        #expect(payload["departureAirport"] as? String == "NRT")
        #expect(payload["arrivalAirport"] as? String == "KIX")
        #expect(payload["departureTime"] as? String == "08:30")
        #expect(payload["arrivalTime"] as? String == "10:05")
        #expect(payload["arrivalDayOffset"] as? Int == 0)
        let fields = payload["fields"] as? [String: String]
        #expect(fields == ["departure.terminal": "T3", "departure.checkInCounter": "A1"])

        let departureOnly = manualFlightPayload(ManualFlightInput(
            flightNumber: "XX1",
            departureDate: "2026-11-01",
            depAirport: "ICN",
            arrAirport: "HND",
            scheduledDepartureLocal: DateComponents(hour: 9, minute: 0)
        ))
        #expect(departureOnly["arrivalTime"] == nil)
        #expect(departureOnly["arrivalDayOffset"] == nil)
        #expect(departureOnly["fields"] == nil)
        #expect(departureOnly["awaitAutoData"] == nil)
    }

    @Test("대기 등록은 origin pending이고 출발 시각을 생략할 수 있다")
    func pendingMapping() {
        let data: [String: Any] = [
            "operating": ["airline": "XX", "flightNumber": "XX800"],
            "origin": "pending",
            "departure": ["airport": "ICN", "timeZone": "Asia/Seoul", "autoDataSupported": true],
            "arrival": ["airport": "HND", "timeZone": "Asia/Tokyo", "autoDataSupported": false],
            "status": ["value": "scheduled"],
            "sync": ["phase": "schedule"],
        ]
        let flight = mapFlightDocument(key: "XX800_2026-11-01_ICN", data: data)
        #expect(flight?.origin == .pending)
        #expect(flight?.departure.scheduledAt == nil)
        #expect(flight?.isSample == false)

        let payload = manualFlightPayload(ManualFlightInput(
            flightNumber: "xx800",
            departureDate: "2026-11-01",
            depAirport: "icn",
            arrAirport: "hnd",
            awaitAutoData: true
        ))
        #expect(payload["awaitAutoData"] as? Bool == true)
        #expect(payload["departureTime"] == nil)
        #expect(payload["departureAirport"] as? String == "ICN")
        #expect(payload["departureDate"] as? String == "2026-11-01")
        #expect(payload["fields"] == nil)
    }

    private func candidate(level: String, key: String, tracked: Bool) -> [String: Any] {
        [
            "flightKey": key,
            "operating": ["airline": "OZ", "flightNumber": "OZ1075"],
            "departure": ["airport": "HND", "scheduledAt": "2026-11-01T01:00:00Z", "timeZone": "Asia/Tokyo"],
            "arrival": ["airport": "ICN", "scheduledAt": "2026-11-01T03:30:00Z", "timeZone": "Asia/Seoul"],
            "dataLevel": level,
            "alreadyTracked": tracked,
        ]
    }

    private func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? .distantPast
    }
}
