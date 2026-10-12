import SwiftUI

@main
struct DFlightApp: App {
    #if MOCK_DATA
    @State private var appEnvironment = AppEnvironment.mock()
    #endif

    var body: some Scene {
        WindowGroup {
            root
                .modifier(RootChrome())
        }
    }

    @ViewBuilder
    private var root: some View {
        #if MOCK_DATA
        RootView()
            .environment(appEnvironment)
            .environment(appEnvironment.readNotices)
        #else
        LivePlaceholderView()
        #endif
    }
}

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
