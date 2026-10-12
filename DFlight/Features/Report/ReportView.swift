import SwiftUI

@Observable
final class ReportViewModel {
    let flight: Flight
    var departureAirport: Airport?
    var arrivalAirport: Airport?

    var departureTerminal: String
    var departureGate: String
    var departureCheckIn: String
    var arrivalTerminal: String
    var arrivalGate: String
    var arrivalBaggage: String

    var isSaving = false
    var errorMessage: String?

    init(flight: Flight) {
        self.flight = flight
        departureTerminal = flight.departure.terminal.value ?? ""
        departureGate = flight.departure.gate.value ?? ""
        departureCheckIn = flight.departure.checkInCounter?.value ?? ""
        arrivalTerminal = flight.arrival.terminal.value ?? ""
        arrivalGate = flight.arrival.gate.value ?? ""
        arrivalBaggage = flight.arrival.baggageBelt?.value ?? ""
    }

    private var originalDepartureTerminal: String { flight.departure.terminal.value ?? "" }
    private var originalDepartureGate: String { flight.departure.gate.value ?? "" }
    private var originalDepartureCheckIn: String { flight.departure.checkInCounter?.value ?? "" }
    private var originalArrivalTerminal: String { flight.arrival.terminal.value ?? "" }
    private var originalArrivalGate: String { flight.arrival.gate.value ?? "" }
    private var originalArrivalBaggage: String { flight.arrival.baggageBelt?.value ?? "" }

    var canSave: Bool {
        !isSaving
            && departureGateError == nil
            && departureCheckInError == nil
            && arrivalGateError == nil
            && arrivalBaggageError == nil
            && !changes().isEmpty
    }

    var departureGateError: LocalizedStringKey? {
        guard flight.departure.gate.source != .airportData else { return nil }
        return error(departureGate, valid: isValidGate, message: "영문·숫자 1~5자로 입력해 주세요")
    }

    var arrivalGateError: LocalizedStringKey? {
        guard flight.arrival.gate.source != .airportData else { return nil }
        return error(arrivalGate, valid: isValidGate, message: "영문·숫자 1~5자로 입력해 주세요")
    }

    var departureCheckInError: LocalizedStringKey? {
        guard flight.departure.checkInCounter?.source != .airportData else { return nil }
        return error(departureCheckIn, valid: isValidCheckInCounter, message: "영문·숫자·- 1~7자로 입력해 주세요")
    }

    var arrivalBaggageError: LocalizedStringKey? {
        guard flight.arrival.baggageBelt?.source != .airportData else { return nil }
        return error(arrivalBaggage, valid: isValidBaggageBelt, message: "영문·숫자 1~3자로 입력해 주세요")
    }

    func terminals(for airport: Airport?, current: String) -> [String] {
        var options = airport?.terminals.filter { !$0.isEmpty } ?? []
        if options.isEmpty {
            options = (1...9).map { "T\($0)" }
        }
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    /// `nil` 필드는 그대로 두고, 값이 바뀐 항목만 `.some`으로 담는다. 빈 문자열은 지우기.
    func changes() -> [ReportInput] {
        var inputs: [ReportInput] = []
        var departure = ReportInput(side: .departure)
        var departureChanged = false
        if assign(&departure.terminal, from: originalDepartureTerminal, to: departureTerminal, locked: flight.departure.terminal.source == .airportData) {
            departureChanged = true
        }
        if assign(&departure.gate, from: originalDepartureGate, to: departureGate, locked: flight.departure.gate.source == .airportData) {
            departureChanged = true
        }
        if assign(&departure.checkInCounter, from: originalDepartureCheckIn, to: departureCheckIn, locked: flight.departure.checkInCounter?.source == .airportData) {
            departureChanged = true
        }
        if departureChanged { inputs.append(departure) }

        var arrival = ReportInput(side: .arrival)
        var arrivalChanged = false
        if assign(&arrival.terminal, from: originalArrivalTerminal, to: arrivalTerminal, locked: flight.arrival.terminal.source == .airportData) {
            arrivalChanged = true
        }
        if assign(&arrival.gate, from: originalArrivalGate, to: arrivalGate, locked: flight.arrival.gate.source == .airportData) {
            arrivalChanged = true
        }
        if assign(&arrival.baggageBelt, from: originalArrivalBaggage, to: arrivalBaggage, locked: flight.arrival.baggageBelt?.source == .airportData) {
            arrivalChanged = true
        }
        if arrivalChanged { inputs.append(arrival) }
        return inputs
    }

    private func assign(_ field: inout String??, from original: String, to edited: String, locked: Bool) -> Bool {
        let next = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !locked, next != previous else { return false }
        field = .some(next.isEmpty ? nil : next)
        return true
    }

    private func error(_ text: String, valid: (String) -> Bool, message: LocalizedStringKey) -> LocalizedStringKey? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || valid(trimmed) { return nil }
        return message
    }
}

