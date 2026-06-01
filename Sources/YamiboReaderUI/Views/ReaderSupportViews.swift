import SwiftUI
import YamiboReaderCore

public enum ReaderProgressScrubPhase: Equatable, Sendable {
    case idle
    case pressed
    case scrubbing
    case ended
}

public enum ReaderProgressScrubHaptic: Equatable, Sendable {
    case start
    case chapterTick
    case commit
}

public struct ReaderProgressScrubPreview: Equatable, Sendable {
    public var chapterTitle: String?
    public var pageNumber: Int

    public init(chapterTitle: String?, pageNumber: Int) {
        self.chapterTitle = chapterTitle
        self.pageNumber = max(pageNumber, 1)
    }

    public var displayText: String {
        let pageText = "第\(pageNumber)页"
        guard let chapterTitle,
              !chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pageText
        }
        return "\(chapterTitle) \(pageText)"
    }
}

public struct ReaderProgressScrubContext: Sendable {
    public var readingMode: ReaderReadingMode
    public var pageCount: Int
    public var currentProgressPercent: Int
    public var targetPageIndex: @Sendable (Double) -> Int
    public var chapterTitle: @Sendable (Int) -> String?
    public var chapterTickStartIndex: @Sendable (Int) -> Int?

    public init(
        readingMode: ReaderReadingMode,
        pageCount: Int,
        currentProgressPercent: Int,
        targetPageIndex: @escaping @Sendable (Double) -> Int,
        chapterTitle: @escaping @Sendable (Int) -> String?,
        chapterTickStartIndex: @escaping @Sendable (Int) -> Int?
    ) {
        self.readingMode = readingMode
        self.pageCount = max(pageCount, 1)
        self.currentProgressPercent = min(max(currentProgressPercent, 0), 100)
        self.targetPageIndex = targetPageIndex
        self.chapterTitle = chapterTitle
        self.chapterTickStartIndex = chapterTickStartIndex
    }

    public var valueRange: ClosedRange<Double> {
        switch readingMode {
        case .paged:
            0 ... Double(max(pageCount - 1, 0))
        case .vertical:
            0 ... 100
        }
    }

    public var restingValue: Double {
        switch readingMode {
        case .paged:
            0
        case .vertical:
            Double(currentProgressPercent)
        }
    }
}

public struct ReaderProgressScrubUpdate: Equatable, Sendable {
    public var haptics: [ReaderProgressScrubHaptic]
    public var committedPageIndex: Int?

    public init(haptics: [ReaderProgressScrubHaptic] = [], committedPageIndex: Int? = nil) {
        self.haptics = haptics
        self.committedPageIndex = committedPageIndex
    }
}

public enum ReaderProgressDragMapping {
    public static func value(
        startProgressFraction: Double,
        translation: CGFloat,
        length: CGFloat,
        range: ClosedRange<Double>
    ) -> Double {
        guard length > 0 else { return range.lowerBound }
        let startFraction = min(max(startProgressFraction, 0), 1)
        let translatedFraction = startFraction + Double(translation / length)
        let clampedFraction = min(max(translatedFraction, 0), 1)
        return range.lowerBound + clampedFraction * (range.upperBound - range.lowerBound)
    }
}

public struct ReaderProgressChromePresentation: Equatable, Sendable {
    public var readingMode: ReaderReadingMode
    public var isChromeVisible: Bool

    public init(readingMode: ReaderReadingMode, isChromeVisible: Bool) {
        self.readingMode = readingMode
        self.isChromeVisible = isChromeVisible
    }

    public var showsConventionalSlider: Bool { false }

    public var showsHorizontalFill: Bool {
        readingMode == .paged
    }

    public var supportsHorizontalScrub: Bool {
        readingMode == .paged
    }

    public var horizontalCapsuleUsesIndependentTapAndDrag: Bool { true }

    public var showsVerticalScrubber: Bool {
        readingMode == .vertical && isChromeVisible
    }

    public func horizontalCapsuleText(percentText: String) -> String {
        "目录 · \(percentText)"
    }
}

public enum ReaderBottomActionKind: Equatable, Sendable {
    case browser
    case comments
    case settings
    case bookmark
    case cache
}

public struct ReaderBottomAction: Equatable, Sendable {
    public var kind: ReaderBottomActionKind
    public var isDisabled: Bool

    public init(kind: ReaderBottomActionKind, isDisabled: Bool = false) {
        self.kind = kind
        self.isDisabled = isDisabled
    }
}

public struct ReaderBottomActionRowPresentation: Equatable, Sendable {
    public var isScrubbing: Bool

    public init(isScrubbing: Bool) {
        self.isScrubbing = isScrubbing
    }

    public var actions: [ReaderBottomAction] {
        [
            ReaderBottomAction(kind: .browser),
            ReaderBottomAction(kind: .bookmark, isDisabled: true),
            ReaderBottomAction(kind: .cache),
        ]
    }

    public var opacity: Double {
        isScrubbing ? 0 : 1
    }

    public var allowsHitTesting: Bool {
        !isScrubbing
    }

    public var isAccessibilityHidden: Bool {
        isScrubbing
    }

    public var preservesLayout: Bool { true }
}

public enum ReaderBottomChromeHorizontalAlignment: Equatable, Sendable {
    case trailing
}

