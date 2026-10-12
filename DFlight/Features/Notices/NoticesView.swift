import SwiftUI

@Observable
final class NoticesViewModel {
    var notices: [Notice] = []
    var loaded = false
    var failed = false

    func load(_ repository: any NoticeRepository) async {
        do {
            notices = visibleNotices(try await repository.notices(), now: Date())
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }
}

struct NoticesView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(NoticeReadStore.self) private var readNotices
    @Environment(\.locale) private var locale
    @State private var model = NoticesViewModel()

    var body: some View {
        Group {
            if !model.loaded {
                ProgressView()
            } else if model.failed {
                ContentUnavailableView {
                    Text("공지를 불러오지 못했습니다")
                }
            } else if model.notices.isEmpty {
                ContentUnavailableView {
                    Text("공지사항이 없습니다")
                }
            } else {
                List(model.notices) { notice in
                    NavigationLink {
                        NoticeDetailView(notice: notice)
                    } label: {
                        noticeRow(notice)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("공지사항")
        .task { await model.load(env.notices) }
    }

    private func noticeRow(_ notice: Notice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized(notice.title, language: languageCode))
                    .font(.body)
                Text(notice.publishedAt.formatted(dateStyle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !readNotices.contains(notice.id) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("읽지 않음")
            }
        }
    }

    private var languageCode: String {
        locale.language.languageCode?.identifier ?? "en"
    }

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
    }
}

private struct NoticeDetailView: View {
    var notice: Notice

    @Environment(NoticeReadStore.self) private var readNotices
    @Environment(\.locale) private var locale
    @State private var blockedURL: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized(notice.title, language: languageCode))
                    .font(.title2.weight(.bold))
                Text(notice.publishedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                bodyText
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("공지")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.openURL, OpenURLAction { url in
            ExternalLink.open(url, blocked: $blockedURL)
            return .handled
        })
        .detailExternalAlert($blockedURL)
        .task { readNotices.markRead(notice.id) }
    }

    private var languageCode: String {
        locale.language.languageCode?.identifier ?? "en"
    }

    private var bodyText: Text {
        let raw = localized(notice.body, language: languageCode)
        if let attributed = try? AttributedString(markdown: raw) {
            return Text(attributed)
        }
        return Text(verbatim: raw)
    }
}
