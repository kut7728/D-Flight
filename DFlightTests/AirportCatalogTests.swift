import Foundation
import Testing
@testable import DFlight

@Suite("공항 기본 데이터")
struct AirportCatalogTests {
    @Test("코드로 찾고, 없는 코드는 nil")
    func lookup() {
        let icn = AirportCatalog.airport(code: " icn ")
        #expect(icn?.code == "ICN")
        #expect(icn?.nameKo == "인천")
        #expect(icn?.nameJa == "仁川")
        #expect(icn?.nameEn == "Incheon")
        #expect(icn?.timeZone == "Asia/Seoul")
        #expect(icn?.terminals == ["T1", "T2"])
        #expect(icn?.mapURL?.absoluteString == "https://www.airport.kr/geomap/ap_en/view.do?type=2&alertType=0&tmnlId=P01")

        #expect(AirportCatalog.airport(code: "GMP")?.terminals == [])
        #expect(AirportCatalog.airport(code: "GMP")?.mapURL != nil)
        #expect(AirportCatalog.airport(code: "HND")?.terminals == ["T1", "T2", "T3"])
        #expect(AirportCatalog.airport(code: "NRT")?.terminals == ["T1", "T2", "T3"])
        #expect(AirportCatalog.airport(code: "KIX")?.terminals == ["T1", "T2"])
        #expect(AirportCatalog.airport(code: "PUS")?.terminals == [])
        #expect(AirportCatalog.airport(code: "PUS")?.mapURL == nil)

        let den = AirportCatalog.airport(code: "DEN")
        #expect(den?.nameKo == den?.nameEn)
        #expect(den?.nameJa == den?.nameEn)
        #expect(den?.terminals == [])
        #expect(den?.mapURL == nil)
        #expect(AirportCatalog.airport(code: "NOPE") == nil)
    }

    @Test("검색은 코드 접두 다음 이름·도시. 빈 검색은 한·일 공항이 앞")
    func search() {
        #expect(AirportCatalog.search("ICN").first?.code == "ICN")
        #expect(AirportCatalog.search("인천").contains { $0.code == "ICN" })
        #expect(AirportCatalog.search("羽田").contains { $0.code == "HND" })
        #expect(AirportCatalog.search("haneda").contains { $0.code == "HND" })
        #expect(AirportCatalog.search("로스앤젤레스").contains { $0.code == "LAX" })
        #expect(AirportCatalog.search("sao paulo").contains { $0.code == "GRU" })
        #expect(AirportCatalog.search("São Paulo").contains { $0.code == "GRU" })
        #expect(AirportCatalog.search("zzzqqq").isEmpty)
        #expect(AirportCatalog.search("ICN", limit: 0).isEmpty)
        #expect(AirportCatalog.search("A", limit: 3).count == 3)

        let prefixed = AirportCatalog.search("OS", limit: 80)
        let split = prefixed.firstIndex { !$0.code.hasPrefix("OS") } ?? prefixed.count
        #expect(prefixed.prefix(split).allSatisfy { $0.code.hasPrefix("OS") })
        #expect(prefixed.dropFirst(split).allSatisfy { !$0.code.hasPrefix("OS") })

        let ranked = AirportCatalog.search("", limit: 20_000)
        let icn = ranked.firstIndex { $0.code == "ICN" }
        let hnd = ranked.firstIndex { $0.code == "HND" }
        let bkk = ranked.firstIndex { $0.code == "BKK" }
        #expect(ranked.count > 1000)
        #expect(icn != nil && hnd != nil && bkk != nil)
        #expect(icn! < hnd!)
        #expect(hnd! < bkk!)
        #expect(AirportCatalog.search("", limit: 50).count == 50)
    }
}
