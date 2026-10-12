import SwiftUI
import UserNotifications

struct NotificationPermissionView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color("AccentColor"))
                .accessibilityHidden(true)
            Text("게이트가 바뀌면 바로 알려 드릴게요")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                bullet("출발 시각 변경·결항")
                bullet("터미널·게이트 변경")
                bullet("출발 24시간·3시간 전")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Button("알림 허용", action: allow)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            Button("나중에") {
                env.finishNotificationPrompt()
            }
            .font(.body)
            .foregroundStyle(Color("AccentColor"))
            .frame(minHeight: 44)
        }
        .padding(24)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·")
            Text(text)
        }
        .font(.body)
    }

    private func allow() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            Task { @MainActor in
                env.finishNotificationPrompt()
            }
        }
    }
}
