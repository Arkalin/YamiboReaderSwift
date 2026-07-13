import SwiftUI
import YamiboXCore

struct ForumContentLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("common.loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

struct ForumContentErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ForumColors.orangeAccent)
            Text(message)
                .font(.body)
                .foregroundStyle(ForumColors.textDark)
                .multilineTextAlignment(.center)
            Button {
                retry()
            } label: {
                Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .forumCardBackground()
    }
}
