import Foundation
import Observation

/// 공지 읽음 여부. 기기에만 저장한다. 설정 공지 화면은 `@Environment(NoticeReadStore.self)`로 쓴다.
@MainActor
@Observable
final class NoticeReadStore {
    private static let storageKey = "readNoticeIDs"

    private(set) var ids: Set<String>

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? [])
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func markRead(_ id: String) {
        var next = ids
        next.insert(id)
        ids = next
        UserDefaults.standard.set(next.sorted(), forKey: Self.storageKey)
    }

    func removeAll() {
        ids = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}
