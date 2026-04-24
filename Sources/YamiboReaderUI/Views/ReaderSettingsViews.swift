import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

private extension Font.Weight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

struct ReaderSettingsPanel: View {
    @ObservedObject var model: ReaderContainerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftSettings = ReaderAppearanceSettings()
    @State private var draftApplePencilPageTurnSettings = ApplePencilPageTurnSettings()
    @State private var hasLoadedDraft = false
    private static let fallbackPreviewText = L10n.string("reader.settings.preview_fallback")
    private static let previewCharacterCount = 200

    private var showsApplePencilSection: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && draftSettings.readingMode == .paged
#else
        false
#endif
    }

    private var showsTwoPageToggle: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && draftSettings.readingMode == .paged
#else
        false
#endif
    }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let heroHeight = max(300, min(356, proxy.size.height * 0.34)) + topInset
            let palette = ReaderBooksSheetPalette(settings: draftSettings, colorScheme: colorScheme)

            ZStack(alignment: .top) {
                ReaderBooksUnifiedSheetBackground(
                    palette: palette,
                    heroHeight: heroHeight
                )

                VStack(spacing: 0) {
                    ReaderBooksHeroSection(
                        settings: draftSettings,
                        palette: palette,
                        previewText: model.previewText(
                            translationMode: draftSettings.translationMode,
                            characterCount: Self.previewCharacterCount,
                            fallback: Self.fallbackPreviewText
                        ),
                        topInset: topInset,
                        height: heroHeight,
                        onClose: { dismiss() },
                        onConfirm: {
                            model.applySettings(
                                draftSettings,
                                applePencilPageTurnSettings: draftApplePencilPageTurnSettings
                            )
                            dismiss()
                        }
                    )

                    ScrollView {
                        VStack(spacing: 24) {
                            ReaderBooksTextSection(
                                settings: draftSettings,
                                palette: palette,
                                onFontScaleChange: setFontScale,
                                onFontFamilyChange: setFontFamily
                            )

                            ReaderBooksLayoutSection(
                                settings: draftSettings,
                                palette: palette,
                                onLineHeightChange: setLineHeightScale,
                                onCharacterSpacingChange: setCharacterSpacingScale,
                                onHorizontalPaddingChange: setHorizontalPadding
                            )

                            ReaderBooksStandaloneToggleSection(
                                title: L10n.string("reader.justified_text"),
                                palette: palette,
                                isOn: Binding(
                                    get: { draftSettings.usesJustifiedText },
                                    set: { draftSettings.usesJustifiedText = $0 }
                                )
                            )

                            ReaderBooksDisplaySection(
                                settings: draftSettings,
                                palette: palette,
                                colorScheme: colorScheme,
                                showsTwoPageToggle: showsTwoPageToggle,
                                showsTwoPagesInLandscapeOnPad: Binding(
                                    get: { draftSettings.showsTwoPagesInLandscapeOnPad },
                                    set: { draftSettings.showsTwoPagesInLandscapeOnPad = $0 }
                                ),
                                onBackgroundStyleChange: setBackgroundStyle,
                                onReadingModeChange: setReadingMode,
                                onSelectOriginalText: { setTranslationMode(.none) },
                                onSelectSimplifiedText: { setTranslationMode(.simplified) },
                                onSelectTraditionalText: { setTranslationMode(.traditional) }
                            )

                            ReaderBooksMiscSection(
                                palette: palette,
                                loadsInlineImages: draftSettings.loadsInlineImages,
                                onLoadsInlineImagesChange: setImageLoading
                            )

                            if showsApplePencilSection {
                                ReaderBooksApplePencilSection(
                                    settings: draftApplePencilPageTurnSettings,
                                    palette: palette,
                                    isEnabled: Binding(
                                        get: { draftApplePencilPageTurnSettings.isEnabled },
                                        set: { draftApplePencilPageTurnSettings.isEnabled = $0 }
                                    ),
                                    onBehaviorChange: setApplePencilPageTurnBehavior
                                )
                            }
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Color.clear)
        }
        .background(Color.clear)
        .onAppear {
            guard !hasLoadedDraft else { return }
            draftSettings = model.settings
            draftApplePencilPageTurnSettings = model.applePencilPageTurnSettings
            hasLoadedDraft = true
        }
    }

    private func setFontScale(_ value: Double) { draftSettings.fontScale = value }
    private func setFontFamily(_ value: ReaderFontFamily) { draftSettings.fontFamily = value }
    private func setLineHeightScale(_ value: Double) { draftSettings.lineHeightScale = value }
    private func setCharacterSpacingScale(_ value: Double) { draftSettings.characterSpacingScale = value }
    private func setHorizontalPadding(_ value: Double) { draftSettings.horizontalPadding = value }
    private func setUsesJustifiedText(_ value: Bool) { draftSettings.usesJustifiedText = value }
    private func setBackgroundStyle(_ value: ReaderBackgroundStyle) { draftSettings.backgroundStyle = value }
    private func setReadingMode(_ value: ReaderReadingMode) { draftSettings.readingMode = value }
    private func setTranslationMode(_ value: ReaderTranslationMode) { draftSettings.translationMode = value }
    private func setImageLoading(_ value: Bool) { draftSettings.loadsInlineImages = value }
    private func setApplePencilPageTurnBehavior(_ value: ApplePencilPageTurnBehavior) {
        draftApplePencilPageTurnSettings.behavior = value
    }
}

