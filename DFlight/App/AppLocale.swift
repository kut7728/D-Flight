import Foundation

/// `@AppStorage("appLanguage")` 값 `system` / `ko` / `ja` / `en`.
enum AppLocale {
    static func resolved(stored: String) -> Locale? {
        switch stored {
        case "ko": return Locale(identifier: "ko")
        case "ja": return Locale(identifier: "ja")
        case "en": return Locale(identifier: "en")
        default:
            let code = Locale.current.language.languageCode?.identifier
            if code == "ko" || code == "ja" || code == "en" { return nil }
            return Locale(identifier: "en")
        }
    }

    static func languageCode(stored: String) -> String {
        if stored == "ko" || stored == "ja" || stored == "en" { return stored }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return (code == "ko" || code == "ja" || code == "en") ? code : "en"
    }
}

/// 서버 푸시 언어. `system`이면 기기 언어, 지원하지 않으면 영어.
nonisolated func pushLanguage(appLanguage: AppLanguage, deviceLanguageCode: String) -> String {
    switch appLanguage {
    case .ko, .ja, .en:
        return appLanguage.rawValue
    case .system:
        if deviceLanguageCode == "ko" || deviceLanguageCode == "ja" || deviceLanguageCode == "en" {
            return deviceLanguageCode
        }
        return "en"
    }
}

/// `String(localized:locale:)`는 번들 선호 언어만 본다. 앱에서 고른 로케일의 lproj를 직접 읽는다.
nonisolated func appString(_ key: String, locale: Locale) -> String {
    let code = locale.language.languageCode?.identifier ?? "ko"
    guard
        let path = Bundle.main.path(forResource: code, ofType: "lproj"),
        let bundle = Bundle(path: path)
    else { return key }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
