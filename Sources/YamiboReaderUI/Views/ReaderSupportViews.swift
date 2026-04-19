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

private struct ReaderBlockView: View {
    let block: ReaderRenderedBlock
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState

    var body: some View {
        switch block {
        case let .text(text, _):
            Text(text)
                .font(.system(size: 22 * settings.fontScale))
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
        settings.usesNightMode ? Color.white.opacity(0.92) : .primary
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
                Text(model.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
                    Button("设置", action: onShowSettings)
                        .buttonStyle(.bordered)
                    Button("缓存", action: onShowCache)
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

private struct ReaderChromeIconButton: View {
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

struct ReaderChapterDrawerOverlay: View {
    @ObservedObject var model: ReaderContainerModel
    @Binding var isPresented: Bool
    let onSelect: (ReaderChapter) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if isPresented {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }

                    ReaderChapterDrawer(
                        model: model,
                        width: min(proxy.size.width * 0.75, 420),
                        onSelect: { chapter in
                            onSelect(chapter)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
        }
        .allowsHitTesting(isPresented)
    }
}

private struct ReaderChapterDrawer: View {
    @ObservedObject var model: ReaderContainerModel
    let width: CGFloat
    let onSelect: (ReaderChapter) -> Void

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.35)
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.chapters, id: \.startIndex) { chapter in
                            Button {
                                onSelect(chapter)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title)
                                        .font(.body)
                                        .foregroundStyle(isCurrent(chapter) ? Color.accentColor : .primary)
                                        .lineLimit(1)
                                    Text(chapterLocationText(for: chapter))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isCurrent(chapter) ? Color.accentColor.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .id(chapter.startIndex)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    scrollToCurrentChapter(using: scrollProxy)
                }
                .onChange(of: model.currentChapterIndex) { _, _ in
                    scrollToCurrentChapter(using: scrollProxy)
                }
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
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

struct ReaderSettingsPanel: View {
    @ObservedObject var model: ReaderContainerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ReaderSettingsSectionCard(title: "阅读模式", systemName: "book.pages") {
                        Picker("阅读模式", selection: readingModeBinding) {
                            ForEach(ReaderReadingMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    ReaderSettingsSectionCard(title: "文字排版", systemName: "textformat.size") {
                        ReaderSettingsSliderRow(
                            title: "字号",
                            valueText: String(format: "%.1f", model.settings.fontScale),
                            value: model.settings.fontScale,
                            range: 0.8 ... 1.8,
                            step: 0.1,
                            tint: .brown,
                            onChange: { model.updateFontScale($0) }
                        )

                        ReaderSettingsDivider()

                        ReaderSettingsSliderRow(
                            title: "行距",
                            valueText: String(format: "%.2f", model.settings.lineHeightScale),
                            value: model.settings.lineHeightScale,
                            range: 1.2 ... 2.2,
                            step: 0.1,
                            tint: .teal,
                            onChange: { model.updateLineHeightScale($0) }
                        )

                        ReaderSettingsDivider()

                        ReaderSettingsSliderRow(
                            title: "页边距",
                            valueText: String(format: "%.0f", model.settings.horizontalPadding),
                            value: model.settings.horizontalPadding,
                            range: 8 ... 36,
                            step: 2,
                            tint: .indigo,
                            onChange: { model.updateHorizontalPadding($0) }
                        )
                    }

                    ReaderSettingsPreviewCard(settings: model.settings)

                    ReaderSettingsSectionCard(title: "显示与转换", systemName: "text.justify") {
                        Picker("简繁转换", selection: translationModeBinding) {
                            ForEach(ReaderTranslationMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        ReaderSettingsDivider()

                        ReaderSettingsToggleRow(
                            title: "夜间模式",
                            subtitle: "降低亮度刺激，适合暗光环境",
                            systemName: "moon.fill",
                            isOn: nightModeBinding
                        )

                        ReaderSettingsDivider()

                        ReaderSettingsToggleRow(
                            title: "系统状态栏",
                            subtitle: "显示时间、电量和网络状态",
                            systemName: "wifi",
                            isOn: systemStatusBarBinding
                        )

                        ReaderSettingsDivider()

                        ReaderSettingsToggleRow(
                            title: "帖子图片",
                            subtitle: "关闭后更像纯文本阅读器，加载也更稳定",
                            systemName: "photo.on.rectangle.angled",
                            isOn: imageLoadingBinding
                        )
                    }

                    ReaderSettingsSectionCard(title: "页面背景", systemName: "swatchpalette") {
                        ReaderBackgroundStylePicker(
                            selectedStyle: model.settings.backgroundStyle,
                            usesNightMode: model.settings.usesNightMode,
                            onSelect: { model.updateBackgroundStyle($0) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var readingModeBinding: Binding<ReaderReadingMode> {
        Binding(
            get: { model.settings.readingMode },
            set: { model.updateReadingMode($0) }
        )
    }

    private var translationModeBinding: Binding<ReaderTranslationMode> {
        Binding(
            get: { model.settings.translationMode },
            set: { model.updateTranslationMode($0) }
        )
    }

    private var nightModeBinding: Binding<Bool> {
        Binding(
            get: { model.settings.usesNightMode },
            set: { model.updateNightMode($0) }
        )
    }

    private var imageLoadingBinding: Binding<Bool> {
        Binding(
            get: { model.settings.loadsInlineImages },
            set: { model.updateImageLoading($0) }
        )
    }

    private var systemStatusBarBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showsSystemStatusBar },
            set: { model.updateSystemStatusBarVisibility($0) }
        )
    }
}

private struct ReaderSettingsPreviewCard: View {
    let settings: ReaderAppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("实时预览")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Text("今夜，窗外的风像翻页声一样轻。")
                    .font(.system(size: 18 * settings.fontScale, weight: .semibold))
                    .foregroundStyle(textColor)
                Text("阅读设置会即时作用在正文中。你可以先把它调到舒服，再继续往下读。")
                    .font(.system(size: 15 * settings.fontScale))
                    .lineSpacing(6 * settings.lineHeightScale)
                    .foregroundStyle(textColor.opacity(0.9))
                    .padding(.trailing, settings.horizontalPadding)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(previewBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var previewBackground: some ShapeStyle {
        if settings.usesNightMode {
            return AnyShapeStyle(Color(red: 0.14, green: 0.15, blue: 0.17))
        }
        return AnyShapeStyle(backgroundColor)
    }

    private var backgroundColor: Color {
        switch settings.backgroundStyle {
        case .system:
            return Color(uiColor: .secondarySystemBackground)
        case .paper:
            return Color(red: 0.98, green: 0.95, blue: 0.88)
        case .mint:
            return Color(red: 0.91, green: 0.97, blue: 0.93)
        case .sakura:
            return Color(red: 0.98, green: 0.92, blue: 0.94)
        }
    }

    private var textColor: Color {
        settings.usesNightMode ? .white.opacity(0.92) : .primary
    }
}

private struct ReaderSettingsSectionCard<Content: View>: View {
    let title: String
    let systemName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemName)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ReaderSettingsSliderRow: View {
    let title: String
    let valueText: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                Text(valueText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                controlButton(systemName: "minus") {
                    onChange(max(range.lowerBound, value - step))
                }

                Slider(
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            let stepped = (newValue / step).rounded() * step
                            onChange(min(range.upperBound, max(range.lowerBound, stepped)))
                        }
                    ),
                    in: range
                )
                .tint(tint)

                controlButton(systemName: "plus") {
                    onChange(min(range.upperBound, value + step))
                }
            }
        }
    }

    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderSettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemName: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct ReaderBackgroundStylePicker: View {
    let selectedStyle: ReaderBackgroundStyle
    let usesNightMode: Bool
    let onSelect: (ReaderBackgroundStyle) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ReaderBackgroundStyle.allCases, id: \.self) { style in
                Button {
                    onSelect(style)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(backgroundColor(for: style, usesNightMode: usesNightMode))
                            .overlay(alignment: .topLeading) {
                                Text("Aa")
                                    .font(.system(size: 20, weight: .semibold, design: .serif))
                                    .foregroundStyle(usesNightMode ? Color.white.opacity(0.9) : Color.primary.opacity(0.85))
                                    .padding(12)
                            }
                            .frame(height: 78)

                        HStack {
                            Text(style.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedStyle == style {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selectedStyle == style ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReaderSettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.06))
    }
}

private func backgroundColor(for style: ReaderBackgroundStyle, usesNightMode: Bool) -> Color {
    if usesNightMode {
        return Color(red: 0.14, green: 0.15, blue: 0.17)
    }
    switch style {
    case .system:
        return Color(uiColor: .systemBackground)
    case .paper:
        return Color(red: 0.98, green: 0.95, blue: 0.88)
    case .mint:
        return Color(red: 0.91, green: 0.97, blue: 0.93)
    case .sakura:
        return Color(red: 0.98, green: 0.92, blue: 0.94)
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
