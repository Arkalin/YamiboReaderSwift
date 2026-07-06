import SwiftUI
import YamiboReaderCore

struct ForumThreadRatingResultsRequest: Identifiable, Equatable {
    var threadID: String
    var postID: String

    var id: String {
        "\(threadID)\u{1F}\(postID)"
    }
}

struct ForumThreadRatingResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: ForumThreadRatingResultsPage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let request: ForumThreadRatingResultsRequest
    let load: (String, String) async throws -> ForumThreadRatingResultsPage
    let onUserTap: (String, String?) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && page == nil {
                    ForumThreadReaderLoadingView()
                } else if let errorMessage, page == nil {
                    ForumThreadReaderErrorView(message: errorMessage) {
                        Task {
                            await loadPage()
                        }
                    }
                } else if let page {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.string("forum.thread.rating_participants_format", page.ratings.count))
                                .font(.caption)
                                .foregroundStyle(ForumColors.secondaryText)
                            Spacer(minLength: 0)
                            if let totalScore = page.totalScore {
                                Text(L10n.string("forum.thread.ratings_total_format", totalScore))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ForumColors.orangeAccent)
                            }
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(page.ratings) { rating in
                                    ForumThreadRatingResultRow(rating: rating, onUserTap: openUser)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.string("forum.thread.ratings_all"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if isLoading && page != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
        .task(id: request.id) {
            await loadPage()
        }
    }

    private func loadPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            page = try await load(request.threadID, request.postID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openUser(uid: String, name: String?) {
        dismiss()
        onUserTap(uid, name)
    }
}

private struct ForumThreadRatingResultRow: View {
    let rating: ForumThreadRating
    let onUserTap: (String, String?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let uid = rating.user.uid {
                Button(rating.user.name) {
                    onUserTap(uid, rating.user.name)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForumColors.brownPrimary)
                .frame(maxWidth: 120, alignment: .leading)
            } else {
                Text(rating.user.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.secondaryText)
                    .frame(maxWidth: 120, alignment: .leading)
            }

            Text(rating.scoreText)
                .font(.caption.weight(.bold))
                .foregroundStyle(ForumColors.orangeAccent)
                .frame(width: 48, alignment: .leading)

            Text(rating.reason ?? "")
                .font(.caption)
                .foregroundStyle(ForumColors.textDark)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}