private struct ReaderBooksUnifiedSheetBackground: View {
    let palette: ReaderBooksSheetPalette
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

private struct ReaderBooksHeroSection: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let previewText: String
    let topInset: CGFloat
    let height: CGFloat
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ReaderBooksSettingsHeader(
                palette: palette,
                onClose: onClose,
                onConfirm: onConfirm
            )
            .padding(.horizontal, 28)

            ReaderBooksPreviewMaskedContent(
                settings: settings,
                palette: palette,
                previewText: previewText,
                contentHeight: max(160, height - topInset - 122)
            )
        }
        .padding(.top, topInset + 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
    }
}

private struct ReaderBooksSettingsHeader: View {
    let palette: ReaderBooksSheetPalette
    let onClose: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Text(L10n.string("settings.title"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack {
                headerButton(
                    systemName: "xmark",
                    foreground: palette.primaryText,
                    background: palette.headerButtonBackground,
                    action: onClose
                )
                Spacer()
                headerButton(
                    systemName: "checkmark",
                    foreground: .white,
                    background: palette.confirmButtonBackground,
                    action: onConfirm
                )
            }
        }
        .padding(.horizontal, 6)
    }

    private func headerButton(systemName: String, foreground: Color, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 58, height: 58)
                .background(background, in: Circle())
                .shadow(color: Color.black.opacity(systemName == "checkmark" ? 0.16 : 0.08), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderBooksPreviewMaskedContent: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let previewText: String
    let contentHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            VStack(alignment: .leading, spacing: 20) {
                ReaderRichTextView(
                    text: previewText,
                    chapterTitle: nil,
                    settings: settings,
                    baseFontSize: 22,
                    textColor: UIColor(palette.primaryText)
                )
            }
            .padding(.top, 4)
            .padding(.horizontal, settings.horizontalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentHeight, alignment: .topLeading)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.78),
                    .init(color: .black.opacity(0.92), location: 0.86),
                    .init(color: .black.opacity(0.45), location: 0.94),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }
}

private struct ReaderBooksSheetPalette {
    let isNightMode: Bool
    let heroBackground: Color
    let bodyBackground: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let segmentedBackground: Color
    let divider: Color
    let headerButtonBackground: Color
    let confirmButtonBackground: Color

