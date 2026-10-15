import Foundation

#if !MOCK_DATA
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum LiveBackend {
    static let region = "asia-northeast3"

    @discardableResult
    static func call(_ name: String, data: [String: any Sendable] = [:]) async throws -> Any {
        do {
            let result = try await Functions.functions(region: region).httpsCallable(name).call(data)
            return result.data
        } catch {
            let mapped = mapBackendError(error)
            if let live = mapped as? LiveRepositoryError, live == .unauthenticated {
                try? Auth.auth().signOut()
            }
            throw mapped
        }
    }
}

func mapBackendError(_ error: Error) -> Error {
    let nsError = error as NSError
    guard nsError.domain == FunctionsErrorDomain || nsError.domain == FirestoreErrorDomain else {
        return error
    }
    return repositoryError(forFunctionsCode: nsError.code) ?? error
}
#endif
