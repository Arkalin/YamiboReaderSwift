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

            ReleaseNoteMarkdownView(
                markdown: release.displayBody,
                fallback: L10n.string("about.release_notes.no_body")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ReleaseNoteMarkdownView: View {
    let markdown: String?
    let fallback: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(AboutReleaseNoteMarkdown.blocks(markdown: markdown, fallback: fallback).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(text):
                    markdownText(text)
                case let .unorderedListItem(text, depth):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 8 + CGFloat(depth * 12), alignment: .trailing)

                        markdownText(text)
                    }
                case let .orderedListItem(marker, text, depth):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(marker)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 18 + CGFloat(depth * 12), alignment: .trailing)

                        markdownText(text)
                    }
                case .spacer:
                    Spacer()
                        .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownText(_ text: String) -> Text {
        Text(AboutReleaseNoteMarkdown.attributedInlineMarkdown(text))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

enum AboutReleaseNoteMarkdown {
    enum Block: Equatable {
        case paragraph(String)
        case unorderedListItem(String, depth: Int)
        case orderedListItem(marker: String, String, depth: Int)
        case spacer
    }

    static func blocks(markdown: String?, fallback: String) -> [Block] {
        guard let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [.paragraph(fallback)]
        }

        var blocks: [Block] = []
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            blocks.append(block(for: String(line)))
        }
        return trimSpacerBlocks(blocks)
    }

    static func attributedInlineMarkdown(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(markdown)
        }
    }

    private static func block(for line: String) -> Block {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .spacer }

        let leadingSpaces = line.prefix { $0 == " " }.count
        let depth = leadingSpaces / 2

        if let match = unorderedListMatch(in: trimmed) {
            return .unorderedListItem(match, depth: depth)
        }
        if let match = orderedListMatch(in: trimmed) {
            return .orderedListItem(marker: match.marker, match.text, depth: depth)
        }
        return .paragraph(trimmed)
    }

    private static func unorderedListMatch(in line: String) -> String? {
        guard line.count > 2 else { return nil }
        let marker = line[line.startIndex]
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let nextIndex = line.index(after: line.startIndex)
        guard line[nextIndex].isWhitespace else { return nil }
        return String(line[line.index(after: nextIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedListMatch(in line: String) -> (marker: String, text: String)? {
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }
        guard index > line.startIndex, index < line.endIndex, line[index] == "." else { return nil }
        let markerEnd = line.index(after: index)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let marker = String(line[..<markerEnd])
        let textStart = line.index(after: markerEnd)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
        return (marker, text)
    }

    private static func trimSpacerBlocks(_ blocks: [Block]) -> [Block] {
        var blocks = blocks
        while blocks.first == .spacer {
            blocks.removeFirst()
        }
        while blocks.last == .spacer {
            blocks.removeLast()
        }
        return blocks.isEmpty ? [.spacer] : blocks
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
