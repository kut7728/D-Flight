import Foundation

/// 앱 번들을 찾기 위한 표식. 기본 격리가 MainActor여도 파일 로드는 격리되지 않는다.
nonisolated private final class AirportCatalogBundleToken: NSObject {}

/// 번들의 airports.json. 네트워크를 쓰지 않는다.
nonisolated enum AirportCatalog {

    private struct Row: Decodable {
        var code: String
        var nameKo: String
        var nameJa: String
        var nameEn: String
        var city: String
        var country: String
        var timeZone: String
        var terminals: [String]
        var mapURL: String?
    }

    private struct Entry {
        var airport: Airport
        var codeFold: String
        var folds: [String]
        var rank: Int
    }

    private struct Snapshot {
        var index: [String: Airport]
        var entries: [Entry]
        var emptyOrder: [Airport]
    }

    private static let snapshot = load()
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func airport(code: String) -> Airport? {
        snapshot.index[normalize(code)]
    }

    /// 빈 검색은 한국, 일본, 그 밖 순서. 그 외에는 코드 접두 일치가 이름·도시보다 앞이다.
    static func search(_ query: String, limit: Int = 50) -> [Airport] {
        guard limit > 0 else { return [] }
        let folded = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if folded.isEmpty {
            return Array(snapshot.emptyOrder.prefix(limit))
        }
        var codes: [Airport] = []
        var names: [Airport] = []
        for entry in snapshot.entries {
            if entry.codeFold.hasPrefix(folded) {
                codes.append(entry.airport)
                if codes.count >= limit { break }
            } else if entry.folds.contains(where: { $0.contains(folded) }) {
                names.append(entry.airport)
            }
        }
        if codes.count >= limit {
            return codes
        }
        return Array((codes + names).prefix(limit))
    }

    private static func load() -> Snapshot {
        guard let url = Bundle(for: AirportCatalogBundleToken.self).url(forResource: "airports", withExtension: "json")
            ?? Bundle.main.url(forResource: "airports", withExtension: "json") else {
            preconditionFailure("airports.json을 찾지 못했습니다")
        }
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("airports.json을 읽지 못했습니다")
        }
        let entries = rows.map { row in
            let airport = Airport(
                code: row.code,
                nameKo: row.nameKo,
                nameJa: row.nameJa,
                nameEn: row.nameEn,
                timeZone: row.timeZone,
                terminals: row.terminals,
                mapURL: row.mapURL.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                korean: row.country == "KR"
            )
            return Entry(
                airport: airport,
                codeFold: fold(row.code),
                folds: [fold(row.nameKo), fold(row.nameJa), fold(row.nameEn), fold(row.city)],
                rank: row.country == "KR" ? 0 : row.country == "JP" ? 1 : 2
            )
        }
        let index = Dictionary(uniqueKeysWithValues: entries.map { ($0.airport.code, $0.airport) })
        let emptyOrder = entries.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? lhs.airport.code < rhs.airport.code : lhs.rank < rhs.rank
        }.map(\.airport)
        return Snapshot(index: index, entries: entries, emptyOrder: emptyOrder)
    }

    private static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: posix)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: posix)
    }
}
