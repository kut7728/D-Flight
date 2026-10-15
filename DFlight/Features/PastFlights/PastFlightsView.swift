import SwiftUI

struct PastFlightsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        PastFlightsContent(repository: env.flights)
    }
}

@MainActor
@Observable
private final class PastFlightsModel {
    private let repository: any FlightRepository

    private(set) var past: [TrackedFlight] = []
    private(set) var hasLoaded = false
    private(set) var loadFailed = false

    init(repository: any FlightRepository) {
        self.repository = repository
    }

    func follow() async {
        for await feed in repository.observeFlights() {
            past = partitionFlights(feed.flights, now: Date()).past
            loadFailed = feed.failed
            hasLoaded = true
        }
    }

    func reload() async {
        do {
            let all = try await repository.trackedFlights()
            past = partitionFlights(all, now: Date()).past
            loadFailed = false
        } catch {
            loadFailed = true
        }
        hasLoaded = true
    }

    func untrack(id: String) async {
        do {
            try await repository.untrack(id: id)
            await reload()
        } catch {
            loadFailed = true
        }
    }
}

private struct PastFlightsContent: View {
    @Environment(\.locale) private var locale
    @State private var model: PastFlightsModel
    @State private var pendingDelete: TrackedFlight?

    init(repository: any FlightRepository) {
        _model = State(initialValue: PastFlightsModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            List {
                if model.loadFailed {
                    Section {
                        Text("지금은 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.hasLoaded && model.past.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Text("지난 항공편이 없습니다")
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(model.past) { flight in
                        NavigationLink {
                            FlightDetailView(trackedFlight: flight, readOnly: true)
                        } label: {
                            PastFlightRow(flight: flight)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("삭제", role: .destructive) { pendingDelete = flight }
                        }
                    }
                }
            }
            .navigationTitle("지난 항공편")
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                if !model.hasLoaded {
                    ProgressView()
                }
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
        }
        .task {
            await model.follow()
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

private struct PastFlightRow: View {
    var flight: TrackedFlight
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: flight.enteredFlightNumber)
                    .font(.body.bold())
                    .monospacedDigit()
                Text(verbatim: "\(flight.flight.departure.airport) → \(flight.flight.arrival.airport)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if showsSample(flight) {
                    SampleDataChip()
                }
            }
            Text(verbatim: civilDate(from: flight.departureDate, locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
