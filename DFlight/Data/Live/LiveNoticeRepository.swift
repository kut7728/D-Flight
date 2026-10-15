import Foundation

#if !MOCK_DATA
import FirebaseFirestore

@MainActor
final class LiveNoticeRepository: NoticeRepository {
    func notices() async throws -> [Notice] {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("notices")
                .whereField("publishedAt", isLessThanOrEqualTo: Timestamp(date: Date()))
                .order(by: "publishedAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            return snapshot.documents.compactMap(Self.notice(from:))
        } catch let error as LiveRepositoryError {
            throw error
        } catch {
            throw mapBackendError(error)
        }
    }

    /// 실패·오프라인이면 nil. 앱을 막지 않는다.
    func minimumVersion() async -> (version: String, appStoreURL: URL)? {
        do {
            let snapshot = try await Firestore.firestore().collection("config").document("app").getDocument()
            guard let data = snapshot.data(),
                  let version = data["minimumVersion"] as? String,
                  let urlString = data["appStoreUrl"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return (version, url)
        } catch {
            return nil
        }
    }

    private static func notice(from document: QueryDocumentSnapshot) -> Notice? {
        let data = document.data()
        guard let publishedAt = date(data["publishedAt"]) else { return nil }
        return Notice(
            id: document.documentID,
            title: stringMap(data["title"]),
            body: stringMap(data["body"]),
            important: data["important"] as? Bool ?? false,
            publishedAt: publishedAt,
            expiresAt: date(data["expiresAt"])
        )
    }

    private static func stringMap(_ value: Any?) -> [String: String] {
        guard let map = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for key in ["ko", "ja", "en"] {
            if let text = map[key] as? String { result[key] = text }
        }
        return result
    }

    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}
#endif
