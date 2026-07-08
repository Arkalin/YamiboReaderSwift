#if os(iOS)
import UIKit

/// Captures a frozen snapshot of the currently visible screen, used as
/// `ImageBrowserView.backgroundRevealImage` so an interactive swipe-down-to-dismiss appears to
/// peel away to the page underneath instead of fading to black.
@MainActor
enum ImageBrowserBackgroundSnapshot {
    static func capture() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}
#endif