    init(settings: ReaderAppearanceSettings, colorScheme: ColorScheme) {
        let isNightMode = colorScheme == .dark
        let heroBackground = readerThemeColor(for: settings.backgroundStyle, colorScheme: colorScheme)
        let bodyBackground: Color
        let cardBackground: Color

        if isNightMode {
            bodyBackground = heroBackground.mix(with: Color(red: 0.08, green: 0.09, blue: 0.10), amount: 0.24)
            cardBackground = bodyBackground.mix(with: .white, amount: 0.08)
        } else {
            bodyBackground = heroBackground.mix(with: Color(red: 0.98, green: 0.98, blue: 0.99), amount: 0.72)
            cardBackground = bodyBackground.mix(with: .white, amount: 0.35)
        }

        self.isNightMode = isNightMode
        self.heroBackground = heroBackground
        self.bodyBackground = bodyBackground
        self.cardBackground = cardBackground
        primaryText = isNightMode
            ? Color.white.opacity(0.92)
            : Color(red: 0.09, green: 0.08, blue: 0.10)
        secondaryText = isNightMode
            ? Color.white.opacity(0.68)
            : Color.black.opacity(0.56)
        segmentedBackground = isNightMode
            ? bodyBackground.mix(with: .white, amount: 0.05)
            : bodyBackground.mix(with: Color.black, amount: 0.03)
        divider = isNightMode
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
        headerButtonBackground = isNightMode
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.78)
        confirmButtonBackground = isNightMode
            ? heroBackground.mix(with: Color(red: 0.44, green: 0.39, blue: 0.30), amount: 0.58)
            : heroBackground.mix(with: Color(red: 0.31, green: 0.26, blue: 0.18), amount: 0.72)
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

private struct ReaderBooksTextSection: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let onFontScaleChange: (Double) -> Void
    let onFontFamilyChange: (ReaderFontFamily) -> Void

    var body: some View {
        ReaderBooksSettingsSection(title: L10n.string("reader.section.text"), palette: palette) {
            ReaderBooksFontScaleRow(
                value: settings.fontScale,
                palette: palette,
                onChange: onFontScaleChange
            )
            ReaderBooksDivider(palette: palette)
            ReaderBooksFontPickerRow(
                selectedFamily: settings.fontFamily,
                palette: palette,
                onSelect: onFontFamilyChange
            )
        }
    }
}

private struct ReaderBooksLayoutSection: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let onLineHeightChange: (Double) -> Void
    let onCharacterSpacingChange: (Double) -> Void
    let onHorizontalPaddingChange: (Double) -> Void

    var body: some View {
        ReaderBooksSettingsSection(title: L10n.string("reader.section.layout"), palette: palette) {
            ReaderBooksSliderRow(
                title: L10n.string("reader.line_height"),
                valueLabel: String(format: "%.2f", settings.lineHeightScale),
                value: settings.lineHeightScale,
                range: 1.2 ... 2.2,
                step: 0.05,
                icon: .system("text.line.first.and.arrowtriangle.forward"),
                tint: Color(red: 0.08, green: 0.73, blue: 0.82),
                palette: palette,
                onChange: onLineHeightChange
            )
            ReaderBooksDivider(palette: palette)
            ReaderBooksSliderRow(
                title: L10n.string("reader.character_spacing"),
                valueLabel: "\(Int((settings.characterSpacingScale * 100).rounded()))%",
                value: settings.characterSpacingScale,
                range: 0 ... 0.12,
                step: 0.01,
                icon: .characterSpacing,
                tint: Color(red: 0.13, green: 0.13, blue: 0.16),
                palette: palette,
                onChange: onCharacterSpacingChange
            )
            ReaderBooksDivider(palette: palette)
            ReaderBooksSliderRow(
                title: L10n.string("reader.horizontal_padding"),
                valueLabel: "\(Int(settings.horizontalPadding.rounded()))",
                value: settings.horizontalPadding,
                range: 8 ... 36,
                step: 2,
                icon: .system("rectangle.inset.filled"),
                tint: Color(red: 0.43, green: 0.32, blue: 0.96),
                palette: palette,
                onChange: onHorizontalPaddingChange
            )
        }
    }
}

private struct ReaderBooksStandaloneToggleSection: View {
    let title: String
    let palette: ReaderBooksSheetPalette
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1)
        }
    }
}

private struct ReaderBooksDisplaySection: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let colorScheme: ColorScheme
    let showsTwoPageToggle: Bool
    @Binding var showsTwoPagesInLandscapeOnPad: Bool
    let onBackgroundStyleChange: (ReaderBackgroundStyle) -> Void
    let onReadingModeChange: (ReaderReadingMode) -> Void
    let onSelectOriginalText: () -> Void
    let onSelectSimplifiedText: () -> Void
    let onSelectTraditionalText: () -> Void

    var body: some View {
        ReaderBooksSettingsSection(title: L10n.string("reader.section.display"), palette: palette) {
            ReaderBooksThemePicker(
                selectedStyle: settings.backgroundStyle,
                colorScheme: colorScheme,
                palette: palette,
                onSelect: onBackgroundStyleChange
            )
            ReaderBooksDivider(palette: palette)
            ReaderBooksReadingModePicker(
                selection: settings.readingMode,
                palette: palette,
                onSelect: onReadingModeChange
            )
            if showsTwoPageToggle {
                ReaderBooksDivider(palette: palette)
                ReaderBooksToggleRow(
                    title: L10n.string("reader.two_pages_landscape"),
                    palette: palette,
                    isOn: $showsTwoPagesInLandscapeOnPad
                )
            }
            ReaderBooksDivider(palette: palette)
            ReaderBooksTranslationPicker(
                selectedModeRawValue: settings.translationMode.rawValue,
                palette: palette,
                onSelectOriginal: onSelectOriginalText,
                onSelectSimplified: onSelectSimplifiedText,
                onSelectTraditional: onSelectTraditionalText
            )
        }
    }
}

