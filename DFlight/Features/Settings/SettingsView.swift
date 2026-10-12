import SwiftUI
import UIKit
import UserNotifications

@Observable
final class SettingsViewModel {
    var settings = UserSettings.default
    var loaded = false
    var notificationsDenied = false
    var notices: [Notice] = []
    var errorMessage: String?
    private var saveGeneration = 0
    private var saveQueued = false

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func load(account: any AccountRepository, notices: any NoticeRepository, language: AppLanguage, locale: Locale) async {
        do {
            var value = try await account.settings()
            value.language = language
            settings = value
            loaded = true
        } catch {
            errorMessage = appString("설정을 불러오지 못했습니다", locale: locale)
        }
        if let list = try? await notices.notices() {
            self.notices = visibleNotices(list, now: Date())
        }
        if loaded, saveQueued {
            saveQueued = false
            await save(account: account, language: language, locale: locale)
        }
        await refreshPermission()
    }

    func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }

    func save(account: any AccountRepository, language: AppLanguage, locale: Locale) async {
        settings.language = language
        guard loaded else {
            saveQueued = true
            return
        }
        saveGeneration += 1
        let ticket = saveGeneration
        let snapshot = settings
        try? await Task.sleep(for: .milliseconds(250))
        guard ticket == saveGeneration else { return }
        do {
            try await account.updateSettings(snapshot)
        } catch {
            errorMessage = appString("설정을 저장하지 못했습니다", locale: locale)
        }
    }

    func signOut(_ env: AppEnvironment, locale: Locale) async {
        do {
            try await env.signOut()
        } catch {
            errorMessage = appString("로그아웃하지 못했습니다", locale: locale)
        }
    }

    func deleteAccount(_ env: AppEnvironment, locale: Locale) async {
        do {
            try await env.deleteAccount()
        } catch {
            errorMessage = appString("계정을 삭제하지 못했습니다", locale: locale)
        }
    }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(NoticeReadStore.self) private var readNotices
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("appLanguage") private var appLanguage = "system"

    @State private var model = SettingsViewModel()
    @State private var confirmDelete = false
    @State private var blockedURL: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("화면 · 언어") {
                    Picker("화면 모드", selection: $appearance) {
                        Text("시스템").tag("system")
                        Text("라이트").tag("light")
                        Text("다크").tag("dark")
                    }
                    .pickerStyle(.menu)
                    Picker("언어", selection: $appLanguage) {
                        Text("기기 언어 따르기").tag("system")
                        Text(verbatim: "한국어").tag("ko")
                        Text(verbatim: "日本語").tag("ja")
                        Text(verbatim: "English").tag("en")
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    Toggle("앱 알림", isOn: notificationsBinding)
                        .disabled(!model.loaded)
                    if model.notificationsDenied {
                        Button("설정 앱에서 켜기") { openSystemSettings() }
                    }
                } header: {
                    Text("알림")
                } footer: {
                    Text("항공편별 알림은 각 항공편 상세 화면의 알림 버튼에서 켜고 끕니다. 시점은 출발 24시간·3시간·40분 전으로 고정되어 있습니다.")
                }
                Section("잠금 화면") {
                    Toggle("Live Activity 자동 시작", isOn: liveActivityBinding)
                }
                .disabled(!model.loaded)
                Section("일반") {
                    NavigationLink {
                        NoticesView()
                    } label: {
                        HStack {
                            Text("공지사항")
                            Spacer()
                            if hasUnread {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .accessibilityLabel("읽지 않은 공지")
                            }
                        }
                    }
                }
                Section("계정") {
                    LabeledContent("로그인 방식") {
                        providerLabel
                    }
                    if env.isSignedIn {
                        Button("로그아웃") {
                            Task { await model.signOut(env, locale: locale) }
                        }
                        Button("계정 삭제", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
                Section("정보") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("데이터 출처")
                        Text("인천국제공항공사, 한국공항공사 (공공데이터포털)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("자동 정보 지원 공항")
                        Text("자동 정보는 한국 공항만 제공됩니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("개인정보 처리방침") { open(ExternalLink.privacy) }
                    Button("이용약관") { open(ExternalLink.terms) }
                    Button("문의하기") { open(SettingsDocument.contact) }
                    LabeledContent("앱 버전", value: model.version)
                        .monospacedDigit()
                }
            }
            .tint(Color.accentColor)
            .navigationTitle("설정")
            .task {
                await model.load(
                    account: env.account,
                    notices: env.notices,
                    language: selectedLanguage,
                    locale: locale
                )
            }
            .onChange(of: appLanguage) { _, _ in
                Task { await model.save(account: env.account, language: selectedLanguage, locale: locale) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.refreshPermission() }
            }
            .alert("계정 삭제", isPresented: $confirmDelete) {
                Button("삭제", role: .destructive) {
                    Task { await model.deleteAccount(env, locale: locale) }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("등록한 항공편과 설정이 모두 삭제되며 되돌릴 수 없습니다.")
            }
            .alert(
                "오류",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .detailExternalAlert($blockedURL)
        }
    }

    private var hasUnread: Bool {
        model.notices.contains { !readNotices.contains($0.id) }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .system
    }

    @ViewBuilder
    private var providerLabel: some View {
        switch env.account.currentProvider {
        case .apple:
            Text(verbatim: "Apple")
        case .google:
            Text(verbatim: "Google")
        case nil:
            Text("로그인되지 않음")
        }
    }

    private var liveActivityBinding: Binding<Bool> {
        Binding(
            get: { model.settings.liveActivityEnabled },
            set: { newValue in
                model.settings.liveActivityEnabled = newValue
                Task { await model.save(account: env.account, language: selectedLanguage, locale: locale) }
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.notificationsEnabled },
            set: { newValue in
                model.settings.notificationsEnabled = newValue
                Task { await model.save(account: env.account, language: selectedLanguage, locale: locale) }
            }
        )
    }

    private func open(_ url: URL) {
        ExternalLink.open(url, blocked: $blockedURL)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        open(url)
    }
}

/// 개인정보 처리방침·이용약관·문의 주소는 M9에서 확정한다.
private enum SettingsDocument {
    static let privacy = URL(string: "https://example.com/dflight/privacy")!
    static let terms = URL(string: "https://example.com/dflight/terms")!
    static let contact = URL(string: "mailto:support@example.com")!
}
