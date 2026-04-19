import SwiftUI
import YamiboReaderCore

enum ReaderChapterTextFormatter {
    static func split(text: String, chapterTitle: String?) -> (title: String?, body: String?) {
        guard let chapterTitle else {
            return (nil, nil)
        }

        let trimmedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return (nil, nil)
        }

        if text == trimmedTitle {
            return (trimmedTitle, nil)
        }

        let lineBreakCandidates = ["\r\n", "\n", "\r"]
        for separator in lineBreakCandidates {
            let prefixedTitle = trimmedTitle + separator
            if text.hasPrefix(prefixedTitle) {
                let body = String(text.dropFirst(prefixedTitle.count))
                return (trimmedTitle, separator + body)
            }
        }

        return (nil, nil)
    }
}

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

private struct ReaderBlockView: View {
    let block: ReaderRenderedBlock
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch block {
        case let .text(text, chapterTitle):
            styledReaderText(text, chapterTitle: chapterTitle)
                .lineSpacing(6 * settings.lineHeightScale)
                .foregroundColor(readerTextColor)
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

    private func styledReaderText(_ text: String, chapterTitle: String?) -> Text {
        let segments = ReaderChapterTextFormatter.split(text: text, chapterTitle: chapterTitle)
        guard let title = segments.title else {
            return Text(text)
                .font(readerFont())
                .kerning(readerKerning)
        }

        let titleText = Text(title)
            .font(readerFont(weight: .bold))
            .kerning(readerKerning)
        guard let body = segments.body else {
            return titleText
        }
        return titleText + Text(body)
            .font(readerFont())
            .kerning(readerKerning)
    }

    private func readerFont(weight: Font.Weight = .regular) -> Font {
        settings.fontFamily.font(size: 22 * settings.fontScale, weight: weight)
    }

    private var readerKerning: CGFloat {
        settings.fontFamily.kerning(size: 22 * settings.fontScale, scale: settings.characterSpacingScale)
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
                Label("图片加载失败", systemImage: "photo")
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
                ReaderChromeIconButton(systemName: "xmark", title: "关闭", action: onClose)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ReaderChromeIconButton(systemName: "safari", title: "原贴", action: onOpenForum)
                    ReaderChromeIconButton(systemName: "arrow.clockwise", title: "刷新", action: onRefresh)
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
                    Label("章节", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button(action: onShowSettings) {
                        Label("设置", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)

                    Button(action: onShowCache) {
                        Label("缓存", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                ReaderChromeIconButton(systemName: "chevron.left", title: "上一网页") {
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

                ReaderChromeIconButton(systemName: "chevron.right", title: "下一网页") {
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
                ReaderChromeIconButton(systemName: "backward.end.fill", title: "上一章") {
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

                ReaderChromeIconButton(systemName: "forward.end.fill", title: "下一章") {
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("章节目录")
                                .font(.title3.weight(.semibold))
                            if let summary = model.currentChapterTitle {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }

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
                .navigationTitle("章节目录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") {
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
        return "第 \(chapter.startIndex + 1) 页"
    }

    private func scrollToCurrentChapter(using proxy: ScrollViewProxy) {
        guard let currentChapterIndex = model.currentChapterIndex,
              model.chapters.indices.contains(currentChapterIndex) else { return }
        let targetIndex = max(currentChapterIndex - 3, 0)
        let targetChapter = model.chapters[targetIndex]
        proxy.scrollTo(targetChapter.startIndex, anchor: .top)
    }
}

struct ReaderWebJumpSheet: View {
    @ObservedObject var model: ReaderContainerModel
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("当前网页") {
                    Text(model.currentWebViewText)
                }

                Section("目标网页") {
                    TextField("输入网页页码", text: $input)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("网页跳转")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("跳转") {
                        let target = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) ?? model.visibleView
                        onJump(target)
                        dismiss()
                    }
                }
            }
            .onAppear {
                input = "\(model.visibleView)"
            }
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
                Section("缓存范围") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.cacheScopeTitle)
                            .font(.headline)
                        Text(model.cacheScopeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("选择页码") {
                    Button(selectionState.isAllSelected ? "取消全选" : "全选") {
                        if selectionState.isAllSelected {
                            selectedViews = []
                        } else {
                            selectedViews = Set(model.allCacheableViews)
                        }
                    }
                    .disabled(model.allCacheableViews.isEmpty)

                    if model.allCacheableViews.isEmpty {
                        Text("当前没有可缓存的网页页码")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.allCacheableViews, id: \.self) { view in
                            Button {
                                toggleSelection(for: view)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedViews.contains(view) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedViews.contains(view) ? Color.accentColor : Color.secondary)
                                    Text("第 \(view) 页")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if model.cachedViews.contains(view) {
                                        Label("已缓存", systemImage: "checkmark.seal.fill")
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
                    Section("已选内容") {
                        Text("已选择 \(selectedViews.count) 页")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("缓存管理")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
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
                Button("缓存") {
                    model.startCaching(views: selectionState.uncachedSelectedViews)
                    onShowProgress()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectionState.canCache)

                Button("更新") {
                    model.updateCachedViews(selectionState.cachedSelectedViews)
                    onShowProgress()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(!selectionState.canUpdate)

                Button("删除", role: .destructive) {
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
            .navigationTitle("缓存进度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if model.cacheOperationState.isFinished {
                            Button("完成") {
                                model.dismissCacheProgress()
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("后台运行") {
                                model.hideCacheProgress()
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("终止", role: .destructive) {
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
            return "准备缓存"
        case .running:
            return "正在缓存"
        case .completed:
            return "缓存完成"
        case .cancelled:
            return "缓存已终止"
        }
    }

    private var detailText: String {
        if model.cacheOperationState.isFinished {
            return "已完成 \(model.cacheOperationState.completedCount) / \(max(model.cacheOperationState.totalCount, 1)) 页"
        }

        if let currentView = model.cacheOperationState.currentView {
            return "正在缓存第 \(currentView) 页\n\(model.cacheOperationState.completedCount) / \(max(model.cacheOperationState.totalCount, 1))"
        }

        return "准备开始缓存…"
    }
}
#endif