public struct ReaderBottomChromeLayoutPresentation: Equatable, Sendable {
    public var usesIndependentControls: Bool { true }
    public var panelSpacing: CGFloat { 10 }
    public var maxChromeWidth: CGFloat { 260 }
    public var progressPanelHeight: CGFloat { 44 }
    public var actionButtonIconFrame: CGFloat { 34 }
    public var actionButtonRowHeight: CGFloat { progressPanelHeight }
    public var actionButtonSpacing: CGFloat { 8 }
    public var bottomControlsAdditionalBottomOffset: CGFloat { 8 }
    public var horizontalAlignment: ReaderBottomChromeHorizontalAlignment { .trailing }
    public var progressTextLeadsIcon: Bool { true }
    public var progressFillHasVerticalTrailingEdge: Bool { true }
    public var horizontalProgressThumbVisible: Bool { false }
    public var horizontalChapterTicksVisibleOnlyWhileScrubbing: Bool { true }
    public var horizontalDirectoryContentHiddenWhileScrubbing: Bool { true }
    public var progressCapsulesUseButtonTint: Bool { true }
    public var progressSummaryVisibleWhileScrubbing: Bool { true }
    public var verticalScrubberWidth: CGFloat { progressPanelHeight }
    public var verticalScrubberHeight: CGFloat { progressPanelHeight * 3 + panelSpacing * 3 + actionButtonRowHeight }
    public var verticalPreviewWidth: CGFloat { maxChromeWidth }
    public var verticalPreviewHeight: CGFloat { 50 }
    public var verticalScrubberShowsChapterTicks: Bool { true }
    public var verticalChapterTicksVisibleOnlyWhileScrubbing: Bool { true }
    public var verticalScrubberFillHasSquareEdge: Bool { true }
    public var hidesDirectoryCapsuleDuringVerticalScrub: Bool { true }
    public var verticalScrubberSideSpacing: CGFloat { actionButtonSpacing }
    public var verticalScrubberTicksAreCentered: Bool { true }
    public var verticalScrubberShowsLiveThumb: Bool { false }
    public var verticalScrubberBottomAlignsWithActionButtons: Bool { true }
    public var verticalPreviewUsesTwoLineChapterAndPage: Bool { true }
    public var verticalPreviewUsesLiquidGlass: Bool { true }
    public var horizontalPreviewMatchesVerticalCapsule: Bool { true }
    public var verticalScrubberShowsProgressFill: Bool { true }
    public var verticalCurrentChapterTickUsesAccentColor: Bool { true }
    public var directoryCapsuleContentUsesAccentColor: Bool { true }
    public var bottomProgressSummaryUsesPageCenter: Bool { true }
    public var verticalProgressSummaryUsesLiquidGlass: Bool { true }
    public var verticalChapterTitleCapsuleWrapsContent: Bool { true }
    public var verticalScrubberActionRowBottomOffset: CGFloat { 46 }

    public init() {}
}

public struct ReaderChromeProgressSummary: Equatable, Sendable {
    public var chapterTitle: String
    public var pageProgressLine: String
    public var webProgressLine: String

    public init(chapterTitle: String?, progressText: String) {
        let components = progressText
            .split(separator: "·", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let trimmedChapter = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = trimmedChapter?.isEmpty == false ? trimmedChapter! : components.dropFirst(2).first ?? ""
        self.pageProgressLine = components.first ?? progressText
        self.webProgressLine = components.dropFirst().first ?? ""
    }
}

public struct ReaderProgressScrubState: Equatable, Sendable {
    public private(set) var phase: ReaderProgressScrubPhase = .idle
    public private(set) var value = 0.0
    public private(set) var targetRenderedPageIndex = 0
    public private(set) var preview: ReaderProgressScrubPreview?
    private var lastChapterTickStartIndex: Int?

    public init() {}

    @discardableResult
    public mutating func press(value newValue: Double, context: ReaderProgressScrubContext) -> ReaderProgressScrubUpdate {
        phase = .pressed
        return update(value: newValue, context: context)
    }

    @discardableResult
    public mutating func update(value newValue: Double, context: ReaderProgressScrubContext) -> ReaderProgressScrubUpdate {
        var haptics: [ReaderProgressScrubHaptic] = []
        if phase != .scrubbing {
            haptics.append(.start)
        }

        phase = .scrubbing
        value = Self.clamp(newValue, to: context.valueRange)
        targetRenderedPageIndex = context.targetPageIndex(value)
        preview = ReaderProgressScrubPreview(
            chapterTitle: context.chapterTitle(targetRenderedPageIndex),
            pageNumber: targetRenderedPageIndex + 1
        )

        let tickStartIndex = context.chapterTickStartIndex(targetRenderedPageIndex)
        if let tickStartIndex, tickStartIndex != lastChapterTickStartIndex {
            haptics.append(.chapterTick)
        }
        lastChapterTickStartIndex = tickStartIndex

        return ReaderProgressScrubUpdate(haptics: haptics)
    }

    @discardableResult
    public mutating func end() -> ReaderProgressScrubUpdate {
        phase = .ended
        lastChapterTickStartIndex = nil
        return ReaderProgressScrubUpdate(haptics: [.commit], committedPageIndex: targetRenderedPageIndex)
    }

    public mutating func reset(to value: Double = 0) {
        phase = .idle
        self.value = value
        targetRenderedPageIndex = 0
        preview = nil
        lastChapterTickStartIndex = nil
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct ReaderProgressSliderSnapshot: Equatable {
    var readingMode: ReaderReadingMode
    var visibleView: Int
    var renderedPageCount: Int
    var currentRenderedPage: Int
    var currentProgressPercent: Int

    var modelValue: Double {
        switch readingMode {
        case .vertical:
            Double(currentProgressPercent)
        case .paged:
            Double(max(currentRenderedPage - 1, 0))
        }
    }
}

struct ReaderProgressSliderState: Equatable {
    var sliderValue = 0.0
    var isEditing = false

    mutating func reset(to snapshot: ReaderProgressSliderSnapshot) {
        isEditing = false
        sliderValue = snapshot.modelValue
    }

    mutating func syncModelValue(_ value: Double) {
        guard !isEditing else { return }
        sliderValue = value
    }
}

#if os(iOS)
import UIKit

struct ReaderGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func readerChromePanel(cornerRadius: CGFloat = 28, tint: Color = .clear) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func readerChromeButtonStyle(prominent: Bool = false, tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                self
                    .buttonStyle(.glass)
                    .tint(tint)
            }
        } else {
            if prominent {
                self
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            } else {
                self
                    .buttonStyle(.bordered)
                    .tint(tint)
            }
        }
    }
}

