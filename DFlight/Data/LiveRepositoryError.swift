import Foundation

/// api-spec §1 호출 오류. 화면은 이 값으로 안내를 고른다.
enum LiveRepositoryError: Error, Equatable {
    case unauthenticated
    case invalidArgument
    case notFound
    case alreadyExists
    case permissionDenied
    case resourceExhausted
    case unavailable
    case failedPrecondition
    case notYetAvailable
    case cancelled
    case signInFailed
}

/// api-spec §1 코드 중 화면이 문구를 가리는 것.
nonisolated enum FlightUserMessage: Equatable, Sendable {
    case unavailable
    case retrySoon
    case searchAgain
    case invalidInput
}

nonisolated func flightUserMessage(for error: Error, notFoundIsSearchAgain: Bool = false) -> FlightUserMessage {
    guard let live = error as? LiveRepositoryError else { return .unavailable }
    switch live {
    case .resourceExhausted:
        return .retrySoon
    case .invalidArgument:
        return .invalidInput
    case .notFound:
        return notFoundIsSearchAgain ? .searchAgain : .unavailable
    default:
        return .unavailable
    }
}

/// Functions·Firestore가 공유하는 gRPC 코드.
nonisolated func repositoryError(forFunctionsCode code: Int) -> LiveRepositoryError? {
    switch code {
    case 1: .cancelled
    case 3: .invalidArgument
    case 5: .notFound
    case 6: .alreadyExists
    case 7: .permissionDenied
    case 8: .resourceExhausted
    case 9: .failedPrecondition
    case 14: .unavailable
    case 16: .unauthenticated
    default: nil
    }
}
