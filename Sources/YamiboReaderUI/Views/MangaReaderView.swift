import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

public struct MangaReaderView: View {
    @StateObject private var model: MangaReaderModel
    @State private var showingSettings = false
    @State private var showingDirectorySheet = false
    @State private var showingChrome = true
    private let appModel: YamiboAppModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        _model = StateObject(wrappedValue: MangaReaderModel(context: context, appContext: appModel.appContext))
        self.appModel = appModel
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                content(proxy: proxy)
                brightnessOverlay
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showingChrome {
                    topChrome(topInset: proxy.safeAreaInsets.top)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showingChrome {
                    bottomChrome(bottomInset: proxy.safeAreaInsets.bottom)
                }
            }
            .task {
                await model.prepare()
            }
            .onDisappear {
                Task { await model.saveProgress() }
            }
            .onChange(of: model.fallbackWebContext) { _, newValue in
                if let newValue {
                    appModel.fallbackMangaToWeb(newValue)
                    model.fallbackWebContext = nil
                }
            }
            .sheet(isPresented: $showingSettings) {
                MangaSettingsSheet(model: model)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingDirectorySheet) {
                MangaDirectorySheet(model: model)
            }
            .statusBar(hidden: !model.settings.showsSystemStatusBar || !showingChrome)
        }
    }

    @ViewBuilder
    private func content(proxy: GeometryProxy) -> some View {
        if model.isLoading && model.pages.isEmpty {
            ProgressView("加载漫画中…")
                .tint(.white)
        } else if let errorMessage = model.errorMessage, model.pages.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text(errorMessage)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("返回网页") {
                        appModel.fallbackMangaToWeb(
                            model.makeWebFallbackContext(
                                currentURL: model.context.chapterURL,
                                initialPage: model.context.initialPage
                            )
                        )
                    }
                    .buttonStyle(.bordered)
                    Button("重试") {
                        Task { await model.retryCurrentChapter() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        } else if model.settings.readingMode == .paged {
            pagedContent
        } else {
            verticalContent
        }
    }

    private var pagedContent: some View {
        TabView(selection: $model.currentPageIndex) {
            ForEach(model.pages.indices, id: \.self) { index in
                MangaPageContent(
                    page: model.pages[index],
                    refererURL: model.pages[index].chapterURL,
                    imageRepository: appModel.appContext.mangaImageRepository,
                    zoomEnabled: model.settings.zoomEnabled,
                    onToggleChrome: { showingChrome.toggle() }
                )
                .tag(index)
                .padding(.vertical, 12)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: model.currentPageIndex) { _, newValue in
            model.updateCurrentPage(newValue)
        }
    }

    private var verticalContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 12) {
                    ForEach(model.pages.indices, id: \.self) { index in
                        MangaPageContent(
                            page: model.pages[index],
                            refererURL: model.pages[index].chapterURL,
                            imageRepository: appModel.appContext.mangaImageRepository,
                            zoomEnabled: model.settings.zoomEnabled,
                            onToggleChrome: { showingChrome.toggle() }
                        )
                        .id(index)
                        .onAppear {
                            model.updateCurrentPage(index)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: model.scrollRequestIndex) { _, request in
                guard let request else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(request, anchor: .top)
                }
                model.scrollRequestIndex = nil
            }
        }
    }

    private func topChrome(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                appModel.dismissMangaRestoringWebIfNeeded()
            } label: {
                Image(systemName: "xmark")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.currentPageText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            Button("原帖") {
                appModel.dismissManga(openThreadInForum: model.context.originalThreadURL)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.top, max(12, topInset))
        .padding(.bottom, 10)
        .background(.black.opacity(0.86))
    }

    private func bottomChrome(bottomInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    Task { await model.jumpToAdjacentChapter(-1) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.hasPreviousChapter)

                Slider(
                    value: Binding(
                        get: { Double(model.currentPage?.localIndex ?? 0) },
                        set: { newValue in
                            guard let currentPage = model.currentPage else { return }
                            let target = model.pages.firstIndex {
                                $0.chapterURL == currentPage.chapterURL && $0.localIndex == Int(newValue.rounded())
                            } ?? model.currentPageIndex
                            model.currentPageIndex = target
                            model.updateCurrentPage(target)
                        }
                    ),
                    in: 0 ... Double(max(0, (model.currentPage?.chapterTotalPages ?? 1) - 1))
                )

                Button {
                    Task { await model.jumpToAdjacentChapter(1) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.hasNextChapter)
            }
            .tint(.white)

            HStack(spacing: 24) {
                Button("设置") {
                    showingSettings = true
                }
                Button("目录") {
                    showingDirectorySheet = true
                }
                Text(model.currentPageText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, max(16, bottomInset))
        .background(.black.opacity(0.88))
    }

    private var brightnessOverlay: some View {
        let delta = model.settings.brightness - 1
        return Group {
            if delta < 0 {
                Color.black.opacity(min(0.7, abs(delta)))
            } else if delta > 0 {
                Color.white.opacity(min(0.18, delta * 0.18))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct MangaSettingsSheet: View {
    @ObservedObject var model: MangaReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("阅读模式", selection: Binding(
                    get: { model.settings.readingMode },
                    set: {
                        var updated = model.settings
                        updated.readingMode = $0
                        model.applySettings(updated)
                    }
                )) {
                    ForEach(MangaReadingMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("启用缩放", isOn: Binding(
                    get: { model.settings.zoomEnabled },
                    set: {
                        var updated = model.settings
                        updated.zoomEnabled = $0
                        model.applySettings(updated)
                    }
                ))

                Toggle("显示系统状态栏", isOn: Binding(
                    get: { model.settings.showsSystemStatusBar },
                    set: {
                        var updated = model.settings
                        updated.showsSystemStatusBar = $0
                        model.applySettings(updated)
                    }
                ))

                VStack(alignment: .leading, spacing: 8) {
                    Text("亮度")
                    Slider(
                        value: Binding(
                            get: { model.settings.brightness },
                            set: {
                                var updated = model.settings
                                updated.brightness = $0
                                model.applySettings(updated)
                            }
                        ),
                        in: 0.25 ... 1.5
                    )
                }
            }
            .navigationTitle("漫画设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct MangaDirectorySheet: View {
    @ObservedObject var model: MangaReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle = ""
    @State private var editedPrimaryKeyword = ""
    @State private var editedSecondaryKeyword = ""
    @State private var isHeaderExpanded = false
    @State private var didLoadDraft = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    chaptersSection
                    correctionSection
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                guard !didLoadDraft else { return }
                let draft = model.makeDirectoryEditDraft()
                editedTitle = draft.title
                editedPrimaryKeyword = draft.primaryKeyword
                editedSecondaryKeyword = draft.secondaryKeyword
                didLoadDraft = true
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.currentDirectoryTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(isHeaderExpanded ? nil : 1)
                .onTapGesture {
                    isHeaderExpanded.toggle()
                }

            HStack(spacing: 10) {
                ForEach(MangaDirectorySortOrder.allCases, id: \.self) { sortOrder in
                    Button(sortOrder.title) {
                        model.applyDirectorySortOrder(sortOrder)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.settings.directorySortOrder == sortOrder ? .accentColor : .gray.opacity(0.35))
                    .foregroundStyle(model.settings.directorySortOrder == sortOrder ? .white : .primary)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 12) {
                if let latestChapterText = model.latestChapterText {
                    Text(latestChapterText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(model.directoryUpdateButtonTitle) {
                    Task { await model.updateDirectoryFromPanel() }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isDirectoryUpdateSearchMode ? .indigo : .orange)
                .disabled(!model.isDirectoryUpdateButtonEnabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("章节列表")
                .font(.headline)

            if model.sortedDirectoryChapters.isEmpty {
                ContentUnavailableView("暂无章节", systemImage: "books.vertical")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.sortedDirectoryChapters) { chapter in
                        MangaDirectoryChapterRow(
                            chapter: chapter,
                            isCurrent: chapter.tid == model.currentPage?.tid
                        ) {
                            Task {
                                await model.jumpToChapter(chapter)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    private var correctionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("校正漫画信息")
                .font(.headline)

            TextField("漫画名称", text: $editedTitle)
                .textFieldStyle(.roundedBorder)

            TextField("关键词 1", text: $editedPrimaryKeyword)
                .textFieldStyle(.roundedBorder)

            TextField("关键词 2（可选）", text: $editedSecondaryKeyword)
                .textFieldStyle(.roundedBorder)

            Button("保存校正") {
                Task {
                    await model.renameDirectory(
                        cleanBookName: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        searchKeyword: combinedSearchKeyword
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var combinedSearchKeyword: String {
        [editedPrimaryKeyword, editedSecondaryKeyword]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct MangaDirectoryChapterRow: View {
    let chapter: MangaChapter
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(MangaChapterDisplayFormatter.displayNumber(for: chapter))
                .font(.caption.weight(.bold))
                .foregroundStyle(isCurrent ? .orange : .secondary)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                TruncationAwareText(
                    chapter.rawTitle,
                    font: UIFont.preferredFont(forTextStyle: .subheadline),
                    lineLimit: isExpanded ? nil : 1,
                    isTruncated: $isTruncated
                )
                .font(.subheadline)
                .foregroundStyle(isCurrent ? .primary : .primary)

                if isTruncated {
                    Button(isExpanded ? "收起" : "展开") {
                        isExpanded.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            if isCurrent {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.orange.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isCurrent else { return }
            onSelect()
        }
    }
}

private struct TruncationAwareText: View {
    let text: String
    let font: UIFont
    let lineLimit: Int?
    @Binding var isTruncated: Bool

    @State private var availableWidth: CGFloat = 0

    init(
        _ text: String,
        font: UIFont,
        lineLimit: Int?,
        isTruncated: Binding<Bool>
    ) {
        self.text = text
        self.font = font
        self.lineLimit = lineLimit
        _isTruncated = isTruncated
    }

    var body: some View {
        Text(text)
            .lineLimit(lineLimit)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            availableWidth = proxy.size.width
                            updateTruncation()
                        }
                        .onChange(of: proxy.size.width) { _, newValue in
                            availableWidth = newValue
                            updateTruncation()
                        }
                }
            )
    }

    private func updateTruncation() {
        guard availableWidth > 0 else { return }
        let rect = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        .boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        isTruncated = rect.height > (font.lineHeight * 1.2)
    }
}

private struct MangaPageContent: View {
    let page: MangaPage
    let refererURL: URL
    let imageRepository: MangaImageRepository
    let zoomEnabled: Bool
    let onToggleChrome: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            MangaAuthenticatedImage(
                url: page.imageURL,
                refererURL: refererURL,
                imageRepository: imageRepository,
                zoomEnabled: zoomEnabled
            )
            Text(page.chapterTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleChrome()
        }
    }
}

@MainActor
private final class MangaImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false

    private let url: URL
    private let refererURL: URL
    private let imageRepository: MangaImageRepository
    private var didStart = false

    init(url: URL, refererURL: URL, imageRepository: MangaImageRepository) {
        self.url = url
        self.refererURL = refererURL
        self.imageRepository = imageRepository
    }

    func loadIfNeeded() async {
        guard !didStart, image == nil else { return }
        didStart = true

        do {
            let data = try await imageRepository.imageData(
                for: MangaImageRequest(
                    imageURL: url,
                    refererURL: refererURL
                )
            )
            guard let image = UIImage(data: data) else {
                didFail = true
                return
            }
            self.image = image
        } catch {
            didFail = true
        }
    }
}

private struct MangaAuthenticatedImage: View {
    @StateObject private var loader: MangaImageLoader
    let zoomEnabled: Bool
    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    init(
        url: URL,
        refererURL: URL,
        imageRepository: MangaImageRepository,
        zoomEnabled: Bool
    ) {
        _loader = StateObject(
            wrappedValue: MangaImageLoader(
                url: url,
                refererURL: refererURL,
                imageRepository: imageRepository
            )
        )
        self.zoomEnabled = zoomEnabled
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(steadyScale * gestureScale)
                    .offset(
                        x: steadyOffset.width + gestureOffset.width,
                        y: steadyOffset.height + gestureOffset.height
                    )
                    .animation(.easeOut(duration: 0.2), value: steadyScale)
                    .animation(.easeOut(duration: 0.2), value: steadyOffset)
            } else if loader.didFail {
                Label("图片加载失败", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            } else {
                ProgressView()
                    .padding(.vertical, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .task { await loader.loadIfNeeded() }
        .simultaneousGesture(doubleTapGesture)
        .simultaneousGesture(magnifyGesture)
        .simultaneousGesture(dragGesture)
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                guard zoomEnabled else { return }
                if steadyScale > 1.05 {
                    steadyScale = 1
                    steadyOffset = .zero
                } else {
                    steadyScale = 2
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard zoomEnabled else { return }
                gestureScale = value.magnification
            }
            .onEnded { value in
                guard zoomEnabled else { return }
                steadyScale = min(4, max(1, steadyScale * value.magnification))
                gestureScale = 1
                if steadyScale <= 1.01 {
                    steadyScale = 1
                    steadyOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomEnabled, steadyScale > 1 else { return }
                gestureOffset = value.translation
            }
            .onEnded { value in
                guard zoomEnabled, steadyScale > 1 else { return }
                steadyOffset.width += value.translation.width
                steadyOffset.height += value.translation.height
                gestureOffset = .zero
                if steadyScale <= 1.05 {
                    steadyOffset = .zero
                }
            }
    }
}
#else

public struct MangaReaderView: View {
    private let context: MangaLaunchContext
    private let appModel: YamiboAppModel

    public init(context: MangaLaunchContext, appModel: YamiboAppModel) {
        self.context = context
        self.appModel = appModel
    }

    public var body: some View {
        Text("漫画阅读仅在 iOS 端启用")
            .padding()
    }
}
#endif
