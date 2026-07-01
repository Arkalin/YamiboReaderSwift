import SwiftUI

struct ForumTransientMessageView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 420)
            .background(ForumColors.brownDeep, in: Capsule())
            .shadow(color: ForumColors.brownDeep.opacity(0.22), radius: 12, x: 0, y: 6)
    }
}

private struct ForumTransientMessageOverlayModifier: ViewModifier {
    let message: String?
    let bottomPadding: CGFloat
    let clear: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    ForumTransientMessageView(message: message)
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.2)) {
                        clear()
                    }
                }
            }
    }
}

extension View {
    func forumTransientMessage(
        _ message: String?,
        bottomPadding: CGFloat = 24,
        clear: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(ForumTransientMessageOverlayModifier(
            message: message,
            bottomPadding: bottomPadding,
            clear: clear
        ))
    }
}
