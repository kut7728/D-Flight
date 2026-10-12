import UIKit

/// `@AppStorage("appearance")` 값 `system` / `light` / `dark`를 창 전체에 0.4초 크로스페이드로 적용한다.
@MainActor
enum AppearanceController {
    static func apply(_ raw: String, retry: Bool = true) {
        let style = interfaceStyle(for: raw)
        guard let window = keyWindow else {
            guard retry else { return }
            DispatchQueue.main.async { apply(raw, retry: false) }
            return
        }
        guard window.overrideUserInterfaceStyle != style else { return }
        UIView.transition(with: window, duration: 0.4, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            window.overrideUserInterfaceStyle = style
        }
    }

    private static func interfaceStyle(for raw: String) -> UIUserInterfaceStyle {
        switch raw {
        case "light": .light
        case "dark": .dark
        default: .unspecified
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
