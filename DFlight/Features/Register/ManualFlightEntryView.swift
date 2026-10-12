import SwiftUI

struct ManualFlightEntryView: View {
    var flightNumber: String = ""
    var departureDate: String = ""
    var onRegistered: () -> Void = {}

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ManualFlightForm(
            repository: env.flights,
            flightNumber: flightNumber,
            departureDate: departureDate,
            onRegistered: onRegistered
        )
    }
}

@MainActor
@Observable
private final class ManualFlightModel {
    private let repository: any FlightRepository
    let flightNumber: String
    let departureDate: String

    var departure: Airport?
    var arrival: Airport?
    var departureTime = Date()
    var includesArrival = false
    var arrivalTime = Date()
    var arrivalDayOffset = 0
    var terminal = ""
    var gate = ""
    var checkIn = ""
    var baggage = ""
    private(set) var isSubmitting = false
    private(set) var saveFailed = false

    init(repository: any FlightRepository, flightNumber: String, departureDate: String) {
        self.repository = repository
        self.flightNumber = flightNumber
        self.departureDate = departureDate
    }

    var terminalOptions: [String] {
        let listed = departure?.terminals ?? []
        if listed.isEmpty { return (1...9).map { "T\($0)" } }
        return listed
    }

    var canSubmit: Bool {
        guard isValidFlightNumber(flightNumber), !departureDate.isEmpty else { return false }
        guard let departure, let arrival, departure.code != arrival.code else { return false }
        if !gate.isEmpty && !isValidGate(gate) { return false }
        if !checkIn.isEmpty && !isValidCheckInCounter(checkIn) { return false }
        if !baggage.isEmpty && !isValidBaggageBelt(baggage) { return false }
        return !isSubmitting
    }

    func submit() async -> Bool {
        guard let departure, let arrival, canSubmit else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        let input = ManualFlightInput(
            flightNumber: normalizeFlightNumber(flightNumber),
            departureDate: departureDate,
            depAirport: departure.code,
            arrAirport: arrival.code,
            scheduledDepartureLocal: localComponents(on: departureDate, time: departureTime, dayOffset: 0),
            scheduledArrivalLocal: includesArrival
                ? localComponents(on: departureDate, time: arrivalTime, dayOffset: arrivalDayOffset)
                : nil,
            arrivalDayOffset: includesArrival ? arrivalDayOffset : 0,
            terminal: nilIfEmpty(terminal),
            gate: nilIfEmpty(gate),
            checkInCounter: nilIfEmpty(checkIn),
            baggageBelt: nilIfEmpty(baggage)
        )
        do {
            _ = try await repository.createManual(input)
            saveFailed = false
            return true
        } catch {
            saveFailed = true
            return false
        }
    }

