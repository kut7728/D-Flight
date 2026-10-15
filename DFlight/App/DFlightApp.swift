import SwiftUI

#if !MOCK_DATA
import GoogleSignIn
#endif

@main
struct DFlightApp: App {
    #if MOCK_DATA
    @State private var appEnvironment = AppEnvironment.mock()
    #else
    @State private var launch = LiveLaunch()
    #endif

    var body: some Scene {
        WindowGroup {
            root
                .modifier(RootChrome())
                #if !MOCK_DATA
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                #endif
        }
    }

    @ViewBuilder
    private var root: some View {
        #if MOCK_DATA
        RootView()
            .environment(appEnvironment)
            .environment(appEnvironment.readNotices)
        #else
        if let environment = launch.environment {
            RootView()
                .environment(environment)
                .environment(environment.readNotices)
        } else {
            FirebaseConfigMissingView()
        }
        #endif
    }
}

#if !MOCK_DATA
@MainActor
private final class LiveLaunch {
    let environment: AppEnvironment?

    init() {
        if FirebaseBootstrap.configure() {
            environment = AppEnvironment.live()
        } else {
            environment = nil
        }
    }
}
#endif

private struct RootChrome: ViewModifier {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("selectedTab") private var selectedTab = "myFlights"

    func body(content: Content) -> some View {
        content
            .id(appLanguage)
            .environment(\.selectedTab, $selectedTab)
            .environment(\.locale, AppLocale.resolved(stored: appLanguage) ?? .current)
            .onAppear { AppearanceController.apply(appearance) }
            .onChange(of: appearance) { _, value in
                AppearanceController.apply(value)
            }
    }
}

extension EnvironmentValues {
    @Entry var selectedTab: Binding<String> = .constant("myFlights")
}