struct ReportView: View {
    var flight: Flight

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: ReportViewModel

    init(flight: Flight) {
        self.flight = flight
        _model = State(initialValue: ReportViewModel(flight: flight))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("입력한 정보는 같은 항공편을 등록한 사용자에게 공유됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    sideFields(
                        terminal: $model.departureTerminal,
                        gate: $model.departureGate,
                        extraTitle: "체크인",
                        extra: $model.departureCheckIn,
                        terminalItem: flight.departure.terminal,
                        gateItem: flight.departure.gate,
                        extraItem: flight.departure.checkInCounter ?? InfoItem(),
                        gateError: model.departureGateError,
                        extraError: model.departureCheckInError,
                        terminals: model.terminals(for: model.departureAirport, current: model.departureTerminal)
                    )
                } header: {
                    Text("출발 · \(name(flight.departure, airport: model.departureAirport)) (\(flight.departure.airport))")
                }
                Section {
                    sideFields(
                        terminal: $model.arrivalTerminal,
                        gate: $model.arrivalGate,
                        extraTitle: "수하물",
                        extra: $model.arrivalBaggage,
                        terminalItem: flight.arrival.terminal,
                        gateItem: flight.arrival.gate,
                        extraItem: flight.arrival.baggageBelt ?? InfoItem(),
                        gateError: model.arrivalGateError,
                        extraError: model.arrivalBaggageError,
                        terminals: model.terminals(for: model.arrivalAirport, current: model.arrivalTerminal)
                    )
                } header: {
                    Text("도착 · \(name(flight.arrival, airport: model.arrivalAirport)) (\(flight.arrival.airport))")
                }
            }
            .navigationTitle("정보 제보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(!model.canSave)
                }
            }
            .task {
                model.departureAirport = try? await env.flights.airport(code: flight.departure.airport)
                model.arrivalAirport = try? await env.flights.airport(code: flight.arrival.airport)
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
        }
    }

    private func sideFields(
        terminal: Binding<String>,
        gate: Binding<String>,
        extraTitle: LocalizedStringKey,
        extra: Binding<String>,
        terminalItem: InfoItem,
        gateItem: InfoItem,
        extraItem: InfoItem,
        gateError: LocalizedStringKey?,
        extraError: LocalizedStringKey?,
        terminals: [String]
    ) -> some View {
        Group {
            field("터미널", item: terminalItem) {
                Picker("터미널", selection: terminal) {
                    Text("없음").tag("")
                    ForEach(terminals, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
            field("게이트", item: gateItem) {
                TextField("게이트", text: gate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            if let gateError {
                Text(gateError)
                    .font(.caption)
                    .foregroundStyle(Color("StatusDanger"))
            }
            field(extraTitle, item: extraItem) {
                TextField(extraTitle, text: extra)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            if let extraError {
                Text(extraError)
                    .font(.caption)
                    .foregroundStyle(Color("StatusDanger"))
            }
        }
    }

    @ViewBuilder
    private func field<Editor: View>(_ title: LocalizedStringKey, item: InfoItem, @ViewBuilder editor: () -> Editor) -> some View {
        if item.source == .airportData {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(title) {
                    if let value = item.value, !value.isEmpty {
                        Text(value)
                    } else {
                        Text("미정")
                    }
                }
                Text("(공항 데이터로 제공 중)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            editor()
        }
    }

    private func name(_ side: AirportSide, airport: Airport?) -> String {
        airport?.name(for: locale) ?? side.airport
    }

    private func save() async {
        guard !model.isSaving else { return }
        let inputs = model.changes()
        guard !inputs.isEmpty else {
            dismiss()
            return
        }
        model.isSaving = true
        defer { model.isSaving = false }
        do {
            for input in inputs {
                try await env.flights.submitReport(flightKey: flight.key, input)
            }
            dismiss()
        } catch {
            model.errorMessage = appString("저장하지 못했습니다", locale: locale)
        }
    }
}
