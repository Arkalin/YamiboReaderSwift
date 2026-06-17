# ADR 0001: Manga Reader Boundary Map

Date: 2026-06-17

## Status

Accepted for phase 1.

## Context

The current manga reader is a productionized Yamibo-specific feature rather than a simple layered sample. The existing implementation already contains useful boundaries, but `MangaReaderModel` still coordinates UI state, the **Manga Chapter Window**, **Manga Directory** updates, progress persistence, image prefetching, settings persistence, chapter comments, and native/WebKit fallback behavior.

The refactor will be a parallel rewrite rather than an in-place mutation of `Sources/YamiboReaderUI/Features/MangaReader`. Phase 1 defines the target boundaries and creates visible placeholder directories only. It must not change production behavior.

Domain language follows `docs/contexts/manga-reader/CONTEXT.md`:

- **Manga Directory**
- **Manga Chapter Document**
- **Manga Chapter Window**
- **Manga Reading Position**

## Decision

Create visible target boundary roots without moving existing production files:

```text
Sources/YamiboReaderCore/MangaReader/
  Domain/
  Application/
  Data/

Sources/YamiboReaderUI/Features/MangaReaderNew/
  Presentation/
  Chrome/
  Directory/
  Settings/
  WebFallback/
```

`MangaReaderNew` is a temporary parallel rewrite workspace. It is not a production feature route during phase 1.

## Target Boundaries

### Core Domain

Core Domain owns pure manga reader values and rules.

Target examples:

- **Manga Directory** value semantics.
- **Manga Chapter Document** as parsed image-page content.
- **Manga Chapter Window** ordering, adjacency, trimming, and **Manga Reading Position** resolution.
- Pure merge/sort rules once isolated by tests.

`MangaChapterWindow` is the clearest current Domain candidate. `MangaReadingSession` is not pure Domain because it performs async loading, timeout recovery, directory resolving, and native/Web fallback decisions.

### Core Application

Core Application coordinates reader workflows without depending on SwiftUI or WebKit.

Target examples:

- `MangaDirectoryWorkflow` for **Manga Directory** initialization, update, forced search, rename/merge, cooldown, and persistence coordination.
- A future reader workflow that coordinates **Manga Chapter Window**, loading, jump behavior, progress, settings commits, and image prefetch policy.
- Probe recovery policy that depends on a WebKit adapter seam rather than WebKit itself.

`MangaReadingSession` is a legacy Application candidate. Keep it in place during phase 1 and decide its final shape during later extraction.

### Core Data

Core Data owns Yamibo fetches and persistence implementation details.

Target examples:

- `MangaRepository` for Yamibo HTML and directory/search fetches.
- `MangaHTMLParser` for Yamibo HTML extraction.
- `MangaDirectoryStore` as a future persistence-only store.
- `MangaImageRepository` and `MangaImageCacheStore` for image byte fetch/cache.

`MangaDirectoryStore` is legacy mixed Data/Application code because it currently performs persistence, initialization, update strategy, search cooldown, and rename/merge.

### UI Presentation

UI Presentation owns SwiftUI-facing state and controls.

Target examples:

- `MangaReaderView`
- `MangaReaderModel` as a SwiftUI adapter over Application workflows.
- `MangaReaderPresentation` as the primary immutable published snapshot.
- Page projection values for rendering and interaction.

The future model should publish one core `MangaReaderPresentation` snapshot plus minimal UI-only transient state, rather than many independently synchronized content fields.

### UI WebFallback

UI WebFallback owns WebKit-specific adapters and visible fallback views.

Target examples:

- `MangaWebFallbackView`
- `MangaProbeService`
- WebKit JavaScript extraction and hidden probe web view handling.
- A future `WebKitMangaProbeAdapter`.

Core may own probe decisions and policy, but it must not depend on `WKWebView`.

## Specific Boundary Decisions

- `MangaChapterDocument.html` is a legacy implementation convenience. The target shape is a `MangaChapterLoadResult(document, sourceHTML)` or equivalent Application/Data result so Domain **Manga Chapter Document** remains parsed image-page content.
- `MangaReaderSettings` remains a legacy aggregate during phase 1. Future work should distinguish committed reader behavior settings, presentation appearance settings, sheet draft state, and persisted settings-store representation.
- `MangaPage` may remain an Application/Core value, but UI should eventually receive a slimmer `MangaReaderPageProjection` containing image URL, referer URL, chapter identity, owner post ID, title, local page number, and chapter page count.
- Image byte fetch/cache belongs in Core Data. Image prefetch strategy belongs in Core Application. Platform image decoding and display belong in UI Presentation.
- `MangaProbeDecision` can remain pure Core logic. WebKit probing remains a UI adapter behind the existing closure seam until a real extraction needs a stronger interface.

## Phase 1 Scope

Phase 1 may add:

- this ADR
- boundary README files
- placeholder directories

Phase 1 must not add:

- production routing changes
- moves of existing manga reader files
- new Swift workflow/domain/data protocols
- placeholder Swift types with public API
- changes to `MangaReaderModel`, `MangaReadingSession`, `MangaDirectoryStore`, or WebKit fallback behavior

## Cutover Policy

`Sources/YamiboReaderUI/Features/MangaReader` remains the only production native manga reader route until parity is proven.

`Sources/YamiboReaderUI/Features/MangaReaderNew` must not be wired into `RootTabView` during phase 1.

After the new reader passes parity tests, perform one explicit cutover change:

1. Rename old `MangaReader` to `MangaReaderLegacy` or delete it if rollback is not needed.
2. Rename `MangaReaderNew` to `MangaReader`.
3. Update `RootTabView` once.
4. Remove duplicate route and test references.

## Phase 2 Entry Tests

Before phase 2 extracts real workflows or wires the new reader, behavior coverage must exist and pass for:

- **Manga Directory** initialization from tag, same-page links, and pending search cases.
- **Manga Directory** update through tag success, tag empty to search fallback, forced search, and search cooldown.
- **Manga Chapter Window** adjacent insertion, non-adjacent reset, trimming, and **Manga Reading Position** resolution.
- Native/Web manga routing, including fallback web, return to native, suspended web context, and `waitingForNativeReturn`.
- Existing `MangaReaderModel` parity behavior until cutover.

## Consequences

The refactor gets a visible destination without destabilizing the production manga reader. Later phases can move behavior one workflow at a time, with `MangaDirectoryWorkflow` as the preferred first extraction because it has the clearest mixed Data/Application responsibilities and can help remove raw HTML from Domain values.
