# ADR 0001: Manga Reader Boundary Map

Date: 2026-06-17

## Status

Accepted for phase 1. Revised for phase 2 on 2026-06-17.

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
Sources/YamiboReaderCore/Reader/MangaReader/
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

## Phase 2 Revision

Phase 2 changes the refactor policy from behavior-preserving seam extraction around the legacy reader to a full rewrite path:

- The legacy manga reader implementation is reference material only during the rewrite.
- The legacy manga reader does not need to remain runnable or compile-ready once phase 2 begins.
- New manga reader code should live under the phase 1 boundary roots rather than adapting legacy implementation classes or actors.
- New Domain values should follow the glossary directly, even when that breaks compatibility with legacy conveniences such as storing raw HTML on **Manga Chapter Document**.
- Protocol seams introduced in phase 2 should serve the new implementation, not retrofit `MangaRepository`, `MangaDirectoryStore`, `MangaReadingSession`, or `MangaReaderModel`.
- Legacy manga reader implementation files should move out of `Sources/` into `docs/reference/manga-reader-legacy/` so they remain available as reference material without participating in package compilation.
- After the legacy UI reader moves out of `Sources/YamiboReaderUI/Features/MangaReader`, `Sources/YamiboReaderUI/Features/MangaReaderNew` should be renamed to `Sources/YamiboReaderUI/Features/MangaReader`; the rewrite owns the production-facing path name from that point forward.
- App-level manga route/context contracts remain source code, because Favorites, resume route, and app presentation use them outside the legacy reader implementation.
- Phase 2 should deliver a compiling vertical skeleton for the new reader, not complete continuous reading parity.
- Legacy manga reader tests should move to `docs/reference/manga-reader-legacy/Tests/`; new tests should cover the phase 2 skeleton and retained app-level route/context contracts.
- Phase 2 retains Web route types such as `MangaWebContext`, but does not implement WebKit fallback, hidden probing, JavaScript extraction, or automatic return-to-native behavior.
- `MangaReaderSettings` remains a persisted settings contract during phase 2, but it is not the internal state model for the new reader UI.
- Manga progress and resume contracts remain source code, but the phase 2 reader skeleton should not write progress until real **Manga Reading Position** updates exist.
- Phase 2 Data seams should expose repository operations, not raw HTML or full reader workflows. HTML parsing details stay hidden behind repositories.
- `MangaChapterDocumentLoading` should return **Manga Chapter Document** directly without source HTML.
- Tag IDs, same-page chapter links, title, and first post identity needed to initialize a **Manga Directory** should come from a new `MangaDirectoryRepository` boundary.
- `MangaDirectoryRepository` should return a directory seed and remote chapter arrays; Application code owns final **Manga Directory** construction, merge strategy, cooldown, rename, and persistence coordination.
- `ownerPostID` remains parsed metadata on **Manga Chapter Document**. Directory seed may also include first post identity as initialization metadata.
- The legacy `MangaPage` shape should not become new Domain. New reader output should use an Application-level `MangaReaderPageProjection`.
- Phase 2 should rewrite only a minimal **Manga Chapter Window** skeleton that can hold documents, expose page projections, and resolve/clamp a **Manga Reading Position**. Adjacent insertion, trimming, directory refresh, and continuous-reading behavior belong to later phases.
- The phase 2 SwiftUI reader should be a routeable presentation skeleton only. It should not perform real network loading, progress writes, WebKit fallback, image caching, or continuous-reading recovery.
- Existing manga entry points should route to the phase 2 skeleton rather than disabling manga opening. The skeleton keeps the public `MangaReaderView(context:appModel:)` entry shape so app routing can stay narrow.
- During phase 2, `YamiboAppModel.openManga` should route directly to the native skeleton and should not invoke legacy probing or automatically fall back to Web.
- Legacy probe support types and behavior, including `MangaProbePayload`, `MangaProbeOutcome`, and `MangaProbeDecision`, should move to reference with the old probe implementation. Phase 2 keeps Web route context only as an app-level route contract.
- `ThreadOpenResolver` and `ThreadOpenTarget.manga(MangaLaunchContext)` remain source code because they classify forum threads and create app-level manga opening routes rather than implementing the legacy manga reader.

This revision supersedes the earlier assumption that phase 2 must preserve production manga reader behavior while extracting protocol seams.

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

- **Manga Chapter Document** must not carry raw HTML. Chapter HTML parsing belongs behind repository boundaries.
- A new `MangaDirectoryRepository` provides tag IDs, same-page chapter links, title, and first post identity needed to initialize a **Manga Directory**.
- `MangaReaderSettings` remains a persisted settings contract during phase 2. Future work should distinguish committed reader behavior settings, presentation appearance settings, sheet draft state, and persisted settings-store representation.
- The legacy `MangaPage` shape should not be carried forward. UI should receive `MangaReaderPageProjection` containing image URL, referer URL, chapter identity, owner post ID, title, local page number, and chapter page count.
- Image byte fetch/cache belongs in Core Data. Image prefetch strategy belongs in Core Application. Platform image decoding and display belong in UI Presentation.
- Legacy probe decisions and WebKit probing move to reference during phase 2. Future fallback/probe behavior should be redesigned behind new repository or adapter seams.

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

Phase 1 kept `Sources/YamiboReaderUI/Features/MangaReader` as the only production native manga reader route. Phase 2 no longer requires the legacy manga reader to remain production-ready while the rewrite proceeds.

`Sources/YamiboReaderUI/Features/MangaReaderNew` must not be wired into `RootTabView` during phase 1.

At the start of phase 2:

1. Move legacy manga reader source and tests to `docs/reference/manga-reader-legacy/`.
2. Rename `Sources/YamiboReaderUI/Features/MangaReaderNew` to `Sources/YamiboReaderUI/Features/MangaReader`.
3. Keep app-level route/context contracts in source.
4. Route existing manga entry points to the new skeleton.

## Phase 2 Entry Tests

Phase 1 identified the following useful characterization coverage. Under the phase 2 rewrite policy, these tests are reference expectations rather than a requirement that legacy reader behavior stay production-runnable:

- **Manga Directory** initialization from tag, same-page links, and pending search cases.
- **Manga Directory** update through tag success, tag empty to search fallback, forced search, and search cooldown.
- **Manga Chapter Window** adjacent insertion, non-adjacent reset, trimming, and **Manga Reading Position** resolution.
- Native/Web manga routing, including fallback web, return to native, suspended web context, and `waitingForNativeReturn`.
- Existing `MangaReaderModel` parity behavior until cutover.

## Consequences

The refactor gets a visible destination. Phase 2 accepts temporary disruption to the legacy manga reader so the new implementation can model **Manga Chapter Document**, **Manga Directory**, **Manga Chapter Window**, and **Manga Reading Position** without carrying legacy compatibility fields or adapters.
