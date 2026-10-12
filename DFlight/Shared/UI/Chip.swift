import SwiftUI

struct Chip: View {
    enum Style {
        case userReport
        case sampleData
        case changed
    }

    var style: Style

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                if style == .userReport {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Color.secondary, lineWidth: 1)
                }
            }
    }

    private var label: LocalizedStringKey {
        switch style {
        case .userReport: "사용자 제보"
        case .sampleData: "샘플 데이터"
        case .changed: "변경"
        }
    }

    private var foreground: Color {
        switch style {
        case .userReport: .secondary
        case .sampleData: .primary
        case .changed: Color("StatusWarning")
        }
    }

    private var background: Color {
        switch style {
        case .userReport: .clear
        case .sampleData: Color.secondary.opacity(0.2)
        case .changed: Color("StatusWarning").opacity(0.15)
        }
    }
}

struct SampleDataChip: View {
    var onDark = false

    var body: some View {
        if onDark {
            Text("샘플 데이터")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 11))
        } else {
            Chip(style: .sampleData)
        }
    }
}
