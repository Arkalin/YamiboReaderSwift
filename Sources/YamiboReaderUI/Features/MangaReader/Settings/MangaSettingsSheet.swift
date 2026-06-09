import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaSettingsSheet: View {
    @ObservedObject var model: MangaReaderModel
    let showsPadPagedOptions: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showsApplePencilHelp = false
    private static let applePencilHelpText = L10n.string("apple_pencil.help")

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

                if showsPadPagedOptions, model.settings.readingMode == .paged {
                    Section("Apple Pencil") {
                        HStack(spacing: 8) {
                            Text(L10n.string("apple_pencil.page_turn"))
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showsApplePencilHelp.toggle()
                                }
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.headline.weight(.semibold))
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 8)

                            Toggle("", isOn: Binding(
                                get: { model.applePencilPageTurnSettings.isEnabled },
                                set: {
                                    var updated = model.applePencilPageTurnSettings
                                    updated.isEnabled = $0
                                    model.applyApplePencilPageTurnSettings(updated)
                                }
                            ))
                            .labelsHidden()
                        }

                        if showsApplePencilHelp {
                            Text(Self.applePencilHelpText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 6)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Picker(L10n.string("apple_pencil.behavior.title"), selection: Binding(
                            get: { model.applePencilPageTurnSettings.behavior },
                            set: {
                                var updated = model.applePencilPageTurnSettings
                                updated.behavior = $0
                                model.applyApplePencilPageTurnSettings(updated)
                            }
                        )) {
                            ForEach(ApplePencilPageTurnBehavior.allCases, id: \.self) { behavior in
                                Text(behavior.title).tag(behavior)
                            }
                        }
                    }
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
