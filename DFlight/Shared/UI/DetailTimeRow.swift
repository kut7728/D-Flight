import SwiftUI

struct DetailTimeRow: View {
    var title: LocalizedStringKey
    var time: String?
    var previousTime: String?
    var offset: Int = 0
    var missing: LocalizedStringKey = "미정"

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let previousTime {
                Text(previousTime)
                    .font(.subheadline)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if let time {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(time)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(previousTime == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color("StatusWarning")))
                    if offset != 0 {
                        Text(verbatim: offset > 0 ? "+\(offset)" : "\(offset)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(previousTime == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color("StatusWarning")))
                    }
                }
                .lineLimit(1)
            } else {
                Text(missing)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(DetailRowHeight(height: 48))
    }
}
