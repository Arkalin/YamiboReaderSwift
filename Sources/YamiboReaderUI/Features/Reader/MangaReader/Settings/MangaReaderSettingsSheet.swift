import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaReaderSettingsSheet: View {
    @ObservedObject var model: MangaReaderModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftSettings = MangaReaderSettings()
    @State private var hasLoadedDraft = false

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = max(318, min(382, proxy.size.height * 0.38)) + topInset
            let palette = MangaReaderSettingsPalette(colorScheme: colorScheme)

            ZStack(alignment: .top) {
                MangaReaderSettingsBackground(
                    palette: palette,
                    heroHeight: heroHeight
                )

                VStack(spacing: 0) {
                    MangaReaderSettingsHero(
                        settings: draftSettings,
                        palette: palette,
                        topInset: topInset,
                        height: heroHeight,
                        isPadDevice: isPadDevice,
                        onClose: { dismiss() },
                        onConfirm: commitDraft
                    )

                    MangaReaderSettingsSections(
                        settings: $draftSettings,
                        palette: palette,
                        isPadDevice: isPadDevice
                    )
                }
            }
        }
        .background(Color.clear)
        .onAppear(perform: loadDraftIfNeeded)
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        draftSettings = model.presentation.settings
        hasLoadedDraft = true
    }

    private func commitDraft() {
        let committedSettings = draftSettings
        dismiss()
        model.applySettings(committedSettings)
    }
}

private struct MangaReaderSettingsBackground: View {
    let palette: MangaReaderSettingsPalette
    let heroHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            palette.bodyBackground
                .ignoresSafeArea()

            palette.heroBackground
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
    }
}

private struct MangaReaderSettingsHero: View {
    let settings: MangaReaderSettings
    let palette: MangaReaderSettingsPalette
    let topInset: CGFloat
    let height: CGFloat
    let isPadDevice: Bool
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            MangaReaderSettingsPreviewSpread(
                settings: settings,
                palette: palette,
                isPadDevice: isPadDevice,
                height: height,
                contentTopPadding: topInset + 78
            )

            MangaReaderSettingsHeader(
                palette: palette,
                onClose: onClose,
                onConfirm: onConfirm
            )
            .padding(.horizontal, 16)
            .padding(.top, topInset + 12)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
    }
}

private struct MangaReaderSettingsHeader: View {
    let palette: MangaReaderSettingsPalette
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Text(L10n.string("settings.title"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack {
                ReaderChromeCircleButton(
                    systemName: "xmark",
                    title: L10n.string("common.close"),
                    tint: palette.primaryText,
                    action: onClose
                )
                Spacer()
                ReaderChromeCircleButton(
                    systemName: "checkmark",
                    title: L10n.string("common.done"),
                    tint: palette.confirmButtonBackground,
                    prominent: true,
                    action: onConfirm
                )
            }
        }
    }
}

private struct MangaReaderSettingsPreviewSpread: View {
    let settings: MangaReaderSettings
    let palette: MangaReaderSettingsPalette
    let isPadDevice: Bool
    let height: CGFloat
    let contentTopPadding: CGFloat

    private var selectedMode: MangaReaderSettingsModeOption {
        MangaReaderSettingsModeOption(settings)
    }

    private var showsTwoPagePreview: Bool {
        isPadDevice && settings.usesPagedMode && settings.showsTwoPagesInLandscapeOnPad
    }

    private var frameCornerRadii: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: 24,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: 24
        )
    }

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(cornerRadii: frameCornerRadii, style: .continuous)
                .fill(palette.previewFrameBackground)

            if selectedMode == .scroll {
                MangaReaderScrollPreviewPages(palette: palette)
                    .padding(.top, contentTopPadding)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            } else {
                HStack(spacing: showsTwoPagePreview ? 12 : 0) {
                    MangaReaderPagedPreviewPage(
                        palette: palette,
                        isTrailingPage: false,
                        scaleMode: settings.pageScaleMode,
                        pageTurnDirection: settings.pageTurnDirection
                    )
                    if showsTwoPagePreview {
                        MangaReaderPagedPreviewPage(
                            palette: palette,
                            isTrailingPage: true,
                            scaleMode: settings.pageScaleMode,
                            pageTurnDirection: settings.pageTurnDirection
                        )
                    }
                }
                .padding(.top, contentTopPadding)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
            }

            MangaReaderBrightnessPreviewOverlay(brightness: settings.brightness)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(UnevenRoundedRectangle(cornerRadii: frameCornerRadii, style: .continuous))
    }
}

