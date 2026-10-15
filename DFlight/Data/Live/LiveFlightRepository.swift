import Foundation
import Network

#if !MOCK_DATA
import FirebaseAuth
@preconcurrency import FirebaseFirestore

// ponytail: Firestore 스냅샷은 Sendable이 아니다. 콜백에서 딕셔너리로 복사한 뒤 메인에서만 읽는다.
private struct CopiedDocument: @unchecked Sendable {
    var id: String
    var data: [String: Any]
}

private struct CopiedQuery: @unchecked Sendable {
    var documents: [CopiedDocument]
    var fromCache: Bool
}

@MainActor
final class LiveFlightRepository: FlightRepository {
    private static let syncDefaultsKey = "dflight.lastServerSync"

    private var trackedDocs: [String: [String: Any]] = [:]
    private var flightDocs: [String: [String: Any]] = [:]
    private var flightSeen: Set<String> = []
    private var trackedListener: ListenerRegistration?
    private var flightListeners: [String: FlightListen] = [:]
    private var flightGeneration = 0
    private var listenGeneration = 0
    private var listeningUID: String?
    private var trackedReady = false
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var observations: [UUID: AsyncStream<FlightFeed>.Continuation] = [:]
    private var cancelledObservations: Set<UUID> = []
    private var isOffline = false
    private var lastServerSync: Date?
    private var lastFailed = false
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "dflight.network")

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.syncDefaultsKey)
        if stored > 0 {
            lastServerSync = Date(timeIntervalSince1970: stored)
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                self?.setOffline(offline)
            }
        }
        monitor.start(queue: monitorQueue)
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.handleAuth(uid: user?.uid)
            }
        }
    }

    func observeFlights() -> AsyncStream<FlightFeed> {
        AsyncStream { continuation in
            let id = UUID()
            Task { @MainActor in
                if self.cancelledObservations.remove(id) != nil {
                    continuation.finish()
                    return
                }
                self.observations[id] = continuation
                do {
                    try await self.prepare()
                    continuation.yield(self.feed(failed: false))
                } catch LiveRepositoryError.unauthenticated {
                    continuation.yield(self.feed(failed: false))
                } catch {
                    continuation.yield(self.feed(failed: true))
                }
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    if self.observations.removeValue(forKey: id) == nil {
                        self.cancelledObservations.insert(id)
                    }
                }
            }
        }
    }

    func trackedFlights() async throws -> [TrackedFlight] {
        try await prepare()
        return assemble()
    }

    func trackedFlight(id: String) async throws -> TrackedFlight? {
        guard Auth.auth().currentUser != nil else { throw LiveRepositoryError.unauthenticated }
        let snapshot = try await read {
            try await self.trackedCollection().document(id).getDocument(source: .server)
        }
        guard snapshot.exists, let raw = snapshot.data() else { return nil }
        let data = normalize(raw)
        guard let key = data["flightKey"] as? String else { return nil }
        let flightSnapshot = try await read {
            try await Firestore.firestore().collection("flights").document(key).getDocument(source: .server)
        }
        guard let flightRaw = flightSnapshot.data() else { return nil }
        let flightData = normalize(flightRaw)
        guard let flight = mapFlightDocument(key: key, data: flightData),
              let tracked = mapTrackedDocument(id: id, data: data, flight: flight) else { return nil }
        trackedDocs[id] = data
        flightDocs[key] = flightData
        flightSeen.insert(key)
        noteServerSync()
        publish(failed: false)
        return tracked
    }

    func refresh() async throws {
        try await prepare()
        let snapshot = try await read {
            try await self.trackedCollection().getDocuments(source: .server)
        }
        var nextTracked: [String: [String: Any]] = [:]
        var keys: [String] = []
        for document in snapshot.documents {
            let data = normalize(document.data())
            nextTracked[document.documentID] = data
            if let key = data["flightKey"] as? String {
                keys.append(key)
            }
        }
        let uniqueKeys = Array(Set(keys))
        var nextFlights: [String: [String: Any]] = [:]
        for key in uniqueKeys {
            let flightSnapshot = try await read {
                try await Firestore.firestore().collection("flights").document(key).getDocument(source: .server)
            }
            if let data = flightSnapshot.data() {
                nextFlights[key] = normalize(data)
            }
        }
        trackedDocs = nextTracked
        for key in flightDocs.keys where !uniqueKeys.contains(key) {
            flightDocs[key] = nil
            flightSeen.remove(key)
        }
        for (key, data) in nextFlights {
            flightDocs[key] = data
            flightSeen.insert(key)
        }
        syncFlightListeners(Set(uniqueKeys))
        noteServerSync()
        publish(failed: false)
    }

    func search(flightNumber: String, date: String) async throws -> FlightSearchResult {
        let raw = try await LiveBackend.call("searchFlight", data: [
            "flightNumber": normalizeFlightNumber(flightNumber),
            "departureDate": date,
        ])
        guard let data = raw as? [String: Any], let mapped = mapSearchResponse(data) else {
            throw LiveRepositoryError.unavailable
        }
        switch mapped {
        case .found(let flights):
            return .found(flights)
        case .notFound(let reason):
            return .notFound(reason)
        case .alreadyTracked(let key):
            if let existing = try await trackedMatching(flightKey: key) {
                return .alreadyTracked(existing)
            }
            throw LiveRepositoryError.alreadyExists
        }
    }

    func track(flight: Flight, enteredFlightNumber: String) async throws -> TrackedFlight {
        let raw = try await LiveBackend.call("trackFlight", data: [
            "flightKey": flight.key,
            "enteredFlightNumber": normalizeFlightNumber(enteredFlightNumber),
        ])
        guard let data = raw as? [String: Any], let id = data["trackedId"] as? String, !id.isEmpty else {
            throw LiveRepositoryError.unavailable
        }
        if let tracked = try await trackedFlight(id: id) { return tracked }
        throw LiveRepositoryError.notFound
    }

    func createManual(_ input: ManualFlightInput) async throws -> TrackedFlight {
        let raw = try await LiveBackend.call("createManualFlight", data: manualFlightPayload(input))
        guard let data = raw as? [String: Any], let id = data["trackedId"] as? String, !id.isEmpty else {
            throw LiveRepositoryError.unavailable
        }
        if let tracked = try await trackedFlight(id: id) { return tracked }
        throw LiveRepositoryError.notFound
    }

    func untrack(id: String) async throws {
        try await LiveBackend.call("untrackFlight", data: ["trackedId": id])
        trackedDocs[id] = nil
        publish(failed: false)
    }

    func updateFlightNotify(trackedId: String, _ notify: FlightNotify) async throws {
        try await LiveBackend.call("updateFlightNotify", data: [
            "trackedId": trackedId,
            "notify": [
                "changes": notify.changes,
                "dayBefore": notify.dayBefore,
                "leaveForAirport": notify.leaveForAirport,
                "boarding": notify.boarding,
            ],
        ])
    }

    func submitReport(flightKey: String, _ input: ReportInput) async throws {
        // ponytail: M5
        throw LiveRepositoryError.notYetAvailable
    }

    func airports(matching query: String) async throws -> [Airport] {
        AirportCatalog.search(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func airport(code: String) async throws -> Airport? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return AirportCatalog.airport(code: trimmed)
    }

    private func prepare() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw LiveRepositoryError.unauthenticated }
        if trackedListener == nil || listeningUID != uid {
            if let listeningUID, listeningUID != uid {
                trackedDocs.removeAll()
                flightDocs.removeAll()
                flightSeen.removeAll()
            }
            removeListeners()
            listeningUID = uid
            trackedReady = false
            attachTracked(uid)
        }
        if trackedReady { return }
        try await withCheckedThrowingContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }

    private func attachTracked(_ uid: String) {
        listenGeneration += 1
        let generation = listenGeneration
        let query = Firestore.firestore().collection("users").document(uid).collection("trackedFlights")
        trackedListener = query.addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            let copied = snapshot.map { query in
                CopiedQuery(
                    documents: query.documents.map { CopiedDocument(id: $0.documentID, data: $0.data()) },
                    fromCache: query.metadata.isFromCache
                )
            }
            let nsError = error as NSError?
            Task { @MainActor in
                guard let self, self.listenGeneration == generation else { return }
                self.handleTracked(copied, errorDomain: nsError?.domain, errorCode: error == nil ? nil : nsError?.code)
            }
        }
    }

    /// 등록은 최대 30편이라 항공편 문서는 건마다 구독한다.
    private func syncFlightListeners(_ keys: Set<String>) {
        for key in Array(flightListeners.keys) where !keys.contains(key) {
            flightListeners[key]?.registration.remove()
            flightListeners[key] = nil
            flightDocs[key] = nil
            flightSeen.remove(key)
        }
        for key in keys where flightListeners[key] == nil {
            flightGeneration += 1
            let generation = flightGeneration
            let registration = Firestore.firestore().collection("flights").document(key)
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                    let copied: CopiedDocument? = {
                        guard let snapshot, snapshot.exists, let data = snapshot.data() else { return nil }
                        return CopiedDocument(id: key, data: data)
                    }()
                    let exists = snapshot?.exists ?? false
                    let fromCache = snapshot?.metadata.isFromCache ?? false
                    let nsError = error as NSError?
                    Task { @MainActor in
                        self?.handleFlight(
                            key: key,
                            generation: generation,
                            document: copied,
                            exists: exists,
                            fromCache: fromCache,
                            errorCode: error == nil ? nil : nsError?.code
                        )
                    }
                }
            flightListeners[key] = FlightListen(generation: generation, registration: registration)
        }
    }

    private func handleTracked(_ snapshot: CopiedQuery?, errorDomain: String?, errorCode: Int?) {
        if let errorCode, let errorDomain {
            let mapped = mapBackendError(NSError(domain: errorDomain, code: errorCode))
            removeListeners()
            listeningUID = nil
            trackedReady = false
            resumeWaiters(mapped)
            publish(failed: true)
            return
        }
        guard let snapshot else { return }
        var next: [String: [String: Any]] = [:]
        for document in snapshot.documents {
            next[document.id] = normalize(document.data)
        }
        trackedDocs = next
        if !snapshot.fromCache {
            noteServerSync()
        }
        let keys = Set(next.values.compactMap { $0["flightKey"] as? String })
        syncFlightListeners(keys)
        flightSeen = flightSeen.intersection(keys)
        finishIfFlightsReady()
    }

    private func handleFlight(
        key: String,
        generation: Int,
        document: CopiedDocument?,
        exists: Bool,
        fromCache: Bool,
        errorCode: Int?
    ) {
        guard flightListeners[key]?.generation == generation else { return }
        flightSeen.insert(key)
        if errorCode == nil, exists, let document {
            flightDocs[key] = normalize(document.data)
            if !fromCache {
                noteServerSync()
            }
        } else if errorCode == nil, !exists {
            flightDocs[key] = nil
        }
        finishIfFlightsReady()
    }

    private func finishIfFlightsReady() {
        let keys = Set(trackedDocs.values.compactMap { $0["flightKey"] as? String })
        guard keys.isSubset(of: flightSeen) else { return }
        if !trackedReady {
            trackedReady = true
            resumeWaiters(nil)
        }
        publish(failed: false)
    }

    private func trackedMatching(flightKey: String) async throws -> TrackedFlight? {
        if let existing = assemble().first(where: { $0.flightKey == flightKey }) {
            return existing
        }
        let snapshot = try await read {
            try await self.trackedCollection()
                .whereField("flightKey", isEqualTo: flightKey)
                .limit(to: 1)
                .getDocuments()
        }
        guard let id = snapshot.documents.first?.documentID else { return nil }
        return try await trackedFlight(id: id)
    }

    private func assemble() -> [TrackedFlight] {
        var list: [TrackedFlight] = []
        for (id, data) in trackedDocs {
            guard let key = data["flightKey"] as? String,
                  let flightData = flightDocs[key],
                  let flight = mapFlightDocument(key: key, data: flightData),
                  let tracked = mapTrackedDocument(id: id, data: data, flight: flight) else { continue }
            list.append(tracked)
        }
        return list.sorted { $0.scheduledDepartureAt < $1.scheduledDepartureAt }
    }

    private func trackedCollection() throws -> CollectionReference {
        guard let uid = Auth.auth().currentUser?.uid else { throw LiveRepositoryError.unauthenticated }
        return Firestore.firestore().collection("users").document(uid).collection("trackedFlights")
    }

    private func normalize(_ data: [String: Any]) -> [String: Any] {
        data.mapValues(normalizeValue)
    }

    private func normalizeValue(_ value: Any) -> Any {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let child = value as? [String: Any] { return normalize(child) }
        if let list = value as? [Any] { return list.map(normalizeValue) }
        return value
    }

    private func noteServerSync() {
        let now = Date()
        lastServerSync = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.syncDefaultsKey)
    }

    private func setOffline(_ offline: Bool) {
        guard isOffline != offline else { return }
        isOffline = offline
        publish(failed: lastFailed)
    }

    private func handleAuth(uid: String?) {
        if uid == nil {
            guard listeningUID != nil || trackedListener != nil else { return }
            clearCachedFlights()
            removeListeners()
            listeningUID = nil
            trackedReady = false
            resumeWaiters(LiveRepositoryError.unauthenticated)
            publish(failed: false)
            return
        }
        guard let listeningUID, listeningUID != uid else { return }
        clearCachedFlights()
        removeListeners()
        self.listeningUID = nil
        trackedReady = false
        resumeWaiters(LiveRepositoryError.unauthenticated)
        publish(failed: false)
    }

    private func clearCachedFlights() {
        trackedDocs.removeAll()
        flightDocs.removeAll()
        flightSeen.removeAll()
    }

    private func removeListeners() {
        listenGeneration += 1
        trackedListener?.remove()
        trackedListener = nil
        for listen in flightListeners.values {
            listen.registration.remove()
        }
        flightListeners.removeAll()
    }

    private func resumeWaiters(_ error: Error?) {
        let pending = readyWaiters
        readyWaiters.removeAll()
        for waiter in pending {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume()
            }
        }
    }

    private func feed(failed: Bool) -> FlightFeed {
        FlightFeed(flights: assemble(), isOffline: isOffline, lastServerSync: lastServerSync, failed: failed)
    }

    private func publish(failed: Bool) {
        lastFailed = failed
        let snapshot = feed(failed: failed)
        for continuation in observations.values {
            continuation.yield(snapshot)
        }
    }

    private func read<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as LiveRepositoryError {
            throw error
        } catch {
            throw mapBackendError(error)
        }
    }
}

private struct FlightListen {
    var generation: Int
    var registration: ListenerRegistration
}
#endif
