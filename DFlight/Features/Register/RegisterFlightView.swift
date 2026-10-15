import SwiftUI

struct RegisterFlightView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        RegisterFlightContent(repository: env.flights)
    }
}

private enum SearchOutcome: Equatable {
    case none
    case notFound(NotFoundReason?)
    case failed(FlightUserMessage)
    case alreadyTracked(TrackedFlight?)
    case found
}

@MainActor
@Observable
private final class RegisterFlightModel {
    private let repository: any FlightRepository

    var flightNumber = ""
    var departureDate = Date()
    private(set) var outcome: SearchOutcome = .none
    private(set) var results: [Flight] = []
    private(set) var airports: [String: Airport] = [:]
    var selectedKey: String?
    private(set) var isSearching = false
    private(set) var isSubmitting = false
    private(set) var notice: FlightUserMessage?

    init(repository: any FlightRepository) {
        self.repository = repository
    }

    var canSearch: Bool {
        isValidFlightNumber(flightNumber) && !isSearching
    }

    var departureDateString: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: departureDate)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var dateRange: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return start...end
    }

    var selectedFlight: Flight? {
        guard let selectedKey else { return nil }
        return results.first { $0.key == selectedKey }
    }

    func normalizeNumber() {
        let normalized = normalizeFlightNumber(flightNumber)
        if flightNumber != normalized {
            flightNumber = normalized
        }
    }

    func clearResults() {
        outcome = .none
        results = []
        selectedKey = nil
        notice = nil
    }

    func search() async {
        normalizeNumber()
        guard isValidFlightNumber(flightNumber) else { return }
        isSearching = true
        notice = nil
        defer { isSearching = false }
        do {
            let result = try await repository.search(flightNumber: flightNumber, date: departureDateString)
            switch result {
            case .found(let flights):
                if flights.isEmpty {
                    outcome = .notFound(nil)
                    results = []
                    selectedKey = nil
                } else {
                    outcome = .found
                    results = flights
                    selectedKey = flights.count == 1 ? flights[0].key : nil
                    await cacheAirports(in: flights)
                }
            case .notFound(let reason):
                outcome = .notFound(reason)
                results = []
                selectedKey = nil
            case .alreadyTracked(let tracked):
                outcome = .alreadyTracked(tracked)
                results = []
                selectedKey = nil
            }
        } catch {
            if let live = error as? LiveRepositoryError, live == .alreadyExists {
                outcome = .alreadyTracked(nil)
            } else {
                outcome = .failed(flightUserMessage(for: error))
            }
            results = []
            selectedKey = nil
        }
    }

    func track() async -> Bool {
        guard let flight = selectedFlight else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await repository.track(flight: flight, enteredFlightNumber: normalizeFlightNumber(flightNumber))
            notice = nil
            return true
        } catch {
            if let live = error as? LiveRepositoryError, live == .alreadyExists {
                let existing = try? await repository.trackedFlights().first { $0.flightKey == flight.key }
                outcome = .alreadyTracked(existing)
                notice = nil
                return false
            }
            notice = flightUserMessage(for: error, notFoundIsSearchAgain: true)
            return false
        }
    }

    func name(for code: String, locale: Locale) -> String {
        if let airport = airports[code] {
            return "\(airport.name(for: locale)) (\(code))"
        }
        return code
    }

    private func cacheAirports(in flights: [Flight]) async {
        let codes = Set(flights.flatMap { [$0.departure.airport, $0.arrival.airport] })
        var loaded = airports
        for code in codes where loaded[code] == nil {
            if let airport = try? await repository.airport(code: code) {
                loaded[code] = airport
            }
        }
        airports = loaded
    }
}

private struct RegisterFlightContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: RegisterFlightModel

    init(repository: any FlightRepository) {
        _model = State(initialValue: RegisterFlightModel(repository: repository))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("편명", text: $model.flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.search)
                        .onSubmit { Task { await model.search() } }
                    DatePicker(
                        "출발 날짜",
                        selection: $model.departureDate,
                        in: model.dateRange,
                        displayedComponents: .date
                    )
                } footer: {
                    Text("출발 공항 현지 날짜 기준. 시차 때문에 이 기기의 날짜와 다를 수 있습니다.")
                }
                Section {
                    Button {
                        Task { await model.search() }
                    } label: {
                        if model.isSearching {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("찾기")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!model.canSearch)
                }
                result
            }
            .navigationTitle("항공편 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .onChange(of: model.flightNumber) { _, newValue in
                let normalized = normalizeFlightNumber(newValue)
                if normalized != newValue {
                    model.flightNumber = normalized
                    return
                }
                model.clearResults()
            }
            .onChange(of: model.departureDate) { old, new in
                guard !Calendar.current.isDate(old, inSameDayAs: new) else { return }
                model.clearResults()
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        if let notice = model.notice {
            Section {
                failureText(notice)
            }
        }
        switch model.outcome {
        case .none:
            EmptyView()
        case .failed(let message):
            Section {
                failureText(message)
            }
        case .notFound(let reason):
            Section {
                if reason != .outsideScheduleSeason {
                    Text("자동 정보를 찾지 못했습니다")
                }
                notFoundCopy(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if reason == .outsideScheduleSeason {
                    NavigationLink("대기 등록") {
                        ManualFlightEntryView(
                            flightNumber: model.flightNumber,
                            departureDate: model.departureDateString,
                            pending: true,
                            onRegistered: { dismiss() }
                        )
                    }
                } else {
                    NavigationLink("직접 입력해서 등록") {
                        ManualFlightEntryView(
                            flightNumber: model.flightNumber,
                            departureDate: model.departureDateString,
                            onRegistered: { dismiss() }
                        )
                    }
                }
            }
        case .alreadyTracked(let tracked):
            Section {
                Text("이미 등록된 항공편입니다")
                if let tracked {
                    NavigationLink("보기") {
                        FlightDetailView(trackedFlight: tracked, readOnly: false)
                    }
                }
            }
        case .found:
            if model.results.count > 1 {
                Section("구간을 선택해 주세요") {
                    ForEach(model.results) { flight in
                        Button {
                            model.selectedKey = flight.key
                        } label: {
                            HStack {
                                CandidateLine(flight: flight, model: model)
                                Spacer()
                                if model.selectedKey == flight.key {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color("AccentColor"))
                                }
                            }
                        }
                    }
                }
            }
            if let flight = model.selectedFlight {
                Section {
                    CandidateSummary(flight: flight, entered: model.flightNumber, model: model)
                    Button {
                        Task {
                            if await model.track() { dismiss() }
                        }
                    } label: {
                        if model.isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("등록")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(model.isSubmitting)
                }
            }
        }
    }
}

