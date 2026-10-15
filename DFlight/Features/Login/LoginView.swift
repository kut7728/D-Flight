import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var isWorking = false
    @State private var failed = false
    #if !MOCK_DATA
    @State private var appleNonce = ""
    #endif
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
            let nonce = Nonce.random()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Nonce.sha256(nonce)
        } onCompletion: { result in
            handleApple(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .disabled(isWorking)
        #endif
    }

    private var googleButton: some View {
        Button {
            signIn(.google)
        } label: {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text("Google로 계속하기")
                    .font(.headline)
            }
            .foregroundStyle(googleForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(googleBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(googleStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private var googleBackground: Color {
        colorScheme == .dark
            ? Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255)
            : .white
    }

    private var googleStroke: Color {
        colorScheme == .dark
            ? Color(red: 142 / 255, green: 145 / 255, blue: 143 / 255)
            : Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255)
    }

    private var googleForeground: Color {
        colorScheme == .dark
            ? Color(red: 227 / 255, green: 227 / 255, blue: 227 / 255)
            : Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
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

    private func signIn(_ provider: LoginProvider) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            await run {
                try await env.signIn(provider)
            }
        }
    }

    #if !MOCK_DATA
    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            failed = true
        case .success(let authorization):
            guard
                let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = apple.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                !appleNonce.isEmpty
            else {
                failed = true
                return
            }
            guard !isWorking else { return }
            isWorking = true
            let nonce = appleNonce
            let fullName = apple.fullName
            Task {
                defer { isWorking = false }
                await run {
                    try await env.signInWithApple(idToken: idToken, rawNonce: nonce, fullName: fullName)
                }
            }
        }
    }
    #endif

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch LiveRepositoryError.cancelled {
        } catch {
            failed = true
        }
    }
}

private enum PolicyLink {
    case privacy
    case terms
}
