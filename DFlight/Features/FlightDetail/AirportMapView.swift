import SwiftUI
#if !MOCK_DATA
import SafariServices
#endif

struct AirportMapView: View {
    var url: URL

    var body: some View {
        #if MOCK_DATA
        VStack(spacing: 12) {
            Text("Mock 빌드에서는 외부 페이지를 열지 않습니다")
                .font(.body)
                .multilineTextAlignment(.center)
            Text(url.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        #else
        DetailSafariPage(url: url)
            .ignoresSafeArea()
        #endif
    }
}

#if !MOCK_DATA
private struct DetailSafariPage: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
