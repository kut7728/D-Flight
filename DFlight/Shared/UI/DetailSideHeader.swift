import SwiftUI

struct DetailSideHeader: View {
    var title: Text
    var showsEdit: Bool
    var editLabel: LocalizedStringKey
    var onEdit: () -> Void

    @ScaledMetric(relativeTo: .headline) private var titleSize = 18

    var body: some View {
        HStack(spacing: 8) {
            title
                .font(.system(size: titleSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if showsEdit {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(editLabel))
            }
        }
        .modifier(DetailRowHeight(height: 52))
    }
}