private func failureText(_ message: FlightUserMessage) -> some View {
    Group {
        switch message {
        case .unavailable:
            Text("지금은 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.")
        case .retrySoon:
            Text("잠시 후 다시 시도해 주세요")
        case .searchAgain:
            Text("다시 검색해 주세요")
        case .invalidInput:
            Text("입력 내용을 확인해 주세요")
        }
    }
    .foregroundStyle(.secondary)
}

@ViewBuilder
private func notFoundCopy(_ reason: NotFoundReason?) -> some View {
    switch reason {
    case .noKoreanAirportData:
        Text("한국 공항이 포함되지 않은 항공편은 자동 정보를 지원하지 않습니다.")
    case .notInSchedule:
        Text("편명이나 날짜가 잘못됐을 수 있습니다.")
    case .outsideScheduleSeason:
        Text("아직 공개된 시간표가 없습니다. 출발 3일 전부터 자동으로 확인합니다.")
    case nil:
        Text("한국 공항이 포함되지 않은 항공편은 자동 정보를 지원하지 않습니다.")
        Text("편명이나 날짜가 잘못됐을 수 있습니다.")
    }
}

private struct CandidateLine: View {
    var flight: Flight
    var model: RegisterFlightModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: "\(flight.departure.airport) → \(flight.arrival.airport)")
                    .font(.body.bold())
                    .monospacedDigit()
                if flight.isSample {
                    SampleDataChip()
                }
                if flight.origin == .user {
                    Chip(style: .userReport)
                }
            }
            Text(verbatim: "\(clock(flight.departure)) → \(clock(flight.arrival))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func clock(_ side: AirportSide) -> String {
        guard let date = shown(side) else { return appString("미정", locale: locale) }
        return localTime(date, timeZone: side.timeZone, locale: locale)
    }
}

private struct CandidateSummary: View {
    var flight: Flight
    var entered: String
    var model: RegisterFlightModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "\(model.name(for: flight.departure.airport, locale: locale)) → \(model.name(for: flight.arrival.airport, locale: locale))")
            HStack(spacing: 4) {
                timeText(flight.departure)
                Text(verbatim: "→")
                    .foregroundStyle(.secondary)
                timeText(flight.arrival)
                if let offset = offset {
                    Text(verbatim: offset > 0 ? "+\(offset)" : "\(offset)")
                        .font(.caption.bold())
                        .monospacedDigit()
                }
                if needsLocalBadge(flight) {
                    Text("현지")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if codeshare(entered: entered, operating: flight.operating) {
                HStack(spacing: 4) {
                    Text("실제 운항")
                    Text(verbatim: displayOperatingCode(flight.operating))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 8) {
                if flight.isSample {
                    SampleDataChip()
                }
                if flight.origin == .user {
                    Chip(style: .userReport)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeText(_ side: AirportSide) -> some View {
        let changed = delayMinutes(side) != nil
        return HStack(spacing: 4) {
            if changed, let scheduled = side.scheduledAt {
                Text(verbatim: localTime(scheduled, timeZone: side.timeZone, locale: locale))
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let date = shown(side) {
                Text(verbatim: localTime(date, timeZone: side.timeZone, locale: locale))
                    .foregroundStyle(changed ? Color("StatusWarning") : Color.primary)
                    .monospacedDigit()
            } else {
                Text("미정")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var offset: Int? {
        guard let departure = shown(flight.departure), let arrival = shown(flight.arrival) else { return nil }
        let value = dayOffset(
            departure: departure,
            depTZ: flight.departure.timeZone,
            arrival: arrival,
            arrTZ: flight.arrival.timeZone
        )
        return value == 0 ? nil : value
    }
}
