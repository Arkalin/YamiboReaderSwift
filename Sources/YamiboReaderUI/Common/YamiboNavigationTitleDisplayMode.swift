import SwiftUI

extension View {
    @ViewBuilder
    func yamiboInlineNavigationTitleDisplayMode() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}