private struct ReaderBooksMiscSection: View {
    let palette: ReaderBooksSheetPalette
    let loadsInlineImages: Bool
    let onLoadsInlineImagesChange: (Bool) -> Void

    var body: some View {
        ReaderBooksSettingsSection(title: L10n.string("reader.section.other"), palette: palette) {
            ReaderBooksToggleRow(
                title: L10n.string("reader.inline_images"),
                palette: palette,
                isOn: Binding(
                    get: { loadsInlineImages },
                    set: { onLoadsInlineImagesChange($0) }
                )
            )
        }
    }
}

private struct ReaderBooksApplePencilSection: View {
    private static let helpText = L10n.string("apple_pencil.help")

    let settings: ApplePencilPageTurnSettings
    let palette: ReaderBooksSheetPalette
    @Binding var isEnabled: Bool
    let onBehaviorChange: (ApplePencilPageTurnBehavior) -> Void
    @State private var showsHelp = false

    var body: some View {
        ReaderBooksSettingsSection(title: "Apple Pencil", palette: palette) {
            HStack(spacing: 10) {
                Text(L10n.string("apple_pencil.page_turn"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsHelp.toggle()
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.blue)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }

            if showsHelp {
                Text(Self.helpText)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.segmentedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ReaderBooksDivider(palette: palette)

            HStack(spacing: 12) {
                Text(L10n.string("apple_pencil.behavior.title"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                Menu {
                    ForEach(ApplePencilPageTurnBehavior.allCases, id: \.self) { behavior in
                        Button {
                            onBehaviorChange(behavior)
                        } label: {
                            if settings.behavior == behavior {
                                Label(behavior.title, systemImage: "checkmark")
                            } else {
                                Text(behavior.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(settings.behavior.title)
                            .font(.title3)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.78)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.secondaryText.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReaderBooksSettingsSection<Content: View>: View {
    let title: String
    let palette: ReaderBooksSheetPalette
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
                    .strokeBorder(palette.divider, lineWidth: 1)
            }
        }
    }
}

private struct ReaderBooksFontScaleRow: View {
    let value: Double
    let palette: ReaderBooksSheetPalette
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("reader.font_size"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }

            HStack(spacing: 14) {
                circleButton(systemName: "minus") {
                    onChange(max(0.8, value - 0.1))
                }

                Slider(
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            let stepped = (newValue / 0.1).rounded() * 0.1
                            onChange(min(1.8, max(0.8, stepped)))
                        }
                    ),
                    in: 0.8 ... 1.8
                )
                .tint(Color(red: 0.71, green: 0.51, blue: 0.35))

                circleButton(systemName: "plus") {
                    onChange(min(1.8, value + 0.1))
                }
            }
        }
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 44, height: 44)
                .background(palette.segmentedBackground, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderBooksFontPickerRow: View {
    let selectedFamily: ReaderFontFamily
    let palette: ReaderBooksSheetPalette
    let onSelect: (ReaderFontFamily) -> Void

    var body: some View {
        HStack {
            Text(L10n.string("reader.font_family"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Spacer()
            Menu {
                ForEach(ReaderFontFamily.allCases, id: \.self) { family in
                    Button(family.title) {
                        onSelect(family)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedFamily.title)
                        .foregroundStyle(palette.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryText.opacity(0.75))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ReaderBooksToggleRow: View {
    let title: String
    let palette: ReaderBooksSheetPalette
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct ReaderBooksSliderRow: View {
    let title: String
    let valueLabel: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let icon: ReaderBooksSliderIcon
    let tint: Color
    let palette: ReaderBooksSheetPalette
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack(spacing: 16) {
                ReaderBooksSliderLeadingIcon(
                    icon: icon,
                    palette: palette
                )
                    .frame(width: 26)

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

                Text(valueLabel)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
    }
}

private enum ReaderBooksSliderIcon {
    case system(String)
    case characterSpacing
}

private struct ReaderBooksSliderLeadingIcon: View {
    let icon: ReaderBooksSliderIcon
    let palette: ReaderBooksSheetPalette

    var body: some View {
        switch icon {
        case let .system(name):
            Image(systemName: name)
                .font(.title3)
                .foregroundStyle(palette.primaryText)
        case .characterSpacing:
            VStack(spacing: -1) {
                Text(L10n.string("reader.character_spacing_sample"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
            }
            .frame(width: 26, height: 24)
        }
    }
}

private struct ReaderBooksReadingModePicker: View {
    let selection: ReaderReadingMode
    let palette: ReaderBooksSheetPalette
    let onSelect: (ReaderReadingMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("reading_mode.title"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack(spacing: 8) {
                modeButton(.paged)
                modeButton(.vertical)
            }
            .padding(6)
            .background(palette.segmentedBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func modeButton(_ mode: ReaderReadingMode) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Text(mode.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selection == mode ? palette.cardBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .foregroundStyle(palette.primaryText)
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderBooksTranslationPicker: View {
    let selectedModeRawValue: String
    let palette: ReaderBooksSheetPalette
    let onSelectOriginal: () -> Void
    let onSelectSimplified: () -> Void
    let onSelectTraditional: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("translation.title"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack(spacing: 8) {
                translationButton(L10n.string("translation.original"), modeRawValue: ReaderTranslationMode.none.rawValue, action: onSelectOriginal)
                translationButton(L10n.string("translation.simplified"), modeRawValue: ReaderTranslationMode.simplified.rawValue, action: onSelectSimplified)
                translationButton(L10n.string("translation.traditional"), modeRawValue: ReaderTranslationMode.traditional.rawValue, action: onSelectTraditional)
            }
            .padding(6)
            .background(palette.segmentedBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func translationButton(_ title: String, modeRawValue: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selectedModeRawValue == modeRawValue ? palette.cardBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .foregroundStyle(palette.primaryText)
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderBooksThemePicker: View {
    let selectedStyle: ReaderBackgroundStyle
    let colorScheme: ColorScheme
    let palette: ReaderBooksSheetPalette
    let onSelect: (ReaderBackgroundStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("reader.background_theme"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            HStack(spacing: 12) {
                ForEach(ReaderBackgroundStyle.allCases, id: \.self) { style in
                    Button {
                        onSelect(style)
                    } label: {
                        VStack(spacing: 10) {
                            Circle()
                                .fill(readerThemeColor(for: style, colorScheme: colorScheme))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Circle()
                                        .strokeBorder(selectedStyle == style ? palette.primaryText : Color.clear, lineWidth: 2)
                                }
                            Text(style.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(palette.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedStyle == style ? palette.primaryText.opacity(0.06) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ReaderBooksDivider: View {
    let palette: ReaderBooksSheetPalette

    var body: some View {
        Divider().overlay(palette.divider)
    }
}

func readerThemeColor(for style: ReaderBackgroundStyle, colorScheme: ColorScheme) -> Color {
    let isNightMode = colorScheme == .dark
    if isNightMode {
        switch style {
        case .system:
            return Color(red: 0.15, green: 0.16, blue: 0.18)
        case .paper:
            return Color(red: 0.21, green: 0.19, blue: 0.16)
        case .mint:
            return Color(red: 0.14, green: 0.18, blue: 0.16)
        case .sakura:
            return Color(red: 0.19, green: 0.16, blue: 0.18)
        }
    }

    switch style {
    case .system:
        return Color(red: 0.95, green: 0.94, blue: 0.91)
    case .paper:
        return Color(red: 0.96, green: 0.92, blue: 0.84)
    case .mint:
        return Color(red: 0.92, green: 0.97, blue: 0.93)
    case .sakura:
        return Color(red: 0.97, green: 0.92, blue: 0.93)
    }
}

#endif
