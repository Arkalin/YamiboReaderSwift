# YamiboX Context Map

YamiboX uses multiple domain context documents. Start here, then read the context files relevant to the code or issue you are working on.

## Contexts

| Context | Path | Read when working on |
| --- | --- | --- |
| Manga Reader | `docs/contexts/manga-reader/CONTEXT.md` | Continuous manga chapter loading, manga directories, manga page position, or manga reader ambiguity. |
| Novel Reader | `docs/contexts/novel-reader/CONTEXT.md` | Native novel reading, TextKit 2 layout, runtime generations, reader presentation, positions, surfaces, and SwiftUI adapters. |
| Reader Navigation | `docs/contexts/reader-navigation/CONTEXT.md` | Cross-reader navigation behavior shared by manga and novel readers, including non-linear jumps and return anchors. |
| Reader Comments | `docs/contexts/reader-comments/CONTEXT.md` | Cross-reader chapter comment targets, loading state, and comment presentation shared by manga and novel readers. |
| Library and Account | `docs/contexts/library-account/CONTEXT.md` | Favorites, local reading metadata, WebDAV sync, Yamibo accounts, profile display, forum credit progress, security questions, or sign out. |
| Forum | `docs/contexts/forum/CONTEXT.md` | Native forum browsing, forum board and thread-list presentation, forum web fallback, and routing from forum content into native readers. |

## Implementation Landmarks

- `Sources/YamiboXCore` is organized by feature (`Account`, `Forum`, `Library`, `Reader/{Manga,Novel,Shared}`, `Settings`, `Sync`, `Update`) with `Domain`/`Application`/`Data` layers inside each feature. Cross-cutting infrastructure lives under `Sources/YamiboXCore/Infrastructure/{Networking,HTML,Images,Routing,Localization}`; the shared GRDB database lifecycle lives under `Sources/YamiboXCore/Persistence/`, with each feature contributing its own schema module. Core is UIKit-free.
- `YamiboAppContext` (`Sources/YamiboXCore/App/`) is the composition root. It assembles per-feature `*Dependencies` packages (`ForumDependencies`, `LibraryDependencies`, `AccountDependencies`, `MangaReaderDependencies`, `NovelReaderDependencies`, `SettingsDependencies`, `WebDAVSyncDependencies`); feature views and view models receive their dependencies package explicitly and never touch the context. Only the app-entry layer (`Sources/YamiboXUI/AppEntry/`) uses the context.
- `Sources/YamiboXUI` mirrors the feature layout under `Features/`; cross-feature UI helpers live under `Sources/YamiboXUI/Platform/`.
- Manga native reader UI lives under `Sources/YamiboXUI/Features/Reader/Manga/`. Read `Root/MangaReaderView.swift` first for chrome and content routing, `Viewports/Paged/` (entry point `MangaPagedReaderViewport.swift`) for paged viewport behavior, and `Support/MangaPagedReadingPlan.swift` for page/spread ordering rules.
- Manga paged reading keeps resume, comments, and progress at page-level **Manga Reading Position** even when the viewport displays one-page, two-page, or page-curl **Manga Page Spreads**.
- Novel native reader UI lives under `Sources/YamiboXUI/Features/Reader/Novel/`. The production TextKit 2 adapters live in its `TextKit/` subdirectory; Core novel layout and the runtime seam stay platform-neutral under `Sources/YamiboXCore/Reader/Novel/`.
- Shared reader paging primitives live under `Sources/YamiboXUI/Features/Reader/Shared/Paging/`. Use this location for cross-reader page-turn visuals, boundary page-turn gestures, leaf bookkeeping, and progress fill direction primitives before adding reader-specific copies.
- Shared reader chrome lives under `Sources/YamiboXUI/Features/Reader/Shared/Chrome/`. Directional progress fill behavior for paged readers belongs there when it is not manga-only.

## ADRs

- Read `docs/adr/` for repo-wide architecture decisions when it exists.
- If a context later gains local ADRs, place them under `docs/contexts/<context>/docs/adr/` and read them with that context.

## Producer Rule

When adding new domain language, update the smallest relevant context file. If a term crosses contexts, define it once in the owning context and reference it by name elsewhere.