private struct MangaReaderPagedPreviewPage: View {
    let palette: MangaReaderSettingsPalette
    let isTrailingPage: Bool
    let scaleMode: MangaPageScaleMode
    let pageTurnDirection: MangaPageTurnDirection

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.previewPageBackground)

            if scaleMode == .fitHeight {
                MangaReaderPagedPreviewFitHeightContent(
                    palette: palette,
                    isTrailingPage: isTrailingPage,
                    pageTurnDirection: pageTurnDirection
                )
            } else {
                MangaReaderPagedPreviewFitWidthContent(
                    palette: palette,
                    isTrailingPage: isTrailingPage
                )
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
    }
}

private struct MangaReaderPagedPreviewFitWidthContent: View {
    let palette: MangaReaderSettingsPalette
    let isTrailingPage: Bool

    var body: some View {
        MangaReaderPagedPreviewArtwork(
            palette: palette,
            isTrailingPage: isTrailingPage,
            panelWidth: nil,
            scale: 1
        )
        .padding(12)
    }
}

private struct MangaReaderPagedPreviewFitHeightContent: View {
    private static let artworkSize = CGSize(width: 156, height: 130)

    let palette: MangaReaderSettingsPalette
    let isTrailingPage: Bool
    let pageTurnDirection: MangaPageTurnDirection

    private var contentAlignment: Alignment {
        switch pageTurnDirection {
        case .leftToRight:
            .leading
        case .rightToLeft:
            .trailing
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 12
            let contentHeight = max(proxy.size.height - inset * 2, 1)
            let contentWidth = max(proxy.size.width - inset * 2, 1)
            let scale = contentHeight / Self.artworkSize.height
            let scaledPanelWidth = (Self.artworkSize.width - 8) / 2 * scale

            MangaReaderPagedPreviewArtwork(
                palette: palette,
                isTrailingPage: isTrailingPage,
                panelWidth: scaledPanelWidth,
                scale: scale
            )
            .frame(
                width: contentWidth,
                height: contentHeight,
                alignment: contentAlignment
            )
            .clipped()
            .padding(inset)
        }
    }
}

private struct MangaReaderPagedPreviewArtwork: View {
    let palette: MangaReaderSettingsPalette
    let isTrailingPage: Bool
    let panelWidth: CGFloat?
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(alignment: .top, spacing: 8 * scale) {
                MangaReaderPreviewPanel(
                    color: isTrailingPage ? palette.coolPanel : palette.warmPanel,
                    height: 50 * scale,
                    width: panelWidth
                )
                MangaReaderPreviewPanel(
                    color: palette.neutralPanel,
                    height: 50 * scale,
                    width: panelWidth
                )
            }

            MangaReaderPreviewPanel(
                color: isTrailingPage ? palette.neutralPanel : palette.coolPanel,
                height: 34 * scale,
                width: panelWidth.map { $0 * 2 + 8 * scale }
            )

            HStack(spacing: 8 * scale) {
                MangaReaderPreviewPanel(
                    color: palette.neutralPanel,
                    height: 30 * scale,
                    width: panelWidth
                )
                MangaReaderPreviewPanel(
                    color: isTrailingPage ? palette.warmPanel : palette.neutralPanel,
                    height: 30 * scale,
                    width: panelWidth
                )
            }
        }
    }
}

private struct MangaReaderScrollPreviewPages: View {
    let palette: MangaReaderSettingsPalette