struct ReaderPageContent: View {
    let page: ReaderRenderedPage
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(page.blocks) { block in
                ReaderBlockView(
                    block: block,
                    settings: settings,
                    refererURL: refererURL,
                    sessionState: sessionState
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReaderPagedSpreadContent: View {
    let spread: ReaderPagedSpread
    let pages: [ReaderRenderedPage]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            spreadColumn(pageIndex: spread.leftPageIndex)
            spreadColumn(pageIndex: spread.rightPageIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func spreadColumn(pageIndex: Int?) -> some View {
        Group {
            if let pageIndex, pages.indices.contains(pageIndex) {
                ReaderPageContent(
                    page: pages[pageIndex],
                    settings: settings,
                    refererURL: refererURL,
                    sessionState: sessionState
                )
                .padding(.horizontal, settings.horizontalPadding)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ReaderBlockView: View {
    let block: ReaderRenderedBlock
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch block {
        case let .text(text, chapterTitle):
            ReaderRichTextView(
                text: text,
                chapterTitle: chapterTitle,
                settings: settings,
                baseFontSize: 22,
                textColor: UIColor(readerTextColor)
            )
        case let .image(url, _):
            AuthenticatedReaderImage(
                url: url,
                refererURL: refererURL,
                sessionState: sessionState
            )
        case let .footer(text):
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        }
    }

    private var readerTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : .primary
    }
}

struct ReaderRichTextView: UIViewRepresentable {
    let text: String
    let chapterTitle: String?
    let settings: ReaderAppearanceSettings
    let baseFontSize: Double
    let textColor: UIColor
    var titleWeight: UIFont.Weight = .regular

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = makeAttributedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? UIScreen.main.bounds.width
        let fittingSize = uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: targetWidth, height: ceil(fittingSize.height))
    }

    private func makeAttributedText() -> NSAttributedString {
        ReaderAttributedTextFactory.makeAttributedText(
            text: text,
            chapterTitle: chapterTitle,
            settings: settings,
            baseFontSize: baseFontSize,
            textColor: textColor,
            titleWeight: titleWeight
        )
    }
}

@MainActor
private final class ReaderImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var didFail = false

    private let url: URL
    private let refererURL: URL
    private let sessionState: SessionState

    init(url: URL, refererURL: URL, sessionState: SessionState) {
        self.url = url
        self.refererURL = refererURL
        self.sessionState = sessionState
    }

    func loadIfNeeded() async {
        guard image == nil, !isLoading else { return }
        isLoading = true
        didFail = false
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.setValue(sessionState.userAgent, forHTTPHeaderField: "User-Agent")
        if !sessionState.cookie.isEmpty {
            request.setValue(sessionState.cookie, forHTTPHeaderField: "Cookie")
        }
        request.setValue(refererURL.absoluteString, forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode,
                  let image = UIImage(data: data) else {
                didFail = true
                return
            }
            self.image = image
            didFail = false
        } catch {
            didFail = true
        }
    }

    func retry() async {
        await loadIfNeeded()
    }
}

private struct AuthenticatedReaderImage: View {
    @StateObject private var loader: ReaderImageLoader

    init(url: URL, refererURL: URL, sessionState: SessionState) {
        _loader = StateObject(
            wrappedValue: ReaderImageLoader(
                url: url,
                refererURL: refererURL,
                sessionState: sessionState
            )
        )
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.didFail {
                VStack(spacing: 8) {
                    Label(L10n.string("image.load_failed"), systemImage: "photo")
                        .foregroundColor(.secondary)

                    Button {
                        Task {
                            await loader.retry()
                        }
                    } label: {
                        Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            await loader.loadIfNeeded()
        }
    }
}

struct ReaderTopChrome: View {
    let model: ReaderContainerModel
    let topInset: CGFloat
    let onClose: () -> Void
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: model.currentChapterTitle,
            progressText: model.progressText
        )

        ReaderGlassContainer(spacing: 12) {
            let closeButtonSize: CGFloat = 44

            HStack(spacing: 12) {
                Color.clear
                    .frame(width: closeButtonSize, height: closeButtonSize)
                    .accessibilityHidden(true)

                chapterTitleView(summary.chapterTitle)
                    .frame(maxWidth: .infinity)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: closeButtonSize, height: closeButtonSize)
                }
                .buttonStyle(.plain)
                .foregroundStyle(readerChromeButtonTint(for: colorScheme))
                .contentShape(Circle())
                .readerChromePanel(cornerRadius: closeButtonSize / 2, tint: readerChromePanelTint(for: colorScheme))
                .accessibilityLabel(L10n.string("common.close"))
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .tint(readerChromeButtonTint(for: colorScheme))
    }

    @ViewBuilder
    private func chapterTitleView(_ title: String) -> some View {
        let text = Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.primary)

        if model.settings.readingMode == .vertical {
            text
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .readerChromePanel(cornerRadius: 18, tint: readerChromePanelTint(for: colorScheme))
        } else {
            text
                .frame(maxWidth: .infinity)
        }
    }
}

struct ReaderBottomChrome: View {
    @ObservedObject var model: ReaderContainerModel
    let bottomInset: CGFloat
    let onShowChapters: () -> Void
    let onShowSettings: () -> Void
    let onShowCache: () -> Void
    let onShowComments: () -> Void
    let onOpenForum: () -> Void
    let onJumpChapter: (Int) -> Void
    let onProgressCommit: (Int) -> Void
    let isProgressScrubbing: Bool

    @State private var sliderState = ReaderProgressSliderState()
    @State private var scrubState = ReaderProgressScrubState()
    @State private var progressTickFeedbackGenerator = UISelectionFeedbackGenerator()
    @State private var progressStartFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @State private var progressCommitFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @State private var lastFeedbackTickStartIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: chromeLayout.panelSpacing) {
                progressControl
                actionRow
            }
            .frame(maxWidth: chromeLayout.maxChromeWidth)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 12)
            .padding(.trailing, bottomChromeTrailingPadding)
            .padding(.bottom, chromeLayout.bottomControlsAdditionalBottomOffset)

