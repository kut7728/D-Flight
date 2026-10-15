import Foundation
import Testing
@testable import DFlight

@Suite("로그인 보조 로직")
struct AuthLogicTests {
    @Test("SHA256은 알려진 값과 같고, nonce는 32자 문자 집합 안이다")
    func nonceAndHash() {
        #expect(Nonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Nonce.sha256("abc") == Nonce.sha256("abc"))
        let nonce = Nonce.random()
        #expect(nonce.count == 32)
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        #expect(nonce.allSatisfy { allowed.contains($0) })
        #expect(Nonce.random() != nonce)
    }

    @Test("pushLanguage는 앱 언어를 우선하고, 기기 언어가 지원 밖이면 영어다")
    func pushLanguageResolution() {
        #expect(pushLanguage(appLanguage: .ko, deviceLanguageCode: "en") == "ko")
        #expect(pushLanguage(appLanguage: .ja, deviceLanguageCode: "ko") == "ja")
        #expect(pushLanguage(appLanguage: .en, deviceLanguageCode: "ko") == "en")
        #expect(pushLanguage(appLanguage: .system, deviceLanguageCode: "ja") == "ja")
        #expect(pushLanguage(appLanguage: .system, deviceLanguageCode: "fr") == "en")
        #expect(pushLanguage(appLanguage: .system, deviceLanguageCode: "") == "en")
    }

    @Test("서버 함수 gRPC 코드를 api-spec 오류로 바꾼다")
    func functionsCodes() {
        #expect(repositoryError(forFunctionsCode: 16) == .unauthenticated)
        #expect(repositoryError(forFunctionsCode: 3) == .invalidArgument)
        #expect(repositoryError(forFunctionsCode: 5) == .notFound)
        #expect(repositoryError(forFunctionsCode: 6) == .alreadyExists)
        #expect(repositoryError(forFunctionsCode: 7) == .permissionDenied)
        #expect(repositoryError(forFunctionsCode: 8) == .resourceExhausted)
        #expect(repositoryError(forFunctionsCode: 14) == .unavailable)
        #expect(repositoryError(forFunctionsCode: 9) == .failedPrecondition)
        #expect(repositoryError(forFunctionsCode: 1) == .cancelled)
        #expect(repositoryError(forFunctionsCode: 2) == nil)
    }
}