    var body: some View {
        GeometryReader { proxy in
            let pageHeight = min(proxy.size.height, proxy.size.width / 0.72)
            let pageWidth = pageHeight * 0.72
            let visiblePageHeight = min(pageHeight * 0.48, proxy.size.height * 0.44)
            let topPageOffset = visiblePageHeight - pageHeight
            let bottomPageOffset = proxy.size.height - visiblePageHeight

            ZStack(alignment: .top) {
                MangaReaderVerticalPagedPreviewPair(
                    palette: palette,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    containerWidth: proxy.size.width,
                    topPageOffset: topPageOffset,
                    bottomPageOffset: bottomPageOffset
                )

                MangaReaderVerticalPagedPreviewPair(
                    palette: palette,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    containerWidth: proxy.size.width,
                    topPageOffset: topPageOffset,
                    bottomPageOffset: bottomPageOffset
                )
                .blur(radius: 7)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .mask(MangaReaderScrollPreviewEdgeBlurMask())
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .mask(MangaReaderScrollPreviewEdgeFade())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MangaReaderVerticalPagedPreviewPair: View {
    let palette: MangaReaderSettingsPalette
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let containerWidth: CGFloat
    let topPageOffset: CGFloat
    let bottomPageOffset: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            MangaReaderPagedPreviewPage(
                palette: palette,
                isTrailingPage: false,
                scaleMode: .fitWidth,
                pageTurnDirection: .rightToLeft
            )
            .frame(width: pageWidth, height: pageHeight)
            .offset(y: topPageOffset)

            MangaReaderPagedPreviewPage(
                palette: palette,
                isTrailingPage: false,
                scaleMode: .fitWidth,
                pageTurnDirection: .rightToLeft
            )
            .frame(width: pageWidth, height: pageHeight)
            .offset(y: bottomPageOffset)
        }
        .frame(width: containerWidth, height: pageHeight, alignment: .top)
    }
}

private struct MangaReaderScrollPreviewEdgeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.35), location: 0.08),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.78),
                .init(color: .black.opacity(0.35), location: 0.92),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct MangaReaderScrollPreviewEdgeBlurMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.14),
                .init(color: .clear, location: 0.30),
                .init(color: .clear, location: 0.70),
                .init(color: .black, location: 0.86),
                .init(color: .black, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct MangaReaderPreviewPanel: View {
    let color: Color
    let height: CGFloat
    var width: CGFloat?

    private var maximumWidth: CGFloat? {
        width == nil ? .infinity : nil
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: width)
            .frame(maxWidth: maximumWidth)
            .frame(height: height)
    }
}

private struct MangaReaderBrightnessPreviewOverlay: View {
    let brightness: Double

    var body: some View {
        let delta = brightness - 1

        if delta < 0 {
            Color.black.opacity(min(0.7, abs(delta)))
                .allowsHitTesting(false)
        } else if delta > 0 {
            Color.white.opacity(min(0.18, delta * 0.18))
                .allowsHitTesting(false)
        }
    }
}

private struct MangaReaderSettingsSections: View {
    @Binding var settings: MangaReaderSettings
    let palette: MangaReaderSettingsPalette
    let isPadDevice: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                MangaReaderSettingsDisplaySection(
                    settings: $settings,
                    palette: palette
                )

                MangaReaderSettingsPagingSection(
                    settings: $settings,
                    palette: palette,
                    isPadDevice: isPadDevice
                )
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MangaReaderSettingsDisplaySection: View {
    @Binding var settings: MangaReaderSettings
    let palette: MangaReaderSettingsPalette

    var body: some View {
        MangaReaderSettingsCardSection(
            title: L10n.string("manga.settings.section.display"),
            palette: palette
        ) {
            MangaReaderBrightnessRow(
                value: $settings.brightness,
                palette: palette
            )
            MangaReaderSettingsDivider(palette: palette)
            MangaReaderSettingsToggleRow(
                title: L10n.string("manga.double_tap_zoom"),
                palette: palette,
                isOn: $settings.zoomEnabled
            )
        }
    }
}

private struct MangaReaderSettingsPagingSection: View {
    @Binding var settings: MangaReaderSettings
    let palette: MangaReaderSettingsPalette
    let isPadDevice: Bool

    var body: some View {
        MangaReaderSettingsCardSection(
            title: L10n.string("manga.settings.section.paging"),
            palette: palette
        ) {
            MangaReaderModePicker(
                settings: $settings,
                palette: palette
            )

            if settings.usesPagedMode {
                if isPadDevice {
                    MangaReaderSettingsDivider(palette: palette)
                    MangaReaderSettingsToggleRow(
                        title: L10n.string("reader.two_pages_landscape"),
                        palette: palette,
                        isOn: $settings.showsTwoPagesInLandscapeOnPad
                    )
                }
                MangaReaderSettingsDivider(palette: palette)
                MangaReaderDirectionPicker(
                    direction: $settings.pageTurnDirection,
                    palette: palette
                )
                MangaReaderSettingsDivider(palette: palette)
                MangaReaderPageScaleModeMenuRow(
                    scaleMode: $settings.pageScaleMode,
                    palette: palette
                )
            }
        }
    }
}

private struct MangaReaderSettingsCardSection<Content: View>: View {
    let title: String
    let palette: MangaReaderSettingsPalette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(palette.cardStroke, lineWidth: 1)
            }
        }
    }
}