            progressSummary
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, max(bottomInset, 12))
        .onAppear {
            sliderState.reset(to: sliderSnapshot)
        }
        .onChange(of: sliderSnapshot) { _, newValue in
            sliderState.reset(to: newValue)
        }
        .onChange(of: sliderModelValue) { _, newValue in
            sliderState.syncModelValue(newValue)
        }
    }

    private var chromeLayout: ReaderBottomChromeLayoutPresentation {
        ReaderBottomChromeLayoutPresentation()
    }

    private var bottomChromeTrailingPadding: CGFloat {
        guard model.settings.readingMode == .vertical else { return 12 }
        return 12 + chromeLayout.verticalScrubberWidth + chromeLayout.verticalScrubberSideSpacing
    }

    private var actionRow: some View {
        let presentation = actionRowPresentation
        return HStack(spacing: 0) {
            bottomActionButton(
                action: ReaderBottomAction(kind: .browser),
                title: L10n.string("common.original_post"),
                systemName: "safari",
                handler: onOpenForum
            )
            Spacer(minLength: chromeLayout.actionButtonSpacing)
            bottomActionButton(
                action: ReaderBottomAction(kind: .bookmark, isDisabled: true),
                title: "书签",
                systemName: "bookmark",
                handler: {}
            )
            Spacer(minLength: chromeLayout.actionButtonSpacing)
            bottomActionButton(
                action: ReaderBottomAction(kind: .cache),
                title: L10n.string("reader.cache"),
                systemName: "square.and.arrow.down",
                handler: onShowCache
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: chromeLayout.actionButtonRowHeight)
        .opacity(presentation.opacity)
        .allowsHitTesting(presentation.allowsHitTesting)
        .accessibilityHidden(presentation.isAccessibilityHidden)
    }

    private var actionRowPresentation: ReaderBottomActionRowPresentation {
        ReaderBottomActionRowPresentation(isScrubbing: isProgressScrubbing || scrubState.phase == .scrubbing)
    }

    @ViewBuilder
    private var progressSummary: some View {
        let summary = ReaderChromeProgressSummary(
            chapterTitle: model.currentChapterTitle,
            progressText: model.progressText
        )

        let content = VStack(spacing: 2) {
            Text(summary.pageProgressLine)
            if !summary.webProgressLine.isEmpty {
                Text(summary.webProgressLine)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.center)

        if model.settings.readingMode == .vertical {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .readerChromePanel(cornerRadius: 16, tint: readerChromePanelTint(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func bottomActionButton(
        action: ReaderBottomAction,
        title: String,
        systemName: String,
        handler: @escaping () -> Void
    ) -> some View {
        Button(action: handler) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: chromeLayout.actionButtonIconFrame, height: chromeLayout.actionButtonIconFrame)
        }
        .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
        .opacity(action.isDisabled ? 0.34 : 1)
        .disabled(action.isDisabled)
        .accessibilityLabel(title)
    }

    private var progressControl: some View {
        VStack(spacing: chromeLayout.panelSpacing) {
            if let preview = scrubState.preview, scrubState.phase == .scrubbing {
                ReaderVerticalProgressPreviewCapsule(preview: preview)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ReaderDirectoryProgressCapsule(
                title: progressChromePresentation.horizontalCapsuleText(percentText: model.currentProgressPercentText),
                progressFraction: displayedProgressFraction,
                showsFill: progressChromePresentation.showsHorizontalFill,
                supportsScrub: progressChromePresentation.supportsHorizontalScrub && sliderHasAvailableRange,
                isScrubbing: scrubState.phase == .scrubbing,
                ticks: model.progressChapterTicks,
                onTapDirectory: onShowChapters,
                onScrub: { locationX, width in
                    handleHorizontalCapsuleScrub(locationX: locationX, width: width)
                },
                onEndScrub: {
                    commitHorizontalCapsuleScrub()
                }
            )
            .opacity(shouldHideDirectoryCapsule ? 0 : 1)
            .allowsHitTesting(!shouldHideDirectoryCapsule)
            .accessibilityHidden(shouldHideDirectoryCapsule)

            secondaryCapsuleButton(
                title: L10n.string("reader.comments"),
                systemName: "text.bubble",
                action: onShowComments
            )

            secondaryCapsuleButton(
                title: L10n.string("settings.title"),
                systemName: "gearshape",
                action: onShowSettings
            )
        }
    }

    private func secondaryCapsuleButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        let presentation = actionRowPresentation
        let controlTint = chromeLayout.progressCapsulesUseButtonTint ? readerChromeButtonTint(for: colorScheme) : Color.accentColor

        return Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 12)
                Image(systemName: systemName)
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(chromeLayout.directoryCapsuleContentUsesAccentColor ? controlTint : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: chromeLayout.progressPanelHeight)
            .padding(.horizontal, 18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .readerChromePanel(cornerRadius: 24, tint: readerChromePanelTint(for: colorScheme))
        .opacity(presentation.opacity)
        .allowsHitTesting(presentation.allowsHitTesting)
        .accessibilityHidden(presentation.isAccessibilityHidden)
        .accessibilityLabel(title)
    }

    private var shouldHideDirectoryCapsule: Bool {
        chromeLayout.hidesDirectoryCapsuleDuringVerticalScrub
            && model.settings.readingMode == .vertical
            && isProgressScrubbing
    }

    private var progressChromePresentation: ReaderProgressChromePresentation {
        ReaderProgressChromePresentation(readingMode: model.settings.readingMode, isChromeVisible: true)
    }

    private var sliderRange: ClosedRange<Double> {
        if model.settings.readingMode == .vertical {
            0 ... 100
        } else {
            0 ... Double(max(model.renderedPageCount - 1, 0))
        }
    }

    private var sliderModelValue: Double {
        if model.settings.readingMode == .vertical {
            Double(model.currentProgressPercent)
        } else {
            Double(max(model.currentRenderedPage - 1, 0))
        }
    }

    private var sliderSnapshot: ReaderProgressSliderSnapshot {
        ReaderProgressSliderSnapshot(
            readingMode: model.settings.readingMode,
            visibleView: model.visibleView,
            renderedPageCount: model.renderedPageCount,
            currentRenderedPage: model.currentRenderedPage,
            currentProgressPercent: model.currentProgressPercent
        )
    }

    private var sliderHasAvailableRange: Bool {
        sliderRange.lowerBound < sliderRange.upperBound
    }

    private var displayedProgressFraction: Double {
        if scrubState.phase == .scrubbing {
            guard model.renderedPageCount > 1 else { return 0 }
            return Double(scrubState.targetRenderedPageIndex) / Double(max(model.renderedPageCount - 1, 1))
        }
        return model.currentProgressFraction
    }

    private var progressLabelText: String {
        model.progressSliderLabelText(
            isEditing: sliderState.isEditing,
            sliderValue: sliderState.sliderValue,
            targetRenderedPageIndex: sliderTargetRenderedPageIndex
        )
    }

    private var sliderTargetRenderedPageIndex: Int {
        model.targetRenderedPageIndex(forProgressValue: sliderState.sliderValue)
    }

    private var scrubContext: ReaderProgressScrubContext {
        ReaderProgressScrubContext(
            readingMode: model.settings.readingMode,
            pageCount: model.renderedPageCount,
            currentProgressPercent: model.currentProgressPercent,
            targetPageIndex: { value in
                model.targetRenderedPageIndex(forProgressValue: value)
            },
            chapterTitle: { pageIndex in
                model.chapterTitle(forRenderedPageIndex: pageIndex)
            },
            chapterTickStartIndex: { pageIndex in
                model.progressChapterTickStartIndex(forRenderedPageIndex: pageIndex)
            }
        )
    }

    private func handleHorizontalCapsuleScrub(locationX: CGFloat, width: CGFloat) {
        guard progressChromePresentation.supportsHorizontalScrub, width > 0 else { return }
        let fraction = min(max(locationX / width, 0), 1)
        let value = sliderRange.lowerBound + Double(fraction) * (sliderRange.upperBound - sliderRange.lowerBound)
        let update = scrubState.update(value: value, context: scrubContext)
        triggerFeedback(update.haptics)
    }

    private func commitHorizontalCapsuleScrub() {
        guard scrubState.phase == .scrubbing else { return }
        let update = scrubState.end()
        triggerFeedback(update.haptics)
        if let target = update.committedPageIndex {
            onProgressCommit(target)
        }
        sliderState.sliderValue = sliderModelValue
    }

    private func triggerFeedback(_ haptics: [ReaderProgressScrubHaptic]) {
        for haptic in haptics {
            switch haptic {
            case .start:
                progressStartFeedbackGenerator.impactOccurred()
                progressStartFeedbackGenerator.prepare()
                progressTickFeedbackGenerator.prepare()
            case .chapterTick:
                progressTickFeedbackGenerator.selectionChanged()
                progressTickFeedbackGenerator.prepare()
            case .commit:
                progressCommitFeedbackGenerator.impactOccurred()
                progressCommitFeedbackGenerator.prepare()
            }
        }
    }

    private func triggerProgressTickFeedbackIfNeeded() {
        guard let tickStartIndex = model.progressChapterTickStartIndex(forRenderedPageIndex: sliderTargetRenderedPageIndex) else {
            lastFeedbackTickStartIndex = nil
            return
        }
        guard lastFeedbackTickStartIndex != tickStartIndex else { return }

        progressTickFeedbackGenerator.selectionChanged()
        progressTickFeedbackGenerator.prepare()
        lastFeedbackTickStartIndex = tickStartIndex
    }
}

private struct ReaderProgressChapterTickOverlay: View {
    let ticks: [ReaderProgressChapterTick]
    let currentTint: Color

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(ticks.enumerated()), id: \.element.chapter.startIndex) { _, tick in
                Capsule()
                    .fill(tick.isCurrent ? currentTint : Color.secondary.opacity(0.38))
                    .frame(width: tick.isCurrent ? 3 : 2, height: tick.isCurrent ? 12 : 8)
                    .position(
                        x: min(max(tick.position, 0), 1) * geometry.size.width,
                        y: geometry.size.height / 2
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 24)
        .allowsHitTesting(false)
    }
}

private struct ReaderDirectoryProgressCapsule: View {
    let title: String
    let progressFraction: Double
    let showsFill: Bool
    let supportsScrub: Bool
    let isScrubbing: Bool
    let ticks: [ReaderProgressChapterTick]
    let onTapDirectory: () -> Void
    let onScrub: (CGFloat, CGFloat) -> Void
    let onEndScrub: () -> Void
    @State private var dragStartProgressFraction: Double?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let layout = ReaderBottomChromeLayoutPresentation()
            let controlTint = layout.progressCapsulesUseButtonTint ? readerChromeButtonTint(for: colorScheme) : Color.accentColor
            let width = max(geometry.size.width, 1)
            let clampedProgress = min(max(progressFraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12))

                if showsFill {
                    Rectangle()
                        .fill(controlTint.opacity(colorScheme == .dark ? 0.24 : 0.18))
                        .frame(width: max(0, width * clampedProgress))
                        .accessibilityHidden(true)
                }

                ReaderProgressChapterTickOverlay(ticks: ticks, currentTint: controlTint)
                    .padding(.horizontal, 12)
                    .opacity(showsFill && (!layout.horizontalChapterTicksVisibleOnlyWhileScrubbing || isScrubbing) ? 1 : 0)

                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 12)
                    Image(systemName: "list.bullet")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(layout.directoryCapsuleContentUsesAccentColor ? controlTint : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .opacity(layout.horizontalDirectoryContentHiddenWhileScrubbing && isScrubbing ? 0 : 1)
            }
            .frame(height: 44)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .readerChromePanel(cornerRadius: 24, tint: readerChromePanelTint(for: colorScheme))
            .gesture(scrubGesture(width: width), including: supportsScrub ? .gesture : .subviews)
            .onTapGesture(perform: onTapDirectory)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityHint(L10n.string("reader.chapters"))
        }
        .frame(height: ReaderBottomChromeLayoutPresentation().progressPanelHeight)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard supportsScrub else { return }
                if dragStartProgressFraction == nil {
                    dragStartProgressFraction = progressFraction
                }
                let targetFraction = ReaderProgressDragMapping.value(
                    startProgressFraction: dragStartProgressFraction ?? progressFraction,
                    translation: value.translation.width,
                    length: width,
                    range: 0...1
                )
                onScrub(CGFloat(targetFraction) * width, width)
            }
            .onEnded { _ in
                guard supportsScrub else { return }
                dragStartProgressFraction = nil
                onEndScrub()
            }
    }
}

