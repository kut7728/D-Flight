import SwiftUI

struct InfoRow: View {
    var title: LocalizedStringKey
    var state: InfoItemState
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .opacity(dimmed ? 0.4 : 1)
        .modifier(DetailRowHeight(height: 48))
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .confirmedAirport(let value, let changed, let previous):
            HStack(spacing: 8) {
                if changed {
                    Chip(style: .changed)
                }
                if changed, let previous, previous != value {
                    struck(previous)
                }
                valueLabel(value)
            }
        case .confirmedUser(let value):
            HStack(spacing: 8) {
                Chip(style: .userReport)
                valueLabel(value)
            }
        case .undetermined:
            placeholder("미정", prominent: true)
        case .awaiting:
            placeholder("출발 3일 전부터 표시", prominent: false)
        case .noAutoData:
            placeholder("정보 없음", prominent: true)
        case .checkFailed(let lastValue, _):
            HStack(spacing: 8) {
                Text("확인 실패")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let lastValue, !lastValue.isEmpty {
                    valueLabel(lastValue)
                }
            }
        }
    }

    private func valueLabel(_ value: String) -> some View {
        Text(value)
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
    }

    private func struck(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .strikethrough()
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private func placeholder(_ key: LocalizedStringKey, prominent: Bool) -> some View {
        Text(key)
            .font(prominent ? .title3.weight(.semibold) : .subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
