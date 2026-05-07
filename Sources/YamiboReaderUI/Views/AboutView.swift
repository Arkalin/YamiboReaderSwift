import SwiftUI
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AboutViewModel

    public init(appContext: YamiboAppContext) {
        _viewModel = StateObject(wrappedValue: AboutViewModel(appContext: appContext))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    AboutHeaderView()
                        .padding(.top, 32)

                    ReleaseNotesSection(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
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
            .task {
                await viewModel.load()
            }
        }
    }
}

@MainActor
final class AboutViewModel: ObservableObject {
    @Published private(set) var releases: [ReleaseNote] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: ReleaseNotesService
    private var hasLoaded = false

    init(appContext: YamiboAppContext) {
        self.service = appContext.makeReleaseNotesService()
    }

    init(service: ReleaseNotesService) {
        self.service = service
    }

    func load() async {
        guard !hasLoaded else { return }
        await refresh()
        hasLoaded = true
    }

    func retry() async {
        await refresh()
        hasLoaded = true
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            releases = try await service.fetchRecentReleases()
        } catch {
            releases = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

private struct AboutHeaderView: View {
    var body: some View {
        VStack(spacing: 16) {
            AppIconView()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 14, y: 8)

            Text(AppMetadata.displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text(AppMetadata.versionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReleaseNotesSection: View {
    @ObservedObject var viewModel: AboutViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("about.release_notes.title"))
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.string("about.release_notes.loading"))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("about.release_notes.load_failed", errorMessage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(L10n.string("common.retry")) {
                    Task {
                        await viewModel.retry()
                    }
                }
                .buttonStyle(.bordered)
            }
        } else if viewModel.releases.isEmpty {
            Text(L10n.string("about.release_notes.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.releases) { release in
                    ReleaseNoteRow(release: release)
                }
            }
        }
    }
}

private struct ReleaseNoteRow: View {
    let release: ReleaseNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(release.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                if let publishedAt = release.publishedAt {
                    Text(publishedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(AboutReleaseNoteMarkdown.attributedBody(for: release))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum AboutReleaseNoteMarkdown {
    static func attributedBody(for release: ReleaseNote) -> AttributedString {
        attributedBody(markdown: release.displayBody, fallback: L10n.string("about.release_notes.no_body"))
    }

    static func attributedBody(markdown: String?, fallback: String) -> AttributedString {
        guard let markdown else {
            return AttributedString(fallback)
        }

        do {
            return try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full
                )
            )
        } catch {
            return AttributedString(markdown)
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
