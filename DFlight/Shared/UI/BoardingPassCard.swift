import SwiftUI

struct BoardingPassCard: View {
    var tracked: TrackedFlight
    var departureName: String
    var arrivalName: String
    var now: Date
    var action: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var flight: Flight { tracked.flight }
    private var stacksVertically: Bool { dynamicTypeSize.isAccessibilitySize }
    private var cancelled: Bool { flight.status.value == .cancelled }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                header
                    .padding(16)
                perforation
                facts
                    .padding(16)
                    .opacity(cancelled ? 0.4 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("CardBackground"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: tracked.enteredFlightNumber)
                        .font(.title2.bold())
                        .monospacedDigit()
                    if showsSample(tracked) {
                        SampleDataChip()
                    }
                }
                if codeshare(entered: tracked.enteredFlightNumber, operating: flight.operating) {
                    HStack(spacing: 4) {
                        Text("실제 운항")
                        Text(verbatim: displayOperatingCode(flight.operating))
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            route
            times
        }
        .foregroundStyle(Color("CardText"))
    }

    private var topRow: some View {
        let day = dDay(for: flight, now: now)
        return pair {
            DDayLabel(flight: flight, now: now, onCard: true)
                .font(.headline.bold())
                .monospacedDigit()
        } trailing: {
            if showsSideStatus(day) {
                CardDelayStatus(flight: flight)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var route: some View {
        VStack(alignment: stacksVertically ? .leading : .center, spacing: 4) {
            if stacksVertically {
                codeText(flight.departure.airport)
                nameText(departureName, alignment: .leading)
                planeLine
                codeText(flight.arrival.airport)
                nameText(arrivalName, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    codeText(flight.departure.airport)
                    planeLine
                    codeText(flight.arrival.airport)
                }
                HStack {
                    nameText(departureName, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    nameText(arrivalName, alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func codeText(_ code: String) -> some View {
        Text(verbatim: code)
            .font(.largeTitle.bold())
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func nameText(_ name: String, alignment: HorizontalAlignment) -> some View {
        Text(verbatim: name)
            .font(.subheadline)
            .lineLimit(2)
            .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
    }

    private var planeLine: some View {
        HStack(spacing: 4) {
            DashedRule()
            Image(systemName: "airplane")
                .font(.subheadline)
                .foregroundStyle(Color("CardText"))
            DashedRule()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
    }

    private var times: some View {
        let marks = HStack(spacing: 4) {
            if let offset = arrivalOffset, offset != 0 {
                Text(verbatim: offset > 0 ? "+\(offset)" : "\(offset)")
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            if needsLocalBadge(flight) {
                Text("현지")
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(Color("CardSecondary"))

        return Group {
            if stacksVertically {
                VStack(alignment: .leading, spacing: 12) {
                    ClockBlock(side: flight.departure, showsDate: true, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ClockBlock(side: flight.arrival, showsDate: false, alignment: .leading)
                        marks
                    }
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    ClockBlock(side: flight.departure, showsDate: true, alignment: .leading)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        ClockBlock(side: flight.arrival, showsDate: false, alignment: .trailing)
                        marks
                    }
                }
            }
        }
    }

    /// 절취선. 반원 홈은 화면 배경색으로 덮어 뚫린 것처럼 보이게 한다.
    private var perforation: some View {
        ZStack {
            DashedRule()
                .padding(.horizontal, 12)
            HStack {
                notch
                    .offset(x: -12)
                Spacer()
                notch
                    .offset(x: 12)
            }
        }
        .frame(height: 24)
    }

    private var notch: some View {
        Circle()
            .fill(Color(.systemGroupedBackground))
            .frame(width: 24, height: 24)
    }

    private var facts: some View {
        let terminal = fieldText(flight.departure.terminal, side: flight.departure)
        let gate = fieldText(flight.departure.gate, side: flight.departure)
        return Group {
            if stacksVertically {
                VStack(alignment: .leading, spacing: 12) {
                    fact("터미널", terminal.text, missing: terminal.missing, alignment: .leading)
                    fact("게이트", gate.text, missing: gate.missing, alignment: .leading)
                    fact("탑승 시작", boarding.text, missing: boarding.missing, alignment: .leading, singleLine: !boarding.missing)
                }
            } else {
                // 제목과 값을 나눠, 세 칸의 값 기준선을 맞춘다.
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        factTitle("터미널")
                        factTitle("게이트")
                        factTitle("탑승 시작")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        factValue(terminal.text, missing: terminal.missing)
                        factValue(gate.text, missing: gate.missing)
                        factValue(boarding.text, missing: boarding.missing, singleLine: !boarding.missing)
                    }
                }
            }
        }
    }

    private func factTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Color("CardSecondary"))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fact(
        _ title: LocalizedStringKey,
        _ value: String,
        missing: Bool,
        alignment: HorizontalAlignment,
        singleLine: Bool = false
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color("CardSecondary"))
            factValue(value, missing: missing, singleLine: singleLine, alignment: alignment)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }

    private func factValue(
        _ value: String,
        missing: Bool,
        singleLine: Bool = false,
        alignment: HorizontalAlignment = .center
    ) -> some View {
        Text(verbatim: value)
            .font(.title2.bold())
            .foregroundStyle(missing ? Color("CardSecondary") : Color("CardText"))
            .monospacedDigit()
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .lineLimit(singleLine ? 1 : 3)
            .minimumScaleFactor(singleLine ? 0.35 : 0.7)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }

    private var boarding: (text: String, missing: Bool) {
        guard let date = estimatedBoardingTime(flight) else {
            return (appString("정보 없음", locale: locale), true)
        }
        let clock = localTime(date, timeZone: flight.departure.timeZone, locale: locale)
        let text = String(format: appString("약 %@ 추정", locale: locale), locale: locale, clock)
        return (text, false)
    }

    private var arrivalOffset: Int? {
        guard let departure = shown(flight.departure), let arrival = shown(flight.arrival) else { return nil }
        return dayOffset(
            departure: departure,
            depTZ: flight.departure.timeZone,
            arrival: arrival,
            arrTZ: flight.arrival.timeZone
        )
    }

    private func fieldText(_ item: InfoItem, side: AirportSide) -> (text: String, missing: Bool) {
        switch infoState(item, side: side, flight: flight, now: now) {
        case .confirmedAirport(let value, _, _), .confirmedUser(let value):
            return (value, false)
        case .checkFailed(let last, _):
            if let last, !last.isEmpty { return (last, false) }
            return (appString("정보 없음", locale: locale), true)
        case .undetermined:
            return (appString("미정", locale: locale), true)
        case .awaiting:
            return (appString("출발 3일 전부터 표시", locale: locale), true)
        case .noAutoData:
            return (appString("정보 없음", locale: locale), true)
        }
    }

    private func showsSideStatus(_ day: DDay) -> Bool {
        switch day {
        case .departed, .arrived:
            return false
        case .days, .today:
            return flight.status.value != .scheduled
        }
    }

    @ViewBuilder
    private func pair<L: View, R: View>(
        @ViewBuilder _ leading: () -> L,
        @ViewBuilder trailing: () -> R
    ) -> some View {
        if stacksVertically {
            VStack(alignment: .leading, spacing: 12) {
                leading()
                trailing()
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                leading()
                Spacer(minLength: 8)
                trailing()
            }
        }
    }

    private var accessibilityText: String {
        var parts = [tracked.enteredFlightNumber]
        if codeshare(entered: tracked.enteredFlightNumber, operating: flight.operating) {
            parts.append(
                String(
                    format: appString("실제 운항 %@", locale: locale),
                    locale: locale,
                    displayOperatingCode(flight.operating)
                )
            )
        }
        parts.append(
            String(
                format: appString("%1$@에서 %2$@", locale: locale),
                locale: locale,
                departureName,
                arrivalName
            )
        )
        switch dDay(for: flight, now: now) {
        case .days(let count):
            parts.append(String(format: appString("%lld일 후", locale: locale), locale: locale, count))
        case .today:
            parts.append(appString("오늘", locale: locale))
        case .departed:
            parts.append(appString("출발함", locale: locale))
        case .arrived:
            parts.append(appString("도착함", locale: locale))
        }
        if let departure = shown(flight.departure) {
            let clock = localTime(departure, timeZone: flight.departure.timeZone, locale: locale)
            parts.append(String(format: appString("%@ 출발", locale: locale), locale: locale, clock))
        }
        switch flight.status.value {
        case .delayed:
            if let minutes = delayMinutes(flight.departure), minutes > 0 {
                parts.append(String(format: appString("%lld분 지연", locale: locale), locale: locale, minutes))
            } else {
                parts.append(appString("지연", locale: locale))
            }
        case .cancelled:
            parts.append(appString("결항", locale: locale))
        case .unknown:
            parts.append(appString("상태 정보 없음", locale: locale))
        case .scheduled, .departed, .arrived:
            break
        }
        let terminal = fieldText(flight.departure.terminal, side: flight.departure).text
        let gate = fieldText(flight.departure.gate, side: flight.departure).text
        parts.append(String(format: appString("터미널 %@", locale: locale), locale: locale, terminal))
        parts.append(String(format: appString("게이트 %@", locale: locale), locale: locale, gate))
        if showsSample(tracked) {
            parts.append(appString("샘플 데이터", locale: locale))
        }
        return parts.joined(separator: ", ")
    }
}

struct DDayLabel: View {
    var flight: Flight
    var now: Date
    var onCard: Bool = false

    var body: some View {
        switch dDay(for: flight, now: now) {
        case .days(let count):
            Text("D-\(count)")
        case .today:
            Text("D-Day")
        case .departed:
            StatusLabel(status: .departed, onCard: onCard)
        case .arrived:
            StatusLabel(status: .arrived, onCard: onCard)
        }
    }
}

private struct CardDelayStatus: View {
    var flight: Flight

    var body: some View {
        if flight.status.value == .delayed, let minutes = delayMinutes(flight.departure), minutes > 0 {
            Text("지연 \(minutes)분")
                .foregroundStyle(Color("CardWarning"))
                .monospacedDigit()
        } else {
            StatusLabel(status: flight.status.value, onCard: true)
        }
    }
}

private struct ClockBlock: View {
    var side: AirportSide
    var showsDate: Bool
    var alignment: HorizontalAlignment

    @Environment(\.locale) private var locale

    var body: some View {
        let shown = shown(side)
        let changed = delayMinutes(side) != nil
        VStack(alignment: alignment, spacing: 2) {
            if showsDate, let shown {
                Text(verbatim: civilDay(shown, timeZone: side.timeZone, locale: locale))
                    .font(.caption)
                    .foregroundStyle(Color("CardSecondary"))
            }
            HStack(spacing: 4) {
                if changed, let scheduled = side.scheduledAt {
                    Text(verbatim: localTime(scheduled, timeZone: side.timeZone, locale: locale))
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(Color("CardSecondary"))
                }
                if let shown {
                    Text(verbatim: localTime(shown, timeZone: side.timeZone, locale: locale))
                        .font(.title2.bold())
                        .foregroundStyle(changed ? Color("CardWarning") : Color("CardText"))
                } else {
                    Text("미정")
                        .font(.subheadline)
                        .foregroundStyle(Color("CardSecondary"))
                }
            }
            .monospacedDigit()
        }
    }
}

private struct DashedRule: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let y = geo.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            .stroke(Color("CardSecondary"), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }
}

func showsSample(_ tracked: TrackedFlight) -> Bool {
    tracked.isSample || tracked.flight.isSample
}

func displayOperatingCode(_ operating: OperatingFlight) -> String {
    let number = normalizeFlightNumber(operating.flightNumber)
    let airline = normalizeFlightNumber(operating.airline)
    if airline.isEmpty || number.hasPrefix(airline) { return number }
    return airline + number
}

func codeshare(entered: String, operating: OperatingFlight) -> Bool {
    let entered = normalizeFlightNumber(entered)
    let code = displayOperatingCode(operating)
    return !entered.isEmpty && !code.isEmpty && entered != code
}

func shown(_ side: AirportSide) -> Date? {
    side.estimatedAt.value ?? side.scheduledAt
}

func civilDay(_ date: Date, timeZone: String, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: timeZone) ?? .gmt
    formatter.setLocalizedDateFormatFromTemplate("MdEEE")
    return formatter.string(from: date)
}

func civilDate(from ymd: String, locale: Locale) -> String {
    let parts = ymd.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return ymd }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
        return ymd
    }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.timeZone = .gmt
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}
