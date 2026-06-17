import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaSettingsSheet: View {
    @ObservedObject var model: MangaReaderModel
    let showsPadPagedOptions: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.string("reading_mode.title"), selection: Binding(
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

                if showsPadPagedOptions, model.settings.readingMode == .paged {
                    Toggle(L10n.string("reader.two_pages_landscape"), isOn: Binding(
                        get: { model.settings.showsTwoPagesInLandscapeOnPad },
                        set: {
                            var updated = model.settings
                            updated.showsTwoPagesInLandscapeOnPad = $0
                            model.applySettings(updated)
                        }
                    ))
                }

                Toggle(L10n.string("manga.zoom_enabled"), isOn: Binding(
                    get: { model.settings.zoomEnabled },
                    set: {
                        var updated = model.settings
                        updated.zoomEnabled = $0
                        model.applySettings(updated)
                    }
                ))

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("manga.brightness"))
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
            .navigationTitle(L10n.string("manga.settings"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done")) { dismiss() }
                }
            }
        }
    }
}
#endif
