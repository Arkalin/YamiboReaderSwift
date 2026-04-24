import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

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
                Label(L10n.string("image.load_failed"), systemImage: "photo")
                    .foregroundColor(.secondary)
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
    let onOpenForum: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ReaderChromeIconButton(systemName: "xmark", title: L10n.string("common.close"), action: onClose)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ReaderChromeIconButton(systemName: "safari", title: L10n.string("common.original_post"), action: onOpenForum)
                    ReaderChromeIconButton(systemName: "arrow.clockwise", title: L10n.string("common.refresh"), action: onRefresh)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: model.title, textStyle: .headline)
                    .frame(height: MarqueeText.preferredHeight(for: .headline))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let sourceStatusText = model.sourceStatusText {
                    Text(sourceStatusText)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, max(topInset + 8, 20))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }
}

struct ReaderBottomChrome: View {
    @ObservedObject var model: ReaderContainerModel
    let bottomInset: CGFloat
    let onShowChapters: () -> Void
    let onShowWebJump: () -> Void
    let onStepWeb: (Int) -> Void
    let onShowSettings: () -> Void
    let onShowCache: () -> Void
    let onJumpChapter: (Int) -> Void
    let onProgressPreviewChange: (Double?, Bool) -> Void
    let onProgressCommit: (Double) -> Void

    @State private var sliderValue = 0.0
    @State private var isEditingSlider = false

    var body: some View {
        VStack(spacing: 14) {
            firstRow
            secondRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, max(bottomInset, 12))
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
        .onAppear {
            sliderValue = sliderModelValue
        }
        .onChange(of: sliderModelValue) { _, newValue in
            if !isEditingSlider {
                sliderValue = newValue
            }
        }
        .onChange(of: sliderValue) { _, newValue in
            if isEditingSlider {
                onProgressPreviewChange(newValue, true)
            }
        }
    }

    private var firstRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onShowChapters) {
                    Label(L10n.string("reader.chapters"), systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button(action: onShowSettings) {
                        Label(L10n.string("settings.title"), systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)

                    Button(action: onShowCache) {
                        Label(L10n.string("reader.cache"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                ReaderChromeIconButton(systemName: "chevron.left", title: L10n.string("reader.previous_web_page")) {
                    onStepWeb(-1)
                }
                .disabled(model.visibleView <= 1)

                Button(action: onShowWebJump) {
                    Text(model.currentWebViewText)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.maxView <= 1)

                ReaderChromeIconButton(systemName: "chevron.right", title: L10n.string("reader.next_web_page")) {
                    onStepWeb(1)
                }
                .disabled(model.visibleView >= model.maxView)
            }
        }
    }

    private var secondRow: some View {
        VStack(spacing: 8) {
            Text(progressLabelText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ReaderChromeIconButton(systemName: "backward.end.fill", title: L10n.string("reader.previous_chapter")) {
                    onJumpChapter(-1)
                }
                .disabled(!model.hasPreviousChapter)

                if sliderHasAvailableRange {
                    Slider(
                        value: $sliderValue,
                        in: sliderRange,
                        step: 1
                    ) { editing in
                        isEditingSlider = editing
                        if editing {
                            onProgressPreviewChange(sliderValue, true)
                        } else {
                            onProgressPreviewChange(nil, false)
                        }
                        if !editing {
                            onProgressCommit(sliderValue)
                        }
                    }
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.55))
                                .frame(width: 24, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                ReaderChromeIconButton(systemName: "forward.end.fill", title: L10n.string("reader.next_chapter")) {
                    onJumpChapter(1)
                }
                .disabled(!model.hasNextChapter)
            }
        }
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

    private var sliderHasAvailableRange: Bool {
        sliderRange.lowerBound < sliderRange.upperBound
    }

    private var progressLabelText: String {
        if model.settings.readingMode == .vertical {
            model.currentProgressPercentText
        } else {
            "\(model.currentRenderedPage) / \(model.renderedPageCount)"
        }
    }
}

struct ReaderChapterPreviewBubble: View {
    let title: String

    var body: some View {
        VStack {
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ReaderChromeIconButton: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }
}

struct ReaderChapterSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onSelect: (ReaderChapter) -> Void
    let onSelectWebView: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingWebPicker = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                List {

                    Section {
                        ForEach(model.chapters, id: \.startIndex) { chapter in
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
                                Text(model.directoryWebTitle)
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
                                guard view != model.visibleView else { return }
                                onSelectWebView(view)
                            }
                            .presentationCompactAdaptation(.popover)
                        }
                        .accessibilityLabel(model.directoryWebTitle)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.string("common.close")) {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.currentChapterIndex) { _, _ in
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.visibleView) { _, _ in
                    showingWebPicker = false
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
        chapter.title == model.currentChapterTitle
    }

    private func chapterLocationText(for chapter: ReaderChapter) -> String {
        if model.settings.readingMode == .vertical {
            guard model.renderedPageCount > 1 else { return "0%" }
            let fraction = Double(chapter.startIndex) / Double(model.renderedPageCount - 1)
            return "\(Int((fraction * 100).rounded()))%"
        }
        return L10n.string("reader.page_number_spaced", chapter.startIndex + 1)
    }

    private func scrollToCurrentChapter(using proxy: ScrollViewProxy) {
        guard let currentChapterIndex = model.currentChapterIndex,
              model.chapters.indices.contains(currentChapterIndex) else { return }
        let targetIndex = max(currentChapterIndex - 3, 0)
        let targetChapter = model.chapters[targetIndex]
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(targetChapter.startIndex, anchor: .top)
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
                                Image(systemName: view == model.visibleView ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(view == model.visibleView ? Color.accentColor : Color.secondary)

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
                                    .fill(view == model.visibleView ? Color.accentColor.opacity(0.12) : Color.clear)
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
            .onChange(of: model.visibleView) { _, _ in
                scrollToCurrentView(using: proxy)
            }
        }
    }

    private func scrollToCurrentView(using proxy: ScrollViewProxy) {
        guard model.maxView > 0 else { return }
        let target = max(model.visibleView - 2, 1)
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
