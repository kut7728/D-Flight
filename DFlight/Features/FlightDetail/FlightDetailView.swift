import SwiftUI

@Observable
final class FlightDetailViewModel {
    var tracked: TrackedFlight
    var departureAirport: Airport?
    var arrivalAirport: Airport?
    var now = Date()
    var errorMessage: String?

    init(tracked: TrackedFlight) {
        self.tracked = tracked
    }

    private var notifyGeneration = 0

    /// 서버 DB만 다시 읽는다. 외부 API는 부르지 않는다.
    func reload(_ repository: any FlightRepository) async {
        now = Date()
        if let fresh = try? await repository.trackedFlight(id: tracked.id) {
            tracked = fresh
        }
        departureAirport = try? await repository.airport(code: tracked.flight.departure.airport)
        arrivalAirport = try? await repository.airport(code: tracked.flight.arrival.airport)
    }

    func saveNotify(_ notify: FlightNotify, using repository: any FlightRepository) async throws {
        notifyGeneration += 1
        let generation = notifyGeneration
        let previous = tracked.notify
        tracked.notify = notify
        do {
            try await repository.updateFlightNotify(trackedId: tracked.id, notify)
        } catch {
            if generation == notifyGeneration {
                tracked.notify = previous
            }
            throw error
        }
        guard generation == notifyGeneration else { return }
        if let fresh = try? await repository.trackedFlight(id: tracked.id), generation == notifyGeneration {
            tracked = fresh
            now = Date()
        }
    }

    func follow(_ repository: any FlightRepository) async {
        let id = tracked.id
        for await feed in repository.observeFlights() {
            guard let fresh = feed.flights.first(where: { $0.id == id }) else { continue }
            tracked = fresh
            now = Date()
            if departureAirport?.code != fresh.flight.departure.airport {
                departureAirport = try? await repository.airport(code: fresh.flight.departure.airport)
            }
            if arrivalAirport?.code != fresh.flight.arrival.airport {
                arrivalAirport = try? await repository.airport(code: fresh.flight.arrival.airport)
            }
        }
    }

    func delete(_ repository: any FlightRepository) async throws {
        try await repository.untrack(id: tracked.id)
    }
}

struct FlightDetailView: View {
    private let trackedFlight: TrackedFlight
    private let readOnly: Bool

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: FlightDetailViewModel
    @State private var showReport = false
    @State private var confirmDelete = false
    @State private var mapLink: ShownMap?
    @State private var mapQuery: String?
    @State private var blockedURL: String?
    @State private var notificationsEnabled = true

    init(trackedFlight: TrackedFlight, readOnly: Bool) {
        self.trackedFlight = trackedFlight
        self.readOnly = readOnly
        _model = State(initialValue: FlightDetailViewModel(tracked: trackedFlight))
    }