private struct MangaReaderBrightnessRow: View {
    @Binding var value: Double
    let palette: MangaReaderSettingsPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(L10n.string("manga.brightness"))
                        .font(.title3.weight(.semibold))
                } icon: {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(palette.warmAccent)
                }
                .foregroundStyle(palette.primaryText)

                Spacer()

                Text("\(Int((value * 100).rounded()))%")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }

            HStack(spacing: 14) {
                MangaReaderRoundIconButton(
                    systemName: "minus",
                    palette: palette
                ) {
                    value = max(0.25, value - 0.05)
                }

                Slider(value: $value, in: 0.25 ... 1.5, step: 0.05)
                    .tint(palette.warmAccent)

                MangaReaderRoundIconButton(
                    systemName: "plus",
                    palette: palette
                ) {
                    value = min(1.5, value + 0.05)
                }
            }
        }
    }
}

private struct MangaReaderRoundIconButton: View {
    let systemName: String
    let palette: MangaReaderSettingsPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 42, height: 42)
                .background(palette.segmentedBackground, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct MangaReaderSettingsToggleRow: View {
    let title: String
    let palette: MangaReaderSettingsPalette
    var statusText: String?
    var isEnabled = true
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if let statusText {
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .opacity(isEnabled ? 1 : 0.62)
    }
}

private struct MangaReaderModePicker: View {
    @Binding var settings: MangaReaderSettings
    let palette: MangaReaderSettingsPalette

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var selectedMode: MangaReaderSettingsModeOption {
        MangaReaderSettingsModeOption(settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("reading_mode.title"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MangaReaderSettingsModeOption.allCases, id: \.self) { option in
                    MangaReaderModeButton(
                        option: option,
                        isSelected: selectedMode == option,
                        palette: palette
                    ) {
                        settings.selectMode(option)
                    }
                }
            }
        }
    }
}

