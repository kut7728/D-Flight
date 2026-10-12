import Foundation

nonisolated enum DataSource: String, Codable, Hashable, Sendable {
    case airportData = "airport_data"
    case user
}

nonisolated struct InfoItem: Codable, Hashable, Sendable {
    var value: String? = nil
    var source: DataSource? = nil
    var updatedAt: Date? = nil
    /// 마지막으로 공항 데이터가 바꾸기 직전의 값. 24시간 `변경` 칩용.
    var previousValue: String? = nil
}

nonisolated struct TimeItem: Codable, Hashable, Sendable {
    var value: Date? = nil
    var source: DataSource? = nil
    var updatedAt: Date? = nil
}

nonisolated enum FlightStatusValue: String, Codable, Hashable, Sendable {
    case scheduled
    case delayed
    case cancelled
    case departed
    case arrived
    case unknown
}

nonisolated struct FlightStatus: Codable, Hashable, Sendable {
    var value: FlightStatusValue
    var source: DataSource? = nil
    var updatedAt: Date? = nil
}

nonisolated struct AirportSide: Codable, Hashable, Sendable {
    var airport: String
    var timeZone: String
    var scheduledAt: Date? = nil
    var estimatedAt: TimeItem = TimeItem()
    var terminal: InfoItem = InfoItem()
    var gate: InfoItem = InfoItem()
    var checkInCounter: InfoItem? = nil
    var baggageBelt: InfoItem? = nil
    var autoDataSupported: Bool
}

nonisolated enum SyncPhase: String, Codable, Hashable, Sendable {
    case schedule
    case hourly
    case frequent
    case done
}

nonisolated struct SyncInfo: Codable, Hashable, Sendable {
    var phase: SyncPhase
    var nextPollAt: Date? = nil
    var lastSuccessAt: Date? = nil
    var lastFailureAt: Date? = nil
    var consecutiveFailures: Int = 0
    var provider: String? = nil
}

nonisolated struct OperatingFlight: Codable, Hashable, Sendable {
    var airline: String
    var flightNumber: String
}

nonisolated enum FlightOrigin: String, Codable, Hashable, Sendable {
    case airportData = "airport_data"
    case user
}

nonisolated struct Flight: Identifiable, Codable, Hashable, Sendable {
    var key: String
    var id: String { key }
    var operating: OperatingFlight
    var searchKeys: [String]
    var origin: FlightOrigin
    var departure: AirportSide
    var arrival: AirportSide
    var status: FlightStatus
    var sync: SyncInfo
    var trackerCount: Int
    var isSample: Bool
}

nonisolated struct FlightNotify: Codable, Hashable, Sendable {
    var changes = true
    var dayBefore = true
    var leaveForAirport = true
    var boarding = true
}

/// 임박 알림 시점. 저장하지 않는다.
nonisolated enum ImminentTiming {
    static let dayBefore: TimeInterval = 24 * 3600
    static let leaveForAirport: TimeInterval = 3 * 3600
    static let boarding: TimeInterval = 40 * 60
}

nonisolated struct TrackedFlight: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var flightKey: String
    var enteredFlightNumber: String
    /// 출발 공항 현지 날짜 `yyyy-MM-dd`.
    var departureDate: String
    var scheduledDepartureAt: Date
    var createdAt: Date
    var isSample: Bool
    var notify: FlightNotify = FlightNotify()
    /// 화면에서 바로 쓰도록 붙여 둔 항공편.
    var flight: Flight
}

nonisolated struct Airport: Codable, Hashable, Sendable {
    var code: String
    var nameKo: String
    var nameJa: String
    var nameEn: String
    var timeZone: String
    var terminals: [String]
    var mapURL: URL?

    func name(for locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "ko": nameKo
        case "ja": nameJa
        default: nameEn
        }
    }
}

nonisolated struct Notice: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: [String: String]
    var body: [String: String]
    var important: Bool
    var publishedAt: Date
    var expiresAt: Date?
}

nonisolated enum AppLanguage: String, Codable, Hashable, Sendable {
    case system
    case ko
    case ja
    case en
}

nonisolated struct UserSettings: Codable, Hashable, Sendable {
    var language: AppLanguage
    var notificationsEnabled: Bool = true
    var liveActivityEnabled: Bool

    static let `default` = UserSettings(
        language: .system,
        notificationsEnabled: true,
        liveActivityEnabled: true
    )
}

nonisolated enum LoginProvider: String, Codable, Hashable, Sendable {
    case apple
    case google
}

nonisolated enum FlightSearchResult: Hashable, Sendable {
    /// 구간이 1개 이상. 사용자가 공유한 항공편이 섞일 수 있다.
    case found([Flight])
    case notFound
    case alreadyTracked(TrackedFlight)
}

nonisolated struct ManualFlightInput: Codable, Hashable, Sendable {
    var flightNumber: String
    var departureDate: String
    var depAirport: String
    var arrAirport: String
    var scheduledDepartureLocal: DateComponents
    var scheduledArrivalLocal: DateComponents? = nil
    var arrivalDayOffset: Int = 0
    var terminal: String? = nil
    var gate: String? = nil
    var checkInCounter: String? = nil
    var baggageBelt: String? = nil
}

/// `nil`은 그대로 두고, `.some(nil)`은 값을 지운다.
nonisolated struct ReportInput: Hashable, Sendable {
    nonisolated enum Side: String, Codable, Hashable, Sendable {
        case departure
        case arrival
    }

    var side: Side
    var terminal: String?? = nil
    var gate: String?? = nil
    var checkInCounter: String?? = nil
    var baggageBelt: String?? = nil
}
