import SwiftUI
import YamiboReaderCore

#if os(iOS)

struct ReaderBooksSettingsSection<Content: View>: View {
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

struct ReaderBooksFontScaleRow: View {
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

struct ReaderBooksFontPickerRow: View {
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

struct ReaderBooksToggleRow: View {
    let title: String
    let palette: ReaderBooksSheetPalette
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.title3)
                .foregroundStyle(palette.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct ReaderBooksSliderRow: View {
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

enum ReaderBooksSliderIcon {
    case system(String)
    case characterSpacing
}

struct ReaderBooksSliderLeadingIcon: View {
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

struct ReaderBooksReadingModePicker: View {
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

struct ReaderBooksTranslationPicker: View {
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

struct ReaderBooksThemePicker: View {
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

struct ReaderBooksDivider: View {
    let palette: ReaderBooksSheetPalette

    var body: some View {
        Divider().overlay(palette.divider)
    }
}

#endif
