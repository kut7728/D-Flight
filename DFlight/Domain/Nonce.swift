import CryptoKit
import Foundation
import Security

/// Sign in with Apple용 raw nonce. 문자 집합은 Firebase 안내와 같다.
nonisolated enum Nonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    /// 나머지 연산 편향을 피하려고, 문자 집합 길이보다 작은 바이트만 쓴다.
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "nonce 생성에 실패했습니다")
            for byte in bytes where result.count < length && Int(byte) < charset.count {
                result.append(charset[Int(byte)])
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
