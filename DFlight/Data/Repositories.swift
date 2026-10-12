import Foundation

@MainActor
protocol FlightRepository: AnyObject {
    func trackedFlights() async throws -> [TrackedFlight]
    func refresh() async throws
    /// 네트워크 실패는 던진다. 못 찾음은 `notFound`.
    func search(flightNumber: String, date: String) async throws -> FlightSearchResult
    func track(flight: Flight, enteredFlightNumber: String) async throws -> TrackedFlight
    func createManual(_ input: ManualFlightInput) async throws -> TrackedFlight
    func untrack(id: String) async throws
    func updateFlightNotify(trackedId: String, _ notify: FlightNotify) async throws
    /// 서버 DB에 있는 등록 항공편 하나를 다시 읽는다. 외부 API는 부르지 않는다.
    func trackedFlight(id: String) async throws -> TrackedFlight?
    func submitReport(flightKey: String, _ input: ReportInput) async throws
    func airports(matching query: String) async throws -> [Airport]
    func airport(code: String) async throws -> Airport?
}

@MainActor
protocol AccountRepository: AnyObject {
    var currentProvider: LoginProvider? { get }
    func signIn(_ provider: LoginProvider) async throws
    func signOut() async throws
    func deleteAccount() async throws
    func settings() async throws -> UserSettings
    func updateSettings(_ settings: UserSettings) async throws
}

@MainActor
protocol NoticeRepository: AnyObject {
    func notices() async throws -> [Notice]
    /// 실패하면 nil. 앱을 막지 않는다.
    func minimumVersion() async -> (version: String, appStoreURL: URL)?
}
