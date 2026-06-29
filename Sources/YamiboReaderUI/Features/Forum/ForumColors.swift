import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ForumColors {
    static let brownDeep = Color(light: 0x4E2A1B, dark: 0x24120C)
    static let brownPrimary = Color(light: 0x6D3A2B, dark: 0xD6A083)
    static let brownLight = Color(light: 0xCCB8A8, dark: 0x8F6F5E)
    static let creamBackground = Color(light: 0xFFF3D6, dark: 0x17110D)
    static let creamSurface = Color(light: 0xFFF7E0, dark: 0x241B15)
    static let orangeAccent = Color(light: 0xF59E2A, dark: 0xF0A33A)
    static let textDark = Color(light: 0x2E1A0E, dark: 0xF4E7D1)
    static let htmlTextDark = Color(light: 0x6E2B19, dark: 0xF0D8BC)
    static let redAccent = Color(light: 0xFF5656, dark: 0xFF7A70)
    static let pinnedBackground = Color(light: 0xFFF0C8, dark: 0x302416)
    static let announcementBackground = Color(light: 0xFFE8B0, dark: 0x382711)
    static let navBarBackground = Color(light: 0xFFE6B7, dark: 0x21150F)
    static let navBarIconUnselected = Color(light: 0xD29D7C, dark: 0xA97B63)

    static let border = brownPrimary.opacity(0.18)
    static let secondaryText = brownPrimary.opacity(0.68)
    static let tertiaryText = brownLight
    static let mutedFill = brownPrimary.opacity(0.10)
    static let accentFill = orangeAccent.opacity(0.15)

    static func navigationBarBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(hex: 0x24120C)
        case .light:
            Color(hex: 0x4E2A1B)
        @unknown default:
            Color(hex: 0x4E2A1B)
        }
    }

}

private extension Color {
    init(light lightHex: UInt32, dark darkHex: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex)
        })
        #else
        self.init(hex: lightHex)
        #endif
    }

    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#if os(iOS)
extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
#elseif os(macOS)
extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
#endif

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
