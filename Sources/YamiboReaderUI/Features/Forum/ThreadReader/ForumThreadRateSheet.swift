import SwiftUI
import YamiboReaderCore

struct ForumThreadRateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var options: ForumThreadRateOptionsPage?
    @State private var scoreText = ""
    @State private var reason = ""
    @State private var noticeAuthor = false
    @State private var isLoadingOptions = false
    @State private var isSubmitting = false
    @State private var hintMessage: String?
    @State private var errorMessage: String?

    let threadID: String
    let postID: String
    let formHash: String?
    let loadOptions: (String, String) async throws -> ForumThreadRateOptionsPage
    let submit: (String, String, Int, String, String, Bool) async throws -> String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("forum.thread.rate_score"), text: $scoreText)

                    if let options, !options.availableScores.isEmpty {
                        Menu(L10n.string("forum.thread.rate_score_options")) {
                            ForEach(options.availableScores, id: \.self) { score in
                                Button(String(score)) {
                                    scoreText = String(score)
                                }
                            }
                        }
                    }

                    TextField(L10n.string("forum.thread.rate_reason"), text: $reason, axis: .vertical)
                        .lineLimit(3 ... 5)

                    if let options, !options.defaultReasons.isEmpty {
                        Menu(L10n.string("forum.thread.rate_reason_options")) {
                            ForEach(options.defaultReasons, id: \.self) { value in
                                Button(value) {
                                    reason = value
                                }
                            }
                        }
                    }

                    Toggle(L10n.string("forum.thread.rate_notice_author"), isOn: $noticeAuthor)
                }

                if let hintMessage {
                    Section {
                        Text(hintMessage)
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.string("forum.thread.ratings"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? L10n.string("forum.thread.submitting") : L10n.string("forum.thread.submit")) {
                        submitRate()
                    }
                    .disabled(isSubmitting || scoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isLoadingOptions || isSubmitting {
                    ProgressView()
                }
            }
        }
        .task(id: "\(threadID)-\(postID)") {
            await loadRateOptions()
        }
    }

    private func loadRateOptions() async {
        isLoadingOptions = true
        hintMessage = L10n.string("forum.thread.rate_loading_options")
        defer { isLoadingOptions = false }

        do {
            options = try await loadOptions(threadID, postID)
            hintMessage = nil
        } catch {
            hintMessage = L10n.string("forum.thread.rate_options_failed")
        }
    }

    private func submitRate() {
        guard let score = Int(scoreText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = L10n.string("forum.thread.rate_score_invalid")
            return
        }
        guard let formHash else {
            errorMessage = L10n.string("forum.thread.login_info_failed")
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                _ = try await submit(threadID, postID, score, reason, formHash, noticeAuthor)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
