import SwiftUI
import YamiboReaderCore

struct ForumThreadCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let threadID: String
    let postID: String
    let formHash: String?
    let page: Int
    let submit: (String, String, String, String, Int) async throws -> String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(L10n.string("forum.thread.comment_placeholder"))
                                .foregroundStyle(ForumColors.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(L10n.string("forum.thread.comment"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? L10n.string("forum.thread.submitting") : L10n.string("forum.thread.publish")) {
                        submitComment()
                    }
                    .disabled(isSubmitting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
        }
    }

    private func submitComment() {
        guard let formHash else {
            errorMessage = L10n.string("forum.thread.login_info_failed")
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                _ = try await submit(threadID, postID, message, formHash, page)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
