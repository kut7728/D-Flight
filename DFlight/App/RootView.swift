import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.selectedTab) private var selectedTab
    @AppStorage("appLanguage") private var appLanguage = "system"
    @State private var pendingNotice: Notice?
    @State private var didLoadNotice = false

    var body: some View {
        Group {
            if !env.didCheckVersion {
                ProgressView("확인 중")
            } else if let updateURL = env.updateURL {
                ForceUpdateView(appStoreURL: updateURL)
            } else if !env.isSignedIn {
                LoginView()
            } else if env.needsNotificationPrompt {
                NotificationPermissionView()
            } else {
                tabs
            }
        }
        .task {
            await env.checkMinimumVersion()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, env.didCheckVersion else { return }
            Task { await env.checkMinimumVersion() }
        }
    }

    private var tabs: some View {
        TabView(selection: selectedTab) {
            Tab("내 항공편", systemImage: "airplane", value: "myFlights") {
                MyFlightsView()
            }
            Tab("지난 항공편", systemImage: "clock", value: "past") {
                PastFlightsView()
            }
            Tab("설정", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        .task { await loadImportantNotice() }
        .alert(
            "중요 공지",
            isPresented: Binding(
                get: { pendingNotice != nil },
                set: { if !$0 { pendingNotice = nil } }
            ),
            presenting: pendingNotice
        ) { notice in
            Button("확인") {
                env.readNotices.markRead(notice.id)
            }
        } message: { notice in
            Text(Self.noticeMessage(notice, language: AppLocale.languageCode(stored: appLanguage)))
        }
    }

    private func loadImportantNotice() async {
        guard !didLoadNotice else { return }
        let list = (try? await env.notices.notices()) ?? []
        if Task.isCancelled { return }
        didLoadNotice = true
        pendingNotice = visibleNotices(list, now: Date()).first { notice in
            notice.important && !env.readNotices.contains(notice.id)
        }
    }

    private static func noticeMessage(_ notice: Notice, language: String) -> String {
        let title = localized(notice.title, language: language)
        let body = localized(notice.body, language: language)
        if title.isEmpty { return body }
        if body.isEmpty { return title }
        return "\(title)\n\(body)"
    }
}
