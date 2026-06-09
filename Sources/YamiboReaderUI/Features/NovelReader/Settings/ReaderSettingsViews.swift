import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

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
                    heroSection(
                        topInset: topInset,
                        heroHeight: heroHeight,
                        palette: palette
                    )

                    settingsSections(palette: palette)
                }
            }
            .background(Color.clear)
        }
        .background(Color.clear)
        .onAppear(perform: loadDraftIfNeeded)
    }

    private func heroSection(
        topInset: CGFloat,
        heroHeight: CGFloat,
        palette: ReaderBooksSheetPalette
    ) -> some View {
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
            onConfirm: commitDraft
        )
    }

    private func settingsSections(palette: ReaderBooksSheetPalette) -> some View {
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

                ReaderBooksTextOptionsSection(
                    palette: palette,
                    usesJustifiedText: Binding(
                        get: { draftSettings.usesJustifiedText },
                        set: { draftSettings.usesJustifiedText = $0 }
                    ),
                    indentsParagraphFirstLine: Binding(
                        get: { draftSettings.indentsParagraphFirstLine },
                        set: { draftSettings.indentsParagraphFirstLine = $0 }
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

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        draftSettings = model.settings
        draftApplePencilPageTurnSettings = model.applePencilPageTurnSettings
        hasLoadedDraft = true
    }

    private func commitDraft() {
        let committedSettings = draftSettings
        let committedApplePencilPageTurnSettings = draftApplePencilPageTurnSettings
        dismiss()
        Task {
            await model.commitNovelTextAppearance(
                committedSettings,
                applePencilPageTurnSettings: committedApplePencilPageTurnSettings
            )
        }
    }

    private func setFontScale(_ value: Double) { draftSettings.fontScale = value }
    private func setFontFamily(_ value: ReaderFontFamily) { draftSettings.fontFamily = value }
    private func setLineHeightScale(_ value: Double) { draftSettings.lineHeightScale = value }
    private func setCharacterSpacingScale(_ value: Double) { draftSettings.characterSpacingScale = value }
    private func setHorizontalPadding(_ value: Double) { draftSettings.horizontalPadding = value }
    private func setBackgroundStyle(_ value: ReaderBackgroundStyle) { draftSettings.backgroundStyle = value }
    private func setReadingMode(_ value: ReaderReadingMode, pagedTurnStyle: ReaderPagedTurnStyle) {
        draftSettings.readingMode = value
        if value == .paged {
            draftSettings.pagedTurnStyle = pagedTurnStyle
        }
    }
    private func setTranslationMode(_ value: ReaderTranslationMode) { draftSettings.translationMode = value }
    private func setImageLoading(_ value: Bool) { draftSettings.loadsInlineImages = value }
    private func setApplePencilPageTurnBehavior(_ value: ApplePencilPageTurnBehavior) {
        draftApplePencilPageTurnSettings.behavior = value
    }
}

#endif
