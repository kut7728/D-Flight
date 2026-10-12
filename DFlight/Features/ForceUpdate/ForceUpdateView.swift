import SwiftUI

struct ForceUpdateView: View {
    var appStoreURL: URL
    @State private var linkURL: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "airplane")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color("BrandNavy"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("업데이트가 필요합니다")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("계속 쓰려면 새 버전을 받아 주세요.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("App Store에서 업데이트") {
                ExternalLink.open(appStoreURL) { linkURL = $0 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .interactiveDismissDisabled(true)
        .alert("App Store에서 업데이트", isPresented: Binding(
            get: { linkURL != nil },
            set: { if !$0 { linkURL = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(linkURL ?? "")
        }
    }
}
