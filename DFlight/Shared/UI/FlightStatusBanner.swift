import SwiftUI
import UIKit

/// Live Activity 잠금 화면과 같은 내용. 라이트·다크 모두 네이비 배경.
struct FlightStatusBanner: View {
    var enteredFlightNumber: String
    var flight: Flight
    var now: Date
    var isSample: Bool

    @Environment(\.locale) private var locale

    private var bannerSecondary: Color { Color.white.opacity(0.72) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headline
            timeRow
            placeRow
                .opacity(flight.status.value == .cancelled ? 0.4 : 1)
            if showsFootnote {
                footnote
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("BrandNavy"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var headline: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                flightLine
                Spacer(minLength: 8)
                statusText
            }
            VStack(alignment: .leading, spacing: 4) {
                flightLine
                statusText
            }
        }
    }

    private var flightLine: some View {
        Text(verbatim: "✈ \(enteredFlightNumber)  \(flight.departure.airport) → \(flight.arrival.airport)")
            .font(.headline.bold())
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var statusText: some View {
        switch flight.status.value {
        case .scheduled:
            EmptyView()
        case .delayed:
            delayText
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(onNavy("CardWarning"))
                .monospacedDigit()
                .lineLimit(1)
        case .cancelled:
            Text("결항")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(onNavy("CardDanger"))
                .lineLimit(1)
        case .departed:
            Text("출발함")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .arrived:
            Text("도착함")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .unknown:
            Text("상태 정보 없음")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(bannerSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var delayText: some View {
        if let minutes = delayMinutes(flight.departure), minutes > 0 {
            Text("지연 \(minutes)분")
        } else {
            Text("지연")
        }
    }

    private var timeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            departurePhrase
            Text(verbatim: " · ")
                .foregroundStyle(bannerSecondary)
            countdownPhrase
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var departurePhrase: some View {
        if let clock = departureClock {
            if needsLocalBadge(flight) {
                Text("출발 \(clock) (현지)")
                    .foregroundStyle(.white)
            } else {
                Text("출발 \(clock)")
                    .foregroundStyle(.white)
            }
        } else {
            Text("출발 미정")
                .foregroundStyle(bannerSecondary)
        }
    }

    @ViewBuilder
    private var countdownPhrase: some View {
        switch countdown(for: flight, now: now) {
        case .days(let count) where count > 0:
            Text("D-\(count)")
                .foregroundStyle(.white)
        case .days:
            Text("D-Day")
                .foregroundStyle(.white)
        case .remaining(let hours, let minutes):
            Text("\(remainingClock(hours: hours, minutes: minutes)) 남음")
                .foregroundStyle(.white)
        case .departed:
            Text("출발함")
                .foregroundStyle(.white)
        case .arrived:
            Text("도착함")
                .foregroundStyle(.white)
        case .cancelled:
            Text("결항")
                .foregroundStyle(onNavy("CardDanger"))
        }
    }

    private var placeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                place("터미널", terminal)
                Spacer(minLength: 8)
                place("게이트", gate)
            }
            VStack(alignment: .leading, spacing: 4) {
                place("터미널", terminal)
                place("게이트", gate)
            }
        }
        .font(.subheadline)
    }

    private func place(_ title: LocalizedStringKey, _ field: (text: String, missing: Bool)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .foregroundStyle(bannerSecondary)
            Text(verbatim: field.text)
                .fontWeight(.semibold)
                .foregroundStyle(field.missing ? bannerSecondary : .white)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSample || showsCodeshare {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isSample {
                        SampleDataChip(onDark: true)
                    }
                    if showsCodeshare {
                        Text("실제 운항: \(operatingCode) — 체크인은 \(airlineCode) 카운터에서 합니다")
                            .font(.caption)
                            .foregroundStyle(bannerSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if flight.status.value == .cancelled {
                Text("결항되었습니다. 항공사에 확인해 주세요.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(onNavy("CardDanger"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var showsFootnote: Bool {
        isSample || showsCodeshare || flight.status.value == .cancelled
    }

    private var showsCodeshare: Bool {
        codeshare(entered: enteredFlightNumber, operating: flight.operating)
    }

    private var operatingCode: String {
        displayOperatingCode(flight.operating)
    }

    private var airlineCode: String {
        normalizeFlightNumber(flight.operating.airline)
    }

    private var departureClock: String? {
        guard let date = flight.departure.estimatedAt.value ?? flight.departure.scheduledAt else { return nil }
        return localTime(date, timeZone: flight.departure.timeZone, locale: locale)
    }

    private var terminal: (text: String, missing: Bool) {
        fieldText(flight.departure.terminal, side: flight.departure)
    }

    private var gate: (text: String, missing: Bool) {
        fieldText(flight.departure.gate, side: flight.departure)
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
        case .awaiting, .noAutoData:
            return (appString("정보 없음", locale: locale), true)
        }
    }

    private func remainingClock(hours: Int, minutes: Int) -> String {
        String(format: "%d:%02d", locale: locale, hours, minutes)
    }

    /// 카드 위 지연·결항 색. 배너는 모드와 상관없이 네이비라 다크 변형을 쓴다.
    private func onNavy(_ name: String) -> Color {
        let base = UIColor(named: name) ?? .white
        let dark = base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        return Color(uiColor: dark)
    }

    private var accessibilityText: String {
        var parts = [
            enteredFlightNumber,
            String(
                format: appString("%1$@에서 %2$@", locale: locale),
                locale: locale,
                flight.departure.airport,
                flight.arrival.airport
            )
        ]
        switch flight.status.value {
        case .scheduled:
            break
        case .delayed:
            if let minutes = delayMinutes(flight.departure), minutes > 0 {
                parts.append(String(format: appString("%lld분 지연", locale: locale), locale: locale, minutes))
            } else {
                parts.append(appString("지연", locale: locale))
            }
        case .cancelled:
            parts.append(appString("결항", locale: locale))
        case .departed:
            parts.append(appString("출발함", locale: locale))
        case .arrived:
            parts.append(appString("도착함", locale: locale))
        case .unknown:
            parts.append(appString("상태 정보 없음", locale: locale))
        }
        if let clock = departureClock {
            parts.append(String(format: appString("%@ 출발", locale: locale), locale: locale, clock))
        }
        switch countdown(for: flight, now: now) {
        case .days(let count) where count > 0:
            parts.append(String(format: appString("%lld일 후", locale: locale), locale: locale, count))
        case .days:
            parts.append(appString("오늘", locale: locale))
        case .remaining(let hours, let minutes):
            parts.append(
                String(
                    format: appString("%@ 남음", locale: locale),
                    locale: locale,
                    remainingClock(hours: hours, minutes: minutes)
                )
            )
        case .departed:
            parts.append(appString("출발함", locale: locale))
        case .arrived:
            parts.append(appString("도착함", locale: locale))
        case .cancelled:
            parts.append(appString("결항", locale: locale))
        }
        parts.append(String(format: appString("터미널 %@", locale: locale), locale: locale, terminal.text))
        parts.append(String(format: appString("게이트 %@", locale: locale), locale: locale, gate.text))
        if isSample {
            parts.append(appString("샘플 데이터", locale: locale))
        }
        if showsCodeshare {
            parts.append(String(format: appString("실제 운항 %@", locale: locale), locale: locale, operatingCode))
        }
        if flight.status.value == .cancelled {
            parts.append(appString("결항되었습니다. 항공사에 확인해 주세요.", locale: locale))
        }
        return parts.joined(separator: ", ")
    }
}
