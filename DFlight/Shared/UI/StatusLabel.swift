import SwiftUI

struct StatusLabel: View {
    var status: FlightStatusValue
    var onCard: Bool = false

    var body: some View {
        Text(title)
            .foregroundStyle(color)
    }

    private var title: LocalizedStringKey {
        switch status {
        case .scheduled: "예정"
        case .delayed: "지연"
        case .cancelled: "결항"
        case .departed: "출발함"
        case .arrived: "도착함"
        case .unknown: "상태 정보 없음"
        }
    }

    private var color: Color {
        switch status {
        case .delayed:
            Color(onCard ? "CardWarning" : "StatusWarning")
        case .cancelled:
            Color(onCard ? "CardDanger" : "StatusDanger")
        case .scheduled, .departed, .arrived, .unknown:
            onCard ? Color("CardSecondary") : .secondary
        }
    }
}
