import SwiftUI

#if !MOCK_DATA
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore

enum FirebaseBootstrap {
    /// 성공하면 Firebase가 준비된 것이다. plist가 없으면 false. configure는 하지 않는다.
    static func configure() -> Bool {
        if FirebaseApp.app() != nil { return true }
        guard let path = plistPath(), let options = FirebaseOptions(contentsOfFile: path) else {
            return false
        }
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(ReleaseAppCheckFactory())
        #endif
        FirebaseApp.configure(options: options)
        var settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        return true
    }

    private static func plistPath() -> String? {
        let bundle = Bundle.main
        if let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist") {
            return path
        }
        return bundle.path(forResource: "GoogleService-Info", ofType: "plist", inDirectory: "Config")
    }
}

private final class ReleaseAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        AppAttestProvider(app: app)
    }
}

struct FirebaseConfigMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Firebase 설정을 찾을 수 없습니다", systemImage: "exclamationmark.triangle")
        } description: {
            Text("DFlight/Config/GoogleService-Info.plist가 없습니다")
        }
        .padding()
    }
}
#endif
