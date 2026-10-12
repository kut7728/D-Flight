import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var isWorking = false
    @State private var failed = false
    @State private var policy: PolicyLink?
    @State private var linkURL: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("D-Flight")
                .font(.largeTitle.bold())
            Text("예매한 비행기, 놓치지 않게")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 12) {
                appleButton
                googleButton
            }
            policyLinks
                .padding(.top, 24)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .alert("로그인하지 못했습니다. 다시 시도해 주세요.", isPresented: $failed) {
            Button("확인", role: .cancel) {}
        }
        .alert(policyTitle, isPresented: Binding(
            get: { linkURL != nil },
            set: { if !$0 { linkURL = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(linkURL ?? "")
        }
    }

    @ViewBuilder
    private var appleButton: some View {
        #if MOCK_DATA
        Button {
            signIn(.apple)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                Text("Apple로 계속하기")
                    .font(.headline)
            }
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(colorScheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        #else
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { _ in }
        .frame(height: 50)
        #endif
    }

    private var googleButton: some View {
        Button {
            #if MOCK_DATA
            signIn(.google)
            #endif
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: "G")
                    .font(.headline.bold())
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                Text("Google로 계속하기")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var policyLinks: some View {
        HStack(spacing: 8) {
            Button("개인정보 처리방침") { present(.privacy, url: ExternalLink.privacy) }
            Text("·")
                .foregroundStyle(.secondary)
            Button("이용약관") { present(.terms, url: ExternalLink.terms) }
        }
        .font(.footnote)
        .frame(minHeight: 44)
    }

    private var policyTitle: String {
        switch policy {
        case .privacy:
            appString("개인정보 처리방침", locale: locale)
        case .terms:
            appString("이용약관", locale: locale)
        case nil:
            ""
        }
    }

    private func present(_ link: PolicyLink, url: URL) {
        policy = link
        ExternalLink.open(url) { linkURL = $0 }
    }

    #if MOCK_DATA
    private func signIn(_ provider: LoginProvider) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await env.signIn(provider)
            } catch {
                failed = true
            }
        }
    }
    #endif
}

private enum PolicyLink {
    case privacy
    case terms
}
