import AuthenticationServices
import Foundation
import UIKit

#if !MOCK_DATA
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

@MainActor
final class LiveAccountRepository: AccountRepository {
    private let apple = AppleAuthorizationCoordinator()

    var currentProvider: LoginProvider? {
        guard let user = Auth.auth().currentUser else { return nil }
        let ids = Set(user.providerData.map(\.providerID))
        if ids.contains("apple.com") { return .apple }
        if ids.contains("google.com") { return .google }
        return nil
    }

    // 로그인 화면은 SignInWithAppleButton으로 인증을 띄운 뒤 signInWithApple을 호출한다.
    // signIn(.apple)과 계정 삭제 재인증은 ASAuthorizationController를 직접 띄운다.
    func signIn(_ provider: LoginProvider) async throws {
        switch provider {
        case .apple:
            let rawNonce = Nonce.random()
            let authorization = try await apple.perform(rawNonce: rawNonce)
            let parts = try appleParts(authorization)
            try await signInWithApple(idToken: parts.idToken, rawNonce: rawNonce, fullName: parts.fullName)
        case .google:
            try await signInWithGoogle()
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        try await signIn(credential: credential)
    }

    func signOut() async throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        guard let provider = currentProvider else { throw LiveRepositoryError.unauthenticated }
        if provider == .apple {
            let rawNonce = Nonce.random()
            let authorization = try await apple.perform(rawNonce: rawNonce)
            let parts = try appleParts(authorization)
            try await reauthenticate(idToken: parts.idToken, rawNonce: rawNonce, fullName: parts.fullName)
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: parts.authorizationCode)
            } catch {
                throw LiveRepositoryError.failedPrecondition
            }
        }
        try await LiveBackend.call("deleteAccount")
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        AppLocalData.clear()
    }

    func settings() async throws -> UserSettings {
        do {
            let snapshot = try await userDocument().getDocument()
            guard snapshot.exists, let data = snapshot.data() else { return .default }
            let language = (data["language"] as? String).flatMap(AppLanguage.init(rawValue:)) ?? .system
            return UserSettings(
                language: language,
                notificationsEnabled: data["notificationsEnabled"] as? Bool ?? true,
                liveActivityEnabled: data["liveActivityEnabled"] as? Bool ?? true
            )
        } catch let error as LiveRepositoryError {
            throw error
        } catch {
            throw mapBackendError(error)
        }
    }

    func updateSettings(_ settings: UserSettings) async throws {
        let device = Locale.current.language.languageCode?.identifier ?? ""
        try await LiveBackend.call("updateSettings", data: [
            "language": settings.language.rawValue,
            "pushLanguage": pushLanguage(appLanguage: settings.language, deviceLanguageCode: device),
            "notificationsEnabled": settings.notificationsEnabled,
        ])
    }

    private func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw LiveRepositoryError.signInFailed
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = topViewController() else { throw LiveRepositoryError.signInFailed }
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            throw LiveRepositoryError.cancelled
        } catch {
            throw LiveRepositoryError.signInFailed
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw LiveRepositoryError.signInFailed
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        try await signIn(credential: credential)
    }

    private func signIn(credential: AuthCredential) async throws {
        do {
            _ = try await Auth.auth().signIn(with: credential)
        } catch let error as LiveRepositoryError {
            throw error
        } catch {
            throw LiveRepositoryError.signInFailed
        }
    }

    private func reauthenticate(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        guard let user = Auth.auth().currentUser else { throw LiveRepositoryError.unauthenticated }
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        do {
            _ = try await user.reauthenticate(with: credential)
        } catch {
            throw LiveRepositoryError.signInFailed
        }
    }

    private func userDocument() throws -> DocumentReference {
        guard let uid = Auth.auth().currentUser?.uid else { throw LiveRepositoryError.unauthenticated }
        return Firestore.firestore().collection("users").document(uid)
    }
}

private struct AppleParts {
    var idToken: String
    var authorizationCode: String
    var fullName: PersonNameComponents?
}

private func appleParts(_ authorization: ASAuthorization) throws -> AppleParts {
    guard
        let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = apple.identityToken,
        let idToken = String(data: tokenData, encoding: .utf8),
        let codeData = apple.authorizationCode,
        let code = String(data: codeData, encoding: .utf8)
    else {
        throw LiveRepositoryError.signInFailed
    }
    return AppleParts(idToken: idToken, authorizationCode: code, fullName: apple.fullName)
}

@MainActor
private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    func perform(rawNonce: String) async throws -> ASAuthorization {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256(rawNonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        finish(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(.failure(LiveRepositoryError.cancelled))
        } else {
            finish(.failure(LiveRepositoryError.signInFailed))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyWindow() ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let continuation = continuation
        self.continuation = nil
        controller = nil
        continuation?.resume(with: result)
    }
}

private enum AppLocalData {
    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "appearance")
        defaults.removeObject(forKey: "appLanguage")
        defaults.removeObject(forKey: "selectedTab")
        defaults.removeObject(forKey: AppEnvironment.notificationPromptKey)
        defaults.removeObject(forKey: NoticeReadStore.storageKey)
    }
}

@MainActor
private func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
}

@MainActor
private func topViewController() -> UIViewController? {
    var controller = keyWindow()?.rootViewController
    while let presented = controller?.presentedViewController {
        controller = presented
    }
    return controller
}
#endif
