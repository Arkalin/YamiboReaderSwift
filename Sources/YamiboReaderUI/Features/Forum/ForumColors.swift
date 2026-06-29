import SwiftUI

enum ForumColors {
    static let brownDeep = Color(hex: 0x4E2A1B)
    static let brownPrimary = Color(hex: 0x6D3A2B)
    static let brownLight = Color(hex: 0xCCB8A8)
    static let creamBackground = Color(hex: 0xFFF3D6)
    static let creamSurface = Color(hex: 0xFFF7E0)
    static let orangeAccent = Color(hex: 0xF59E2A)
    static let textDark = Color(hex: 0x2E1A0E)
    static let htmlTextDark = Color(hex: 0x6E2B19)
    static let redAccent = Color(hex: 0xFF5656)
    static let pinnedBackground = Color(hex: 0xFFF0C8)
    static let announcementBackground = Color(hex: 0xFFE8B0)
    static let navBarBackground = Color(hex: 0xFFE6B7)
    static let navBarIconUnselected = Color(hex: 0xD29D7C)

    static let border = brownPrimary.opacity(0.18)
    static let secondaryText = brownPrimary.opacity(0.68)
    static let tertiaryText = brownLight
    static let mutedFill = brownPrimary.opacity(0.10)
    static let accentFill = orangeAccent.opacity(0.15)

    static let creamBackgroundHex = "#FFF3D6"
    static let creamSurfaceHex = "#FFF7E0"
    static let htmlTextDarkHex = "#6E2B19"
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension View {
    func forumPageBackground() -> some View {
        background(ForumColors.creamBackground.ignoresSafeArea())
    }

    func forumCardBackground(
        cornerRadius: CGFloat = 8,
        fill: Color = ForumColors.creamSurface
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ForumColors.border, lineWidth: 1)
            }
    }
}