struct ReaderVerticalProgressCapsule: View {
    let progressFraction: Double
    let preview: ReaderProgressScrubPreview?
    let isScrubbing: Bool
    let ticks: [ReaderProgressChapterTick]
    let onScrub: (CGFloat, CGFloat) -> Void
    let onEndScrub: () -> Void
    @State private var dragStartProgressFraction: Double?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let totalWidth = isScrubbing ? layout.verticalPreviewWidth + layout.verticalScrubberSideSpacing + layout.verticalScrubberWidth : layout.verticalScrubberWidth

        GeometryReader { geometry in
            let height = max(geometry.size.height, 1)
            let clampedProgress = min(max(progressFraction, 0), 1)
            let thumbY = min(max(height * clampedProgress, 0), height)

            ZStack(alignment: .topTrailing) {
                verticalProgressBar(height: height, thumbY: thumbY)
                    .frame(width: layout.verticalScrubberWidth, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                if isScrubbing, let preview {
                    ReaderVerticalProgressPreviewCapsule(preview: preview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: min(max(thumbY - layout.verticalPreviewHeight / 2, 0), max(height - layout.verticalPreviewHeight, 0)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geometry.size.width, height: height, alignment: .topTrailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartProgressFraction == nil {
                            dragStartProgressFraction = progressFraction
                        }
                        let targetFraction = ReaderProgressDragMapping.value(
                            startProgressFraction: dragStartProgressFraction ?? progressFraction,
                            translation: value.translation.height,
                            length: height,
                            range: 0...1
                        )
                        onScrub(CGFloat(targetFraction) * height, height)
                    }
                    .onEnded { _ in
                        dragStartProgressFraction = nil
                        onEndScrub()
                    }
            )
            .accessibilityLabel("目录 · 进度")
        }
        .frame(width: totalWidth)
        .frame(height: layout.verticalScrubberHeight)
    }

    private func verticalProgressBar(height: CGFloat, thumbY: CGFloat) -> some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let controlTint = layout.progressCapsulesUseButtonTint ? readerChromeButtonTint(for: colorScheme) : Color.accentColor

        return ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .readerChromePanel(cornerRadius: 24, tint: readerChromePanelTint(for: colorScheme))

            if layout.verticalScrubberShowsProgressFill {
                Rectangle()
                    .fill(controlTint.opacity(colorScheme == .dark ? 0.24 : 0.18))
                    .frame(width: layout.verticalScrubberWidth, height: max(0, thumbY))
                    .accessibilityHidden(true)
            }

            ReaderVerticalProgressChapterTickOverlay(ticks: ticks, currentTint: controlTint)
                .padding(.vertical, 12)
                .opacity(layout.verticalScrubberShowsChapterTicks && (!layout.verticalChapterTicksVisibleOnlyWhileScrubbing || isScrubbing) ? 1 : 0)

            if layout.verticalScrubberShowsLiveThumb {
                Capsule()
                    .fill(controlTint.opacity(0.82))
                    .frame(width: 28, height: 3)
                    .offset(x: -18, y: min(max(thumbY - 1.5, 0), height - 3))
                    .accessibilityHidden(true)
            }
        }
        .mask(Capsule())
    }
}

