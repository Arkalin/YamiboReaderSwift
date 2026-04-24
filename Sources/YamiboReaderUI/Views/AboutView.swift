import SwiftUI
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AppIconView()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                    .padding(.top, 48)

                Text(AppMetadata.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppMetadata.versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .navigationTitle(L10n.string("about.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum AppMetadata {
    static var displayName: String {
        let bundle = Bundle.main
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "YamiboReader"
    }

    static var versionText: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?) where version != build:
            return L10n.string("about.version_with_build", version, build)
        case let (version?, _):
            return L10n.string("about.version", version)
        case let (_, build?):
            return L10n.string("about.version", build)
        case (nil, nil):
            return L10n.string("about.version", "--")
        }
    }
}

private struct AppIconView: View {
    var body: some View {
        if let icon = PlatformAppIcon.load() {
            icon
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.gradient)

                Image(systemName: "book.pages.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

private enum PlatformAppIcon {
    static func load() -> Image? {
        for name in iconNames {
            #if canImport(UIKit)
            if let image = UIImage(named: name) {
                return Image(uiImage: image)
            }
            #elseif canImport(AppKit)
            if let image = NSImage(named: name) {
                return Image(nsImage: image)
            }
            #endif
        }
        return nil
    }

    private static var iconNames: [String] {
        var names = ["AppIcon"]

        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primaryIcon["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files.reversed())
        }

        return names
    }
}
