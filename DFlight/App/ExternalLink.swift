import SwiftUI

enum ExternalLink {
    static let privacy = URL(string: "https://kut7728.github.io/D-Flight/ko/privacy.html")!
    static let terms = URL(string: "https://dflight.example/terms")!

    /// Mock에서는 URL을 열지 않고 경고로 보여 준다.
    @MainActor
    static func open(_ url: URL, reveal: (String) -> Void) {
        #if MOCK_DATA
        reveal(url.absoluteString)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    @MainActor
    static func open(_ url: URL, blocked: Binding<String?>) {
        open(url) { blocked.wrappedValue = $0 }
    }
}

extension View {
    func detailExternalAlert(_ blocked: Binding<String?>) -> some View {
        alert(
            "Mock 빌드에서는 외부 페이지를 열지 않습니다",
            isPresented: Binding(
                get: { blocked.wrappedValue != nil },
                set: { if !$0 { blocked.wrappedValue = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(blocked.wrappedValue ?? "")
        }
    }
}
