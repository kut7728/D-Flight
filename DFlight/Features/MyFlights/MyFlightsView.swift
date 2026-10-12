import SwiftUI
import UIKit
import UserNotifications

struct MyFlightsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        MyFlightsContent(repository: env.flights)
    }
}

@MainActor
@Observable
private final class MyFlightsModel {
    private let repository: any FlightRepository

    private(set) var upcoming: [TrackedFlight] = []
    private(set) var airports: [String: Airport] = [:]
    private(set) var hasLoaded = false
    private(set) var loadFailed = false
    private(set) var notificationsDenied = false
    private(set) var now = Date()

    init(repository: any FlightRepository) {
        self.repository = repository
    }

    func reload() async {
        now = Date()
        do {
            let all = try await repository.trackedFlights()
            upcoming = partitionFlights(all, now: now).upcoming
            await cacheAirports()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        hasLoaded = true
    }

    func refresh() async {
        var failed = false
        do {
            try await repository.refresh()
        } catch {
            failed = true
        }
        await reload()
        if failed { loadFailed = true }
    }

    func untrack(id: String) async {
        do {
            try await repository.untrack(id: id)
            await reload()
        } catch {
            loadFailed = true
        }
    }

    func updateNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    func name(for code: String, locale: Locale) -> String {
        airports[code]?.name(for: locale) ?? code
    }

    private func cacheAirports() async {
        let codes = Set(upcoming.flatMap { [$0.flight.departure.airport, $0.flight.arrival.airport] })
        var loaded = airports
        for code in codes where loaded[code] == nil {
            if let airport = try? await repository.airport(code: code) {
                loaded[code] = airport
            }
        }
        airports = loaded
    }
}

private struct MyFlightsContent: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: MyFlightsModel
    @State private var path = NavigationPath()
    @State private var showRegister = false
    @State private var pendingDelete: TrackedFlight?
    @State private var blockedURL: String?

    init(repository: any FlightRepository) {
        _model = State(initialValue: MyFlightsModel(repository: repository))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.loadFailed {
                    Section {
                        Text("지금은 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.notificationsDenied {
                    Section {
                        Button(action: openSettings) {
                            Text("알림이 꺼져 있어 변경을 알려 드릴 수 없습니다 · 설정 열기")
                                .font(.footnote)
                                .foregroundStyle(Color("AccentColor"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let nearest = model.upcoming.first {
                    Section {
                        BoardingPassCard(
                            tracked: nearest,
                            departureName: model.name(for: nearest.flight.departure.airport, locale: locale),
                            arrivalName: model.name(for: nearest.flight.arrival.airport, locale: locale),
                            now: model.now
                        ) {
                            path.append(nearest)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("삭제", role: .destructive) { pendingDelete = nearest }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color(.systemGroupedBackground))
                        .listRowSeparator(.hidden)
                    }
                    let rest = Array(model.upcoming.dropFirst())
                    if !rest.isEmpty {
                        Section("다가오는 항공편") {
                            ForEach(rest) { flight in
                                NavigationLink(value: flight) {
                                    UpcomingFlightRow(flight: flight, now: model.now)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("삭제", role: .destructive) { pendingDelete = flight }
                                }
                            }
                        }
                    }
                } else if model.hasLoaded {
                    Section {
                        ContentUnavailableView {
                            Text("등록된 항공편이 없습니다")
                        } actions: {
                            Button("항공편 등록") { showRegister = true }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("내 항공편")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: TrackedFlight.self) { flight in
                FlightDetailView(trackedFlight: flight, readOnly: false)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRegister = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("항공편 등록")
                }
            }
            .overlay {
                if !model.hasLoaded {
                    ProgressView()
                }
            }
            .refreshable {
                await model.refresh()
            }
            .confirmationDialog(
                "이 항공편을 삭제할까요?",
                isPresented: deleteShown,
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) {
                    let id = pendingDelete?.id
                    pendingDelete = nil
                    guard let id else { return }
                    Task { await model.untrack(id: id) }
                }
                Button("취소", role: .cancel) {}
            }
            .sheet(isPresented: $showRegister, onDismiss: {
                Task { await model.reload() }
            }) {
                RegisterFlightView()
                    .environment(env)
            }
            .detailExternalAlert($blockedURL)
        }
        .task {
            await model.reload()
            await model.updateNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.updateNotifications() }
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        ExternalLink.open(url, blocked: $blockedURL)
    }
}

private struct UpcomingFlightRow: View {
    var flight: TrackedFlight
    var now: Date

    var body: some View {
        HStack(spacing: 12) {
            DDayLabel(flight: flight.flight, now: now)
                .font(.headline.bold())
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: flight.enteredFlightNumber)
                    .font(.body.bold())
                    .monospacedDigit()
                Text(verbatim: "\(flight.flight.departure.airport) → \(flight.flight.arrival.airport)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if showsSample(flight) {
                SampleDataChip()
            }
        }
    }
}