private struct MangaReaderModeButton: View {
    let option: MangaReaderSettingsModeOption
    let isSelected: Bool
    let palette: MangaReaderSettingsPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: option.systemImageName)
                    .font(.headline.weight(.semibold))
                    .frame(width: 24)

                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isSelected ? palette.selectedControlText : palette.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(
                isSelected ? palette.selectedControlBackground : palette.segmentedBackground,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MangaReaderDirectionPicker: View {
    @Binding var direction: MangaPageTurnDirection
    let palette: MangaReaderSettingsPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("manga.page_turn_direction"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack(spacing: 8) {
                ForEach(MangaPageTurnDirection.allCases, id: \.self) { option in
                    MangaReaderDirectionButton(
                        direction: option,
                        isSelected: direction == option,
                        palette: palette
                    ) {
                        direction = option
                    }
                }
            }
            .padding(6)
            .background(palette.segmentedBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct MangaReaderDirectionButton: View {
    let direction: MangaPageTurnDirection
    let isSelected: Bool
    let palette: MangaReaderSettingsPalette
    let action: () -> Void

    private var systemImageName: String {
        switch direction {
        case .rightToLeft:
            "arrow.left"
        case .leftToRight:
            "arrow.right"
        }
    }

    var body: some View {
        Button(action: action) {
            Label(direction.title, systemImage: systemImageName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? palette.selectedControlText : palette.primaryText)
                .background(
                    isSelected ? palette.selectedControlBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MangaReaderPageScaleModeMenuRow: View {
    @Binding var scaleMode: MangaPageScaleMode
    let palette: MangaReaderSettingsPalette

    var body: some View {
        Menu {
            Picker(
                L10n.string("manga.page_scale_mode"),
                selection: $scaleMode
            ) {
                ForEach(MangaPageScaleMode.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImageName)
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(L10n.string("manga.page_scale_mode"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Text(scaleMode.title)
                        .font(.system(size: 18))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryText.opacity(0.75))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MangaReaderSettingsDivider: View {
    let palette: MangaReaderSettingsPalette

    var body: some View {
        Divider().overlay(palette.divider)
    }
}

private enum MangaReaderSettingsModeOption: CaseIterable, Hashable {
    case slide
    case pageCurl
    case quickFade
    case scroll

    init(_ settings: MangaReaderSettings) {
        switch settings.readingMode {
        case .paged:
            switch settings.pagedTurnStyle {
            case .slide:
                self = .slide
            case .pageCurl:
                self = .pageCurl
            case .quickFade:
                self = .quickFade
            }
        case .vertical:
            self = .scroll
        }
    }

    var title: String {
        switch self {
        case .slide:
            L10n.string("reading_mode.slide")
        case .pageCurl:
            L10n.string("reading_mode.page_curl")
        case .quickFade:
            L10n.string("reading_mode.quick_fade")
        case .scroll:
            L10n.string("reading_mode.scroll")
        }
    }

    var systemImageName: String {
        switch self {
        case .slide:
            "arrow.left.to.line.square"
        case .pageCurl:
            "doc"
        case .quickFade:
            "bolt.square"
        case .scroll:
            "text.page"
        }
    }

    var pagedTurnStyle: ReaderPagedTurnStyle? {
        switch self {
        case .slide:
            .slide
        case .pageCurl:
            .pageCurl
        case .quickFade:
            .quickFade
        case .scroll:
            nil
        }
    }
}

private extension MangaPageScaleMode {
    var systemImageName: String {
        switch self {
        case .fitHeight:
            "arrow.up.and.down"
        case .fitWidth:
            "arrow.left.and.right"
        }
    }
}

private struct MangaReaderSettingsPalette {
    let heroBackground: Color
    let bodyBackground: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let segmentedBackground: Color
    let selectedControlBackground: Color
    let selectedControlText: Color
    let divider: Color
    let cardStroke: Color
    let accent: Color
    let warmAccent: Color
    let confirmButtonBackground: Color
    let previewFrameBackground: Color
    let previewPageBackground: Color
    let warmPanel: Color
    let coolPanel: Color
    let neutralPanel: Color

    init(colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark
        let cool = Color(red: 0.10, green: 0.64, blue: 0.68)
        let warm = Color(red: 0.93, green: 0.36, blue: 0.43)
        let controlAccent = isDark ? Color(red: 0.78, green: 0.58, blue: 0.42) : Color.accentColor
        let ink = Color(red: 0.08, green: 0.08, blue: 0.09)

        if isDark {
            let sheetBackground = Color(red: 0.10, green: 0.10, blue: 0.11)
            bodyBackground = sheetBackground
            heroBackground = sheetBackground
            cardBackground = Color.white.opacity(0.075)
            primaryText = Color.white.opacity(0.92)
            secondaryText = Color.white.opacity(0.66)
            segmentedBackground = Color.white.opacity(0.07)
            selectedControlBackground = controlAccent
            selectedControlText = Color.white
            divider = Color.white.opacity(0.08)
            cardStroke = Color.white.opacity(0.10)
            previewFrameBackground = Color.black.opacity(0.26)
            previewPageBackground = Color(red: 0.88, green: 0.88, blue: 0.84)
            neutralPanel = Color.black.opacity(0.16)
            confirmButtonBackground = sheetBackground.mix(with: Color(red: 0.44, green: 0.39, blue: 0.30), amount: 0.58)
        } else {
            let heroSurfaceBackground = Color.white
            heroBackground = heroSurfaceBackground
            bodyBackground = Color.white
            cardBackground = Color.white.opacity(0.78)
            primaryText = ink
            secondaryText = Color.black.opacity(0.55)
            segmentedBackground = Color.black.opacity(0.045)
            selectedControlBackground = controlAccent
            selectedControlText = Color.white
            divider = Color.black.opacity(0.08)
            cardStroke = Color.black.opacity(0.08)
            previewFrameBackground = Color.black.opacity(0.08)
            previewPageBackground = Color.white
            neutralPanel = Color.black.opacity(0.08)
            confirmButtonBackground = heroSurfaceBackground.mix(
                with: Color(red: 0.31, green: 0.26, blue: 0.18),
                amount: 0.72
            )
        }

        accent = controlAccent
        warmAccent = controlAccent
        warmPanel = warm.opacity(isDark ? 0.52 : 0.34)
        coolPanel = cool.opacity(isDark ? 0.52 : 0.30)
    }
}

private extension Color {
    func mix(with other: Color, amount: Double) -> Color {
        let clamped = min(max(amount, 0), 1)
        let lhs = UIColor(self)
        let rhs = UIColor(other)

        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        return Color(
            red: lr + (rr - lr) * clamped,
            green: lg + (rg - lg) * clamped,
            blue: lb + (rb - lb) * clamped,
            opacity: la + (ra - la) * clamped
        )
    }
}

private extension MangaReaderSettings {
    var usesPagedMode: Bool {
        readingMode == .paged
    }

    mutating func selectMode(_ option: MangaReaderSettingsModeOption) {
        if let pagedTurnStyle = option.pagedTurnStyle {
            readingMode = .paged
            self.pagedTurnStyle = pagedTurnStyle
        } else {
            readingMode = .vertical
        }
    }
}

#endif
