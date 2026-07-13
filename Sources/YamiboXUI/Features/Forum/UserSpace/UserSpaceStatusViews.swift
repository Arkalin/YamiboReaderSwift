import SwiftUI
import YamiboXCore

struct UserSpaceLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("common.loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct UserSpaceErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("common.load_failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.string("common.retry"), action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct UserSpaceEmptyView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(message, systemImage: "tray")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
    }
}
