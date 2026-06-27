import SwiftUI
import YamiboReaderCore

#if os(iOS)

struct ReaderBooksTextSection: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let onFontScaleChange: (Double) -> Void
    let onFontFamilyChange: (ReaderFontFamily) -> Void
    let onSelectOriginalText: () -> Void
    let onSelectSimplifiedText: () -> Void
    let onSelectTraditionalText: () -> Void

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

struct ReaderBooksLayoutSection: View {
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

struct ReaderBooksTextOptionsSection: View {
    let palette: ReaderBooksSheetPalette
    @Binding var usesJustifiedText: Bool
    @Binding var indentsParagraphFirstLine: Bool

    var body: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: L10n.string("reader.justified_text"),
                isOn: $usesJustifiedText
            )
            ReaderBooksDivider(palette: palette)
            toggleRow(
                title: L10n.string("reader.paragraph_first_line_indent"),
                isOn: $indentsParagraphFirstLine
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1)
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .foregroundStyle(palette.primaryText)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

struct ReaderBooksDisplaySection: View {
    let settings: ReaderAppearanceSettings
    let palette: ReaderBooksSheetPalette
    let colorScheme: ColorScheme
    let showsTwoPageToggle: Bool
    @Binding var showsTwoPagesInLandscapeOnPad: Bool
    let onBackgroundStyleChange: (ReaderBackgroundStyle) -> Void
    let onReadingModeChange: (ReaderReadingMode, ReaderPagedTurnStyle) -> Void

    var body: some View {
        ReaderBooksSettingsSection(title: L10n.string("reader.section.display"), palette: palette) {
            ReaderBooksThemePicker(
                selectedStyle: settings.backgroundStyle,
                colorScheme: colorScheme,
                palette: palette,
                onSelect: onBackgroundStyleChange
            )
            ReaderBooksDivider(palette: palette)
            ReaderBooksReadingModeMenuRow(
                settings: settings,
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
        }
    }
}

struct ReaderBooksMiscSection: View {
    let palette: ReaderBooksSheetPalette
    let loadsInlineImages: Bool
    let showsAuthorRepliesToOthers: Bool
    let onLoadsInlineImagesChange: (Bool) -> Void
    let onShowsAuthorRepliesToOthersChange: (Bool) -> Void

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
            ReaderBooksDivider(palette: palette)
            ReaderBooksToggleRow(
                title: L10n.string("reader.author_replies_to_others"),
                palette: palette,
                isOn: Binding(
                    get: { showsAuthorRepliesToOthers },
                    set: { onShowsAuthorRepliesToOthersChange($0) }
                )
            )
        }
    }
}

#endif
