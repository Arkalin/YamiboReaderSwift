import SwiftUI
import YamiboReaderCore

#if os(iOS)

struct ReaderBooksTextSection: View {
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

struct ReaderBooksMiscSection: View {
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

struct ReaderBooksApplePencilSection: View {
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
                    .font(.title3)
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
                    .font(.title3)
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

#endif