private struct ReaderVerticalProgressChapterTickOverlay: View {
    let ticks: [ReaderProgressChapterTick]
    let currentTint: Color

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()

        GeometryReader { geometry in
            ForEach(Array(ticks.enumerated()), id: \.element.chapter.startIndex) { _, tick in
                Capsule()
                    .fill(tick.isCurrent && layout.verticalCurrentChapterTickUsesAccentColor ? currentTint : Color.secondary.opacity(0.38))
                    .frame(width: tick.isCurrent ? 28 : 18, height: tick.isCurrent ? 3 : 2)
                    .position(
                        x: layout.verticalScrubberTicksAreCentered ? geometry.size.width / 2 : geometry.size.width - 24,
                        y: min(max(tick.position, 0), 1) * geometry.size.height
                    )
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ReaderVerticalProgressPreviewCapsule: View {
    let preview: ReaderProgressScrubPreview

    var body: some View {
        let layout = ReaderBottomChromeLayoutPresentation()
        let chapterTitle = preview.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(spacing: 2) {
            Text(chapterTitle?.isEmpty == false ? chapterTitle! : "目录")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("第\(preview.pageNumber)页")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .frame(width: layout.verticalPreviewWidth, height: layout.verticalPreviewHeight)
            .readerChromePanel(cornerRadius: 24, tint: Color.accentColor.opacity(0.08))
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}

struct ReaderChromeIconButton: View {
    let systemName: String
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 34, height: 34)
        }
        .readerChromeButtonStyle(tint: readerChromeButtonTint(for: colorScheme))
        .accessibilityLabel(title)
    }
}

func readerChromePanelTint(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.18)
}

func readerChromeButtonTint(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(red: 0.78, green: 0.58, blue: 0.42) : .accentColor
}

struct ReaderChapterSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onSelect: (ReaderChapter) -> Void
    let onSelectWebView: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingWebPicker = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ZStack {
                    if model.isLoadingChapterDirectory {
                        Text(L10n.string("common.loading"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                if let error = model.chapterDirectoryError {
                                    Label(error, systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if let previousView = model.previousChapterDirectoryWebView {
                                    ReaderChapterWebNavigationButton(
                                        title: L10n.string("reader.go_previous_web_page"),
                                        systemImage: "chevron.up",
                                        action: { onSelectWebView(previousView) }
                                    )
                                }

                                ForEach(model.visibleChapterDirectoryChapters, id: \.startIndex) { chapter in
                                    Button {
                                        onSelect(chapter)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(chapter.title)
                                                .font(.body.weight(isCurrent(chapter) ? .semibold : .regular))
                                                .foregroundStyle(isCurrent(chapter) ? Color.accentColor : .primary)
                                                .lineLimit(1)
                                            Text(chapterLocationText(for: chapter))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(isCurrent(chapter) ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .id(chapter.startIndex)
                                }

                                if let nextView = model.nextChapterDirectoryWebView {
                                    ReaderChapterWebNavigationButton(
                                        title: L10n.string("reader.go_next_web_page"),
                                        systemImage: "chevron.down",
                                        action: { onSelectWebView(nextView) }
                                    )
                                }
                            }
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button {
                            guard model.maxView > 1 else { return }
                            showingWebPicker.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Text(model.chapterDirectoryWebTitle)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .rotationEffect(.degrees(showingWebPicker ? 180 : 0))
                            }
                            .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.maxView <= 1)
                        .popover(isPresented: $showingWebPicker, arrowEdge: .top) {
                            ReaderChapterWebPicker(model: model) { view in
                                showingWebPicker = false
                                guard view != model.visibleChapterDirectoryView else { return }
                                onSelectWebView(view)
                            }
                            .presentationCompactAdaptation(.popover)
                        }
                        .accessibilityLabel(model.chapterDirectoryWebTitle)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Label(L10n.string("common.done"), systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .onAppear {
                    model.resetChapterDirectoryBrowsing()
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.currentChapterIndex) { _, _ in
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.visibleView) { _, _ in
                    showingWebPicker = false
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.visibleChapterDirectoryView) { _, _ in
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.maxView) { _, newValue in
                    if newValue <= 1 {
                        showingWebPicker = false
                    }
                }
            }
        }
    }

    private func isCurrent(_ chapter: ReaderChapter) -> Bool {
        guard model.visibleChapterDirectoryView == model.visibleView else { return false }
        return chapter.title == model.currentChapterTitle
    }

    private func chapterLocationText(for chapter: ReaderChapter) -> String {
        if model.settings.readingMode == .vertical {
            guard model.visibleChapterDirectoryPageCount > 1 else { return "0%" }
            let fraction = Double(chapter.startIndex) / Double(model.visibleChapterDirectoryPageCount - 1)
            return "\(Int((fraction * 100).rounded()))%"
        }
        return L10n.string("reader.page_number_spaced", chapter.startIndex + 1)
    }

    private func scrollToCurrentChapter(using proxy: ScrollViewProxy) {
        guard let currentChapterIndex = model.currentChapterDirectoryIndex,
              model.visibleChapterDirectoryChapters.indices.contains(currentChapterIndex) else { return }
        let targetIndex = max(currentChapterIndex - 3, 0)
        let targetChapter = model.visibleChapterDirectoryChapters[targetIndex]
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(targetChapter.startIndex, anchor: .top)
        }
    }
}

private struct ReaderChapterWebNavigationButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct ReaderChapterCommentsSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let target: ReaderChapterCommentTarget?
    let appModel: YamiboAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderChapterCommentsContent(
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                retry: { target in Task { await model.loadChapterComments(for: target) } },
                loadNext: { Task { await model.loadNextChapterCommentsPage() } },
                openOriginalPost: openOriginalPost(_:)
            )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ReaderChapterCommentsToolbarTitle(target: target)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Label(L10n.string("common.done"), systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await model.refreshChapterComments(for: target) }
                        } label: {
                            Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
                        }
                        .disabled(target == nil)
                    }
                }
        }
        .task(id: target) {
            await model.loadChapterComments(for: target)
        }
    }

    private func openOriginalPost(_ url: URL) {
        dismiss()
        Task {
            await model.saveProgress()
            appModel.dismissReader(openThreadInForum: url)
        }
    }
}

