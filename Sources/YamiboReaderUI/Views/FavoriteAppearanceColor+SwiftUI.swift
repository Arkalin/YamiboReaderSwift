import SwiftUI
import YamiboReaderCore

extension FavoriteAppearanceColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .pink: .pink
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .cyan: .cyan
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }
}