    var body: some View {
        List {
            Section {
                FlightStatusBanner(
                    enteredFlightNumber: model.tracked.enteredFlightNumber,
                    flight: flight,
                    now: model.now,
                    isSample: model.tracked.isSample || flight.isSample,
                    departureDate: model.tracked.departureDate
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color(.systemGroupedBackground))
                .listRowSeparator(.hidden)
            }
            sideSection(
                title: Text("출발 · \(airportName(flight.departure, airport: model.departureAirport)) (\(flight.departure.airport))"),
                side: flight.departure,
                airport: model.departureAirport,
                showsCheckIn: true,
                showsBaggage: false,
                offset: 0
            )
            sideSection(
                title: Text("도착 · \(airportName(flight.arrival, airport: model.arrivalAirport)) (\(flight.arrival.airport))"),
                side: flight.arrival,
                airport: model.arrivalAirport,
                showsCheckIn: false,
                showsBaggage: true,
                offset: arrivalOffset
            )
            if hasSource {
                Section {
                    sourceFooter
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .detailListRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.tracked.enteredFlightNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareMessage) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("공유")
                if !readOnly {
                    Menu {
                        if !notificationsEnabled {
                            Button("앱 알림이 꺼져 있습니다 · 설정에서 켜기") {}
                                .disabled(true)
                        }
                        Toggle("변경 알림", isOn: notifyBinding(\.changes))
                        Toggle("출발 24시간 전", isOn: notifyBinding(\.dayBefore))
                        Toggle("출발 3시간 전", isOn: notifyBinding(\.leaveForAirport))
                        Toggle("탑승 임박", isOn: notifyBinding(\.boarding))
                    } label: {
                        Image(systemName: bellSymbol)
                    }
                    .accessibilityLabel("알림")
                }
                Menu {
                    if !readOnly {
                        Button("정보 제보·수정") { showReport = true }
                    }
                    Button("항공편 삭제", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("더보기")
            }
        }
        .refreshable {
            await model.reload(env.flights)
            await loadNotificationSetting()
        }
        .task(id: trackedFlight.id) {
            if model.tracked.id != trackedFlight.id {
                model.tracked = trackedFlight
            }
            await model.reload(env.flights)
            await loadNotificationSetting()
            await model.follow(env.flights)
        }
        .sheet(isPresented: $showReport, onDismiss: {
            Task { await model.reload(env.flights) }
        }) {
            ReportView(flight: model.tracked.flight)
        }
        .sheet(item: $mapLink) { link in
            NavigationStack {
                AirportMapView(url: link.url)
                    .navigationTitle("공항 안내도")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("닫기") { mapLink = nil }
                        }
                    }
            }
        }
        .confirmationDialog("지도에서 열기", isPresented: mapChooserPresented, titleVisibility: .visible) {
            Button("Apple 지도") { openMap(apple: true) }
            Button("Google 지도") { openMap(apple: false) }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("항공편 삭제", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { deleteFlight() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "오류",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .detailExternalAlert($blockedURL)
    }

    private var flight: Flight { model.tracked.flight }

    private var bellSymbol: String {
        let notify = model.tracked.notify
        let anyOn = notify.changes || notify.dayBefore || notify.leaveForAirport || notify.boarding
        return notificationsEnabled && anyOn ? "bell" : "bell.slash"
    }

    private var arrivalOffset: Int {
        guard
            let departure = flight.departure.estimatedAt.value ?? flight.departure.scheduledAt,
            let arrival = flight.arrival.estimatedAt.value ?? flight.arrival.scheduledAt
        else { return 0 }
        return dayOffset(
            departure: departure,
            depTZ: flight.departure.timeZone,
            arrival: arrival,
            arrTZ: flight.arrival.timeZone
        )
    }

    private var shareMessage: String {
        let names = [
            flight.departure.airport: airportName(flight.departure, airport: model.departureAirport),
            flight.arrival.airport: airportName(flight.arrival, airport: model.arrivalAirport)
        ]
        return shareText(for: model.tracked, airportName: { names[$0] ?? $0 }, locale: locale)
    }

    private var mapChooserPresented: Binding<Bool> {
        Binding(
            get: { mapQuery != nil },
            set: { if !$0 { mapQuery = nil } }
        )
    }

    private func sideSection(
        title: Text,
        side: AirportSide,
        airport: Airport?,
        showsCheckIn: Bool,
        showsBaggage: Bool,
        offset: Int
    ) -> some View {
        Section {
            DetailSideHeader(
                title: title,
                showsEdit: !readOnly,
                editLabel: showsCheckIn ? "출발 정보 제보" : "도착 정보 제보",
                onEdit: { showReport = true }
            )
            .detailListRow()
            DetailTimeRow(
                title: showsCheckIn ? "출발" : "도착",
                time: clock(side.estimatedAt.value ?? side.scheduledAt, timeZone: side.timeZone),
                previousTime: changedClock(side),
                offset: offset,
                missing: flight.origin == .pending ? LocalizedStringKey("정보 대기") : LocalizedStringKey("미정")
            )
            .detailListRow()
            infoRow("터미널", item: side.terminal, side: side, dimmed: flight.status.value == .cancelled)
            if showsCheckIn, let checkIn = side.checkInCounter {
                infoRow("체크인", item: checkIn, side: side, dimmed: false)
            } else if showsCheckIn {
                infoRow("체크인", item: InfoItem(), side: side, dimmed: false)
            }
            infoRow("게이트", item: side.gate, side: side, dimmed: flight.status.value == .cancelled)
            if showsBaggage, let belt = side.baggageBelt {
                infoRow("수하물", item: belt, side: side, dimmed: false)
            } else if showsBaggage {
                infoRow("수하물", item: InfoItem(), side: side, dimmed: false)
            }
            mapActions(side: side, airport: airport)
                .detailListRow()
        }
    }

    private func infoRow(_ title: LocalizedStringKey, item: InfoItem, side: AirportSide, dimmed: Bool) -> some View {
        InfoRow(
            title: title,
            state: infoState(item, side: side, flight: flight, now: model.now),
            awaitingLabel: flight.origin == .pending
                ? LocalizedStringKey("정보 대기")
                : LocalizedStringKey("출발 3일 전부터 표시"),
            dimmed: dimmed
        )
        .detailListRow()
    }

    private func mapActions(side: AirportSide, airport: Airport?) -> some View {
        HStack(spacing: 12) {
            if let url = airport?.mapURL {
                Button("공항 안내도") { mapLink = ShownMap(url: url) }
            }
            Spacer(minLength: 0)
            Button("지도에서 열기") { mapQuery = mapSearchQuery(side: side, airport: airport) }
        }
        .buttonStyle(.borderless)
        .font(.body)
        .foregroundStyle(Color.accentColor)
        .modifier(DetailRowHeight(height: 48))
    }

    private var hasSource: Bool {
        if let provider = flight.sync.provider, !provider.isEmpty { return true }
        if flight.origin == .airportData || flight.origin == .user { return true }
        return updatedClock != nil
    }

    @ViewBuilder
    private var sourceFooter: some View {
        if let provider = flight.sync.provider, !provider.isEmpty, let clock = updatedClock {
            Text("출처: \(providerLabel(provider)) · \(clock) 기준")
        } else if let provider = flight.sync.provider, !provider.isEmpty {
            Text("출처: \(providerLabel(provider))")
        } else if flight.origin == .user, let clock = updatedClock {
            Text("출처: 사용자 입력 · \(clock) 기준")
        } else if flight.origin == .user {
            Text("출처: 사용자 입력")
        } else if let clock = updatedClock {
            Text("출처: 공항 데이터 · \(clock) 기준")
        } else if flight.origin == .airportData {
            Text("출처: 공항 데이터")
        }
    }

    private var updatedClock: String? {
        let stamp = flight.sync.lastSuccessAt ?? flight.sync.lastFailureAt
        return clock(stamp, timeZone: flight.departure.timeZone)
    }

    private func providerLabel(_ provider: String) -> String {
        switch provider.lowercased() {
        case "icn", "iiac", "incheon", "incheon-airport":
            appString("인천국제공항공사", locale: locale)
        case "kac", "koreaairports", "korea-airports":
            appString("한국공항공사", locale: locale)
        default:
            provider
        }
    }

    private func airportName(_ side: AirportSide, airport: Airport?) -> String {
        airport?.name(for: locale) ?? side.airport
    }

    private func clock(_ date: Date?, timeZone: String) -> String? {
        guard let date else { return nil }
        return localTime(date, timeZone: timeZone, locale: locale)
    }

    private func changedClock(_ side: AirportSide) -> String? {
        guard delayMinutes(side) != nil, let scheduled = side.scheduledAt else { return nil }
        return localTime(scheduled, timeZone: side.timeZone, locale: locale)
    }

    private func mapSearchQuery(side: AirportSide, airport: Airport?) -> String {
        let name = airportName(side, airport: airport)
        let state = infoState(side.terminal, side: side, flight: flight, now: model.now)
        if let terminal = confirmedText(state) {
            return "\(name) \(side.airport) \(terminal)"
        }
        return "\(name) \(side.airport)"
    }

    private func confirmedText(_ state: InfoItemState) -> String? {
        switch state {
        case .confirmedAirport(let value, _, _), .confirmedUser(let value):
            value
        case .checkFailed(let lastValue, _):
            lastValue
        case .undetermined, .awaiting, .noAutoData:
            nil
        }
    }

    private func openMap(apple: Bool) {
        guard let mapQuery, let url = mapURL(apple: apple, query: mapQuery) else { return }
        self.mapQuery = nil
        ExternalLink.open(url, blocked: $blockedURL)
    }

    private func mapURL(apple: Bool, query: String) -> URL? {
        if apple {
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
            return components?.url
        }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query)
        ]
        return components?.url
    }

    private func notifyBinding(_ keyPath: WritableKeyPath<FlightNotify, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.tracked.notify[keyPath: keyPath] },
            set: { value in
                var next = model.tracked.notify
                next[keyPath: keyPath] = value
                let repository = env.flights
                let message = appString("저장하지 못했습니다", locale: locale)
                Task {
                    do {
                        try await model.saveNotify(next, using: repository)
                    } catch {
                        model.errorMessage = message
                    }
                }
            }
        )
    }

    private func loadNotificationSetting() async {
        if let settings = try? await env.account.settings() {
            notificationsEnabled = settings.notificationsEnabled
        }
    }

    private func deleteFlight() {
        Task {
            do {
                try await model.delete(env.flights)
                dismiss()
            } catch {
                model.errorMessage = appString("항공편을 삭제하지 못했습니다", locale: locale)
            }
        }
    }
}

private struct ShownMap: Identifiable {
    var id: String { url.absoluteString }
    var url: URL
}