struct MangaChapterCommentsSheet: View {
    @ObservedObject var model: MangaReaderModel
    let target: ReaderChapterCommentTarget?
    let appModel: YamiboAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderChapterCommentsContent(
                state: model.chapterCommentsState,
                isLoadingMore: model.isLoadingMoreChapterComments,
                loadMoreError: model.chapterCommentsLoadMoreError,
                refreshError: model.chapterCommentsRefreshError,
                retry: { target in Task { await model.loadChapterComments(for: target) } },
                loadNext: { Task { await model.loadNextChapterCommentsPage() } },
                openOriginalPost: openOriginalPost(_:)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ReaderChapterCommentsToolbarTitle(target: target)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label(L10n.string("common.done"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshChapterComments(for: target) }
                    } label: {
                        Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(target == nil)
                }
            }
        }
        .task(id: target) {
            await model.loadChapterComments(for: target)
        }
    }

    private func openOriginalPost(_ url: URL) {
        dismiss()
        Task {
            await model.saveProgress()
            appModel.dismissManga(openThreadInForum: url)
        }
    }
}

private struct ReaderChapterCommentsContent: View {
    let state: ReaderChapterCommentsState
    let isLoadingMore: Bool
    let loadMoreError: String?
    let refreshError: String?
    let retry: (ReaderChapterCommentTarget) -> Void
    let loadNext: () -> Void
    let openOriginalPost: (URL) -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.string("common.loading"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unsupported:
            ContentUnavailableView(
                L10n.string("reader.chapter_comments_unsupported"),
                systemImage: "text.bubble"
            )
        case let .failed(target, message):
            VStack(spacing: 12) {
                ContentUnavailableView(
                    message,
                    systemImage: "exclamationmark.triangle"
                )
                Button(L10n.string("common.retry")) {
                    retry(target)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        case let .loaded(target, page):
            if page.comments.isEmpty {
                ContentUnavailableView(
                    L10n.string("reader.chapter_comments_empty"),
                    systemImage: "text.bubble"
                )
            } else {
                List {
                    if let refreshError {
                        Section {
                            Label(refreshError, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        ForEach(page.comments) { comment in
                            ReaderChapterCommentRow(
                                comment: comment,
                                originalPostURL: comment.originalPostURL(threadURL: target.threadURL),
                                openOriginalPost: openOriginalPost
                            )
                        }
                    } footer: {
                        if page.nextView != nil {
                            loadNextButton
                                .padding(.top, 10)
                        }
                    }
                }
            }
        }
    }

    private var loadNextButton: some View {
        Button(action: loadNext) {
            HStack {
                Spacer()
                if isLoadingMore {
                    ProgressView()
                        .tint(Self.loadNextColor)
                } else {
                    Text(loadMoreError ?? L10n.string("reader.chapter_comments_load_next"))
                        .font(.footnote.weight(.medium))
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Self.loadNextColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
    }

    private static let loadNextColor = Color(red: 0.54, green: 0.35, blue: 0.22)
}

private struct ReaderChapterCommentsToolbarTitle: View {
    let target: ReaderChapterCommentTarget?

    var body: some View {
        VStack(spacing: 1) {
            Text(L10n.string("reader.chapter_comments"))
                .font(.headline)
            if let title = target?.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ReaderChapterCommentRow: View {
    let comment: ChapterComment
    let originalPostURL: URL?
    let openOriginalPost: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.authorName.isEmpty ? L10n.string("reader.comment_anonymous") : comment.authorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let metadata = comment.metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                ReaderChapterCommentSourceBadge(source: comment.source)
                if let originalPostURL {
                    Button {
                        openOriginalPost(originalPostURL)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.string("reader.open_original_post"))
                }
            }
            Text(comment.body)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private struct ReaderChapterCommentSourceBadge: View {
    let source: ChapterCommentSource

    var body: some View {
        Text(source.displayLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            .accessibilityLabel(source.displayLabel)
    }

    private var palette: (foreground: Color, border: Color) {
        switch source {
        case .postComment:
            (Color(red: 0.54, green: 0.35, blue: 0.22), Color(red: 0.74, green: 0.52, blue: 0.38))
        case .ratingReason:
            (Color(red: 0.15, green: 0.44, blue: 0.36), Color(red: 0.36, green: 0.65, blue: 0.55))
        case .reply:
            (Color(red: 0.28, green: 0.36, blue: 0.68), Color(red: 0.48, green: 0.56, blue: 0.82))
        }
    }
}

private struct ReaderChapterWebPicker: View {
    @ObservedObject var model: ReaderContainerModel
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(1 ... model.maxView, id: \.self) { view in
                        Button {
                            onSelect(view)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: view == model.visibleChapterDirectoryView ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(view == model.visibleChapterDirectoryView ? Color.accentColor : Color.secondary)

                                Text(L10n.string("reader.page_number_spaced", view))
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 0)

                                if view == model.visibleView {
                                    Text(L10n.string("common.current"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(view == model.visibleChapterDirectoryView ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(view)
                    }
                }
                .padding(8)
            }
            .frame(width: 200)
            .frame(maxHeight: 260)
            .onAppear {
                scrollToCurrentView(using: proxy)
            }
            .onChange(of: model.visibleChapterDirectoryView) { _, _ in
                scrollToCurrentView(using: proxy)
            }
        }
    }

    private func scrollToCurrentView(using proxy: ScrollViewProxy) {
        guard model.maxView > 0 else { return }
        let target = max(model.visibleChapterDirectoryView - 2, 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}

struct ReaderWebJumpSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        HStack {
                            Text(L10n.string("reader.current_web_page"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.currentWebViewText)
                                .fontWeight(.semibold)
                        }
                    }

                    Section(L10n.string("reader.select_web_page")) {
                        ForEach(1 ... model.maxView, id: \.self) { view in
                            Button {
                                onJump(view)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: view == model.visibleView ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(view == model.visibleView ? Color.accentColor : Color.secondary)

                                    Text(L10n.string("reader.page_number_spaced", view))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if view == model.visibleView {
                                        Text(L10n.string("common.current"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .id(view)
                        }
                    }
                }
                .navigationTitle(L10n.string("reader.jump_web_page"))
                .onAppear {
                    scrollToCurrentView(using: proxy)
                }
                .onChange(of: model.visibleView) { _, _ in
                    scrollToCurrentView(using: proxy)
                }
            }
        }
    }

    private func scrollToCurrentView(using proxy: ScrollViewProxy) {
        guard model.maxView > 0 else { return }
        let target = max(model.visibleView - 3, 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}

struct ReaderCachePanel: View {
    @ObservedObject var model: ReaderContainerModel
    let onShowProgress: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedViews: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.string("reader.cache_scope")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.cacheScopeTitle)
                            .font(.headline)
                        Text(model.cacheScopeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.string("reader.select_page")) {
                    Button(selectionState.isAllSelected ? L10n.string("common.deselect_all") : L10n.string("common.select_all")) {
                        if selectionState.isAllSelected {
                            selectedViews = []
                        } else {
                            selectedViews = Set(model.allCacheableViews)
                        }
                    }
                    .disabled(model.allCacheableViews.isEmpty)

                    if model.allCacheableViews.isEmpty {
                        Text(L10n.string("reader.no_cacheable_pages"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.allCacheableViews, id: \.self) { view in
                            Button {
                                toggleSelection(for: view)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedViews.contains(view) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedViews.contains(view) ? Color.accentColor : Color.secondary)
                                    Text(L10n.string("reader.page_number_spaced", view))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if model.cachedViews.contains(view) {
                                        Label(L10n.string("reader.cached"), systemImage: "checkmark.seal.fill")
                                            .labelStyle(.titleAndIcon)
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !selectedViews.isEmpty {
                    Section(L10n.string("reader.selected_content")) {
                        Text(L10n.string("reader.selected_pages", selectedViews.count))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.string("reader.cache_management"))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
            .task {
                await model.refreshCachedState()
            }
        }
    }

    private var selectionState: ReaderCacheSelectionState {
        model.cacheSelectionState(for: selectedViews)
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 12) {
                Button(L10n.string("reader.cache_action.cache")) {
                    model.startCaching(views: selectionState.uncachedSelectedViews)
                    onShowProgress()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectionState.canCache)

                Button(L10n.string("reader.cache_action.update")) {
                    model.updateCachedViews(selectionState.cachedSelectedViews)
                    onShowProgress()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(!selectionState.canUpdate)

                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        await model.deleteCachedViews(selectionState.cachedSelectedViews)
                        dismiss()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!selectionState.canDelete)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func toggleSelection(for view: Int) {
        if selectedViews.contains(view) {
            selectedViews.remove(view)
        } else {
            selectedViews.insert(view)
        }
    }
}

struct ReaderCacheProgressSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)

                VStack(spacing: 10) {
                    Text(titleText)
                        .font(.title3.weight(.semibold))

                    Text(detailText)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if let summary = model.cacheOperationState.summaryMessage, model.cacheOperationState.isFinished {
                        Text(summary)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(L10n.string("reader.cache_progress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if model.cacheOperationState.isFinished {
                            Button(L10n.string("common.done")) {
                                model.dismissCacheProgress()
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(L10n.string("reader.run_in_background")) {
                                model.hideCacheProgress()
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)

                            Button(L10n.string("common.stop"), role: .destructive) {
                                model.stopCaching()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var progressValue: Double {
        guard model.cacheOperationState.totalCount > 0 else { return 0 }
        return Double(model.cacheOperationState.completedCount) / Double(model.cacheOperationState.totalCount)
    }

    private var titleText: String {
        switch model.cacheOperationState.status {
        case .idle:
            return L10n.string("reader.cache_status.ready")
        case .running:
            return L10n.string("reader.cache_status.running")
        case .completed:
            return L10n.string("reader.cache_status.completed")
        case .cancelled:
            return L10n.string("reader.cache_status.cancelled")
        }
    }

    private var detailText: String {
        if model.cacheOperationState.isFinished {
            return L10n.string("reader.cache_detail.completed", model.cacheOperationState.completedCount, max(model.cacheOperationState.totalCount, 1))
        }

        if let currentView = model.cacheOperationState.currentView {
            return L10n.string("reader.cache_detail.running", currentView, model.cacheOperationState.completedCount, max(model.cacheOperationState.totalCount, 1))
        }

        return L10n.string("reader.cache_detail.ready")
    }
}
#endif
