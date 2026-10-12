import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    static let notificationPromptKey = "didAskNotificationPermission"

    let flights: any FlightRepository
    let account: any AccountRepository
    let notices: any NoticeRepository
    let readNotices: NoticeReadStore

    private(set) var isSignedIn: Bool
    private(set) var needsNotificationPrompt = false
    private(set) var updateURL: URL?
    private(set) var didCheckVersion = false

    init(
        flights: any FlightRepository,
        account: any AccountRepository,
        notices: any NoticeRepository,
        readNotices: NoticeReadStore = NoticeReadStore()
    ) {
        let forwarder = AccountForwarder(base: account)
        self.flights = flights
        self.account = forwarder
        self.notices = notices
        self.readNotices = readNotices
        isSignedIn = account.currentProvider != nil
        forwarder.onSessionChange = { [weak self] in
            self?.noteSessionChange()
        }
    }

    func signIn(_ provider: LoginProvider) async throws {
        try await account.signIn(provider)
    }

    func signOut() async throws {
        try await account.signOut()
    }

    func deleteAccount() async throws {
        try await account.deleteAccount()
        readNotices.removeAll()
        UserDefaults.standard.set(false, forKey: Self.notificationPromptKey)
    }

    func finishNotificationPrompt() {
        UserDefaults.standard.set(true, forKey: Self.notificationPromptKey)
        needsNotificationPrompt = false
    }

    func checkMinimumVersion() async {
        let requirement = await notices.minimumVersion()
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if let requirement, isVersion(current, lowerThan: requirement.version) {
            updateURL = requirement.appStoreURL
        } else {
            updateURL = nil
        }
        didCheckVersion = true
    }

    private func noteSessionChange() {
        let signedIn = account.currentProvider != nil
        if signedIn && !isSignedIn && !UserDefaults.standard.bool(forKey: Self.notificationPromptKey) {
            needsNotificationPrompt = true
        }
        if !signedIn {
            needsNotificationPrompt = false
        }
        isSignedIn = signedIn
    }

    #if MOCK_DATA
    static func mock() -> AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        let flights = MockFlightRepository(includeTracked: !arguments.contains("-mockEmpty"))
        let account = MockAccountRepository(startsSignedIn: !arguments.contains("-mockSignedOut"))
        account.onDelete = { flights.removeAllTracked() }
        let notices = MockNoticeRepository(forceUpdate: arguments.contains("-mockForceUpdate"))
        return AppEnvironment(flights: flights, account: account, notices: notices)
    }
    #endif
}

@MainActor
private final class AccountForwarder: AccountRepository {
    private let base: any AccountRepository
    var onSessionChange: @MainActor () -> Void = {}

    init(base: any AccountRepository) {
        self.base = base
    }

    var currentProvider: LoginProvider? { base.currentProvider }

    func signIn(_ provider: LoginProvider) async throws {
        try await base.signIn(provider)
        onSessionChange()
    }

    func signOut() async throws {
        try await base.signOut()
        onSessionChange()
    }

    func deleteAccount() async throws {
        try await base.deleteAccount()
        onSessionChange()
    }

    func settings() async throws -> UserSettings {
        try await base.settings()
    }

    func updateSettings(_ settings: UserSettings) async throws {
        try await base.updateSettings(settings)
    }
}
