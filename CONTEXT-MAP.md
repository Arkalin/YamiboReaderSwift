# YamiboReader Context Map

YamiboReader uses multiple domain context documents. Start here, then read the context files relevant to the code or issue you are working on.

## Contexts

| Context | Path | Read when working on |
| --- | --- | --- |
| Manga Reader | `docs/contexts/manga-reader/CONTEXT.md` | Continuous manga chapter loading, manga directories, manga page position, or manga reader ambiguity. |
| Novel Reader | `docs/contexts/novel-reader/CONTEXT.md` | Native novel reading, TextKit 2 layout, runtime generations, reader presentation, positions, surfaces, and SwiftUI adapters. |
| Reader Navigation | `docs/contexts/reader-navigation/CONTEXT.md` | Cross-reader navigation behavior shared by manga and novel readers, including non-linear jumps and return anchors. |
| Library and Account | `docs/contexts/library-account/CONTEXT.md` | Favorites, local reading metadata, WebDAV sync, Yamibo accounts, profile display, forum credit progress, security questions, or sign out. |

## Implementation Landmarks

- Manga native reader presentation lives under `Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/`. Read `MangaReaderView.swift` first for chrome and content routing, `MangaPagedReaderViewport.swift` for paged viewport behavior, and `MangaPagedReadingPlan.swift` for page/spread ordering rules.
- Manga paged reading keeps resume, comments, and progress at page-level **Manga Reading Position** even when the viewport displays one-page, two-page, or page-curl **Manga Page Spreads**.
- Shared reader paging primitives live under `Sources/YamiboReaderUI/Features/Reader/Shared/Paging/`. Use this location for cross-reader page-turn visuals, boundary page-turn gestures, leaf bookkeeping, and progress fill direction primitives before adding reader-specific copies.
- Shared reader chrome lives under `Sources/YamiboReaderUI/Features/Reader/Shared/Chrome/`. Directional progress fill behavior for paged readers belongs there when it is not manga-only.

## ADRs

- Read `docs/adr/` for repo-wide architecture decisions when it exists.
- If a context later gains local ADRs, place them under `docs/contexts/<context>/docs/adr/` and read them with that context.

## Producer Rule

When adding new domain language, update the smallest relevant context file. If a term crosses contexts, define it once in the owning context and reference it by name elsewhere.