    private func nilIfEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ManualFlightForm: View {
    var onRegistered: () -> Void
    @Environment(\.locale) private var locale
    @State private var model: ManualFlightModel

    init(repository: any FlightRepository, flightNumber: String, departureDate: String, onRegistered: @escaping () -> Void) {
        self.onRegistered = onRegistered
        _model = State(initialValue: ManualFlightModel(
            repository: repository,
            flightNumber: flightNumber,
            departureDate: departureDate
        ))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Text("입력한 정보는 같은 항공편을 등록한 사용자에게 공유됩니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("편명") {
                    Text(verbatim: model.flightNumber)
                        .monospacedDigit()
                }
                LabeledContent("출발 날짜") {
                    Text(verbatim: model.departureDate)
                        .monospacedDigit()
                }
            }
            Section {
                NavigationLink {
                    AirportSearchView(selection: $model.departure)
                } label: {
                    LabeledContent("출발 공항", value: airportLabel(model.departure))
                }
                NavigationLink {
                    AirportSearchView(selection: $model.arrival)
                } label: {
                    LabeledContent("도착 공항", value: airportLabel(model.arrival))
                }
                if model.departure != nil, model.arrival != nil, model.departure?.code == model.arrival?.code {
                    Text("출발 공항과 도착 공항은 달라야 합니다.")
                        .font(.caption)
                        .foregroundStyle(Color("StatusDanger"))
                }
            }
            Section {
                DatePicker("출발 예정 시각", selection: $model.departureTime, displayedComponents: .hourAndMinute)
            } footer: {
                Text("출발 공항 현지 시각")
            }
            Section {
                Toggle("도착 예정 시각", isOn: $model.includesArrival)
                if model.includesArrival {
                    DatePicker("도착 시각", selection: $model.arrivalTime, displayedComponents: .hourAndMinute)
                    Picker("날짜 차이", selection: $model.arrivalDayOffset) {
                        Text(verbatim: "-1").tag(-1)
                        Text(verbatim: "0").tag(0)
                        Text(verbatim: "+1").tag(1)
                        Text(verbatim: "+2").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                if model.includesArrival {
                    Text("도착 공항 현지 시각. 날짜 차이는 출발일 기준입니다.")
                }
            }
            Section {
                Picker("터미널", selection: $model.terminal) {
                    Text("선택 안 함").tag("")
                    ForEach(model.terminalOptions, id: \.self) { option in
                        Text(verbatim: option).tag(option)
                    }
                }
                TextField("게이트", text: $model.gate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("체크인 카운터", text: $model.checkIn)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("수하물 수취대", text: $model.baggage)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !model.gate.isEmpty && !isValidGate(model.gate) {
                        Text("게이트는 영문·숫자 1~5자입니다.")
                    }
                    if !model.checkIn.isEmpty && !isValidCheckInCounter(model.checkIn) {
                        Text("체크인 카운터는 영문·숫자·- 1~7자입니다.")
                    }
                    if !model.baggage.isEmpty && !isValidBaggageBelt(model.baggage) {
                        Text("수하물 수취대는 영문·숫자 1~3자입니다.")
                    }
                }
                .foregroundStyle(Color("StatusDanger"))
            }
            if model.saveFailed {
                Section {
                    Text("지금은 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Task {
                        if await model.submit() { onRegistered() }
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
                .disabled(!model.canSubmit)
            }
        }
        .navigationTitle("직접 입력")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.departure?.code) { _, _ in
            if !model.terminalOptions.contains(model.terminal) {
                model.terminal = ""
            }
        }
    }

    private func airportLabel(_ airport: Airport?) -> String {
        guard let airport else { return appString("선택", locale: locale) }
        return "\(airport.name(for: locale)) (\(airport.code))"
    }
}

private struct AirportSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Binding var selection: Airport?
    @State private var query = ""
    @State private var results: [Airport] = []
    @State private var failed = false
    @State private var hasLoaded = false

    var body: some View {
        List {
            if failed {
                Text("지금은 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.")
                    .foregroundStyle(.secondary)
            } else if !hasLoaded {
                ProgressView()
            } else if results.isEmpty {
                Text("일치하는 공항이 없습니다")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results, id: \.code) { airport in
                    Button {
                        selection = airport
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: airport.name(for: locale))
                            Text(verbatim: airport.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("공항")
        .searchable(text: $query, prompt: "공항 이름 또는 코드")
        .task(id: query) {
            do {
                results = try await env.flights.airports(matching: query.trimmingCharacters(in: .whitespacesAndNewlines))
                failed = false
            } catch {
                results = []
                failed = true
            }
            hasLoaded = true
        }
    }
}

private func localComponents(on ymd: String, time: Date, dayOffset: Int) -> DateComponents {
    let parts = ymd.split(separator: "-").compactMap { Int($0) }
    let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    var comps = DateComponents()
    comps.hour = clock.hour
    comps.minute = clock.minute
    guard parts.count == 3,
          let base = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
          let shifted = calendar.date(byAdding: .day, value: dayOffset, to: base) else {
        return comps
    }
    let day = calendar.dateComponents([.year, .month, .day], from: shifted)
    comps.year = day.year
    comps.month = day.month
    comps.day = day.day
    return comps
}
