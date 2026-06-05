# YamiboReader

YamiboReader reads Yamibo forum threads as native novel and manga reading experiences.

## Language

**Manga Chapter Window**:
The ordered set of currently loaded manga chapter documents used to provide continuous native manga reading around the current page.
_Avoid_: loaded documents, chapter buffer, chapter cache

**Manga Directory**:
The known ordered chapter list for one manga title.
_Avoid_: chapter list, table of contents

**Manga Chapter Document**:
The parsed image-page content for one manga thread chapter.
_Avoid_: loaded chapter, chapter HTML

**Manga Reading Position**:
The reader's current page position within a manga chapter, identified by chapter `tid` and local page index.
_Avoid_: focus, progress, page focus

**Novel Reading Session**:
The state machine for native novel reading, holding the current reader page document, optional prefetched reader page document, pagination output, and current novel reading position.
_Avoid_: reader container state, reader model state, document buffer

**Novel Reading Position**:
The reader's semantic position in a novel thread, identified by web view page, chapter, segment index, Swift `Character` segment offset, and intra-page progress.
_Avoid_: page index, progress, scroll position

**Novel Text Layout**:
The native text layout process that turns a novel reader page document's text segments into rendered page ranges, vertical chunk ranges, measured heights, display layouts, and chapter starts.
_Avoid_: layout engine, textkit wrapper, paginator internals, reader paginator, text view fallback

**Novel Text Viewport**:
The stateful TextKit 2 viewport inside **Novel Text Layout** that lazily lays out visible text fragments while maintaining exact page, chapter, and position indexes for native novel reading.
_Avoid_: scroll view text cache, lazy text view, visible text renderer, viewport wrapper

**Novel Text Viewport Index**:
The exact, cacheable page, chapter, range, and position map built by **Novel Text Layout** before a **Novel Text Viewport** is published to the **Novel Reading Session**.
_Avoid_: estimated page cache, lazy page count, progress approximation, scroll offset index

**Novel Text Display Value**:
The cross-platform rendered text value produced by **Novel Text Layout** for platform adapters to materialize into native TextKit 2 drawing.
_Avoid_: display recipe, display plan, attributed string cache, layout manager, text view model

**Novel Text Attributed Document**:
The attributed document semantics owned by **Novel Text Layout** for TextKit 2 measurement and drawing, including chapter title styling, paragraph indentation, font family, kerning, line height, and justification.
_Avoid_: attributed string helper, UI text style factory, platform text builder, display adapter styling

**Favorite Library**:
The local projection of Yamibo remote favorites plus user-owned reading metadata, display names, hidden state, and collections.
_Avoid_: favorite store, favorites snapshot, favorites list

## Relationships

- A **Manga Directory** contains zero or more **Manga Chapter Documents** by chapter identity.
- A **Manga Chapter Window** contains one or more loaded **Manga Chapter Documents** from a **Manga Directory**.
- A **Manga Chapter Window** preserves the current **Manga Reading Position** while adding or trimming **Manga Chapter Documents**.
- A **Manga Chapter Window** uses chapter `tid` as the canonical chapter identity; chapter URLs are loading and display metadata.
- A **Manga Chapter Window** extends continuous reading by inserting adjacent **Manga Chapter Documents** and handles distant jumps through an explicit reset.
- If a **Manga Reading Position** points past the available pages in its **Manga Chapter Document**, the **Manga Chapter Window** resolves it to the nearest valid page in that chapter.
- A **Manga Chapter Window** can reset to a **Manga Chapter Document** that is not yet known by the **Manga Directory**, but adjacent insertion requires directory adjacency.
- A **Novel Reading Session** paginates the current reader page document and can merge an adjacent prefetched reader page document for continuous vertical reading.
- A **Novel Reading Session** preserves the **Novel Reading Position** when layout or reading mode changes cause repagination.
- A **Novel Reading Session** can promote its prefetched reader page document to become the current reader page document when page navigation crosses the web view page boundary.
- **Novel Text Layout** is the single source of rendered text ranges, measured text heights, native text display layouts, and chapter starts for native novel reading.
- UIKit and AppKit TextKit 2 implementations are adapters behind the same **Novel Text Layout** seam.
- On supported Apple platforms, **Novel Text Layout** uses TextKit 2 as the authoritative layout implementation and does not fall back to estimated text slicing when layout fails.
- **Novel Text Layout** exposes layout failures explicitly so the **Novel Reading Session** can surface them instead of treating them as empty content.
- **Novel Text Layout** must preserve **Novel Reading Position** semantics by returning segment offsets and intra-page progress rather than TextKit-internal positions.
- **Novel Text Viewport Index** build failure is a reader error; native novel reading may retry indexing or open the source web view, but must not fall back to old pagination, estimated slicing, SwiftUI text chunks, or page-level offset fallbacks.
- A **Novel Text Viewport** belongs to **Novel Text Layout** and owns the live TextKit 2 viewport object graph; SwiftUI observes it through platform adapters rather than hosting text chunks directly.
- A **Novel Text Viewport** must keep page counts, chapter starts, and **Novel Reading Position** restoration exact when the reader opens, even if drawing of text fragments remains viewport-lazy.
- A **Novel Text Viewport Index** must be complete before the **Novel Reading Session** publishes readable content; loading UI is preferable to showing approximate page counts or chapter positions.
- A **Novel Text Viewport Index** is cacheable by reader page document identity, text-affecting appearance settings, container layout, reading mode, and two-page spread presentation.
- A **Novel Text Viewport Index** may be stored on disk, but live TextKit objects stay in memory under a session-scoped `@MainActor` runtime owner held by the **Novel Reading Workflow**; cached indexes must carry text and layout fingerprints.
- A **Novel Text Viewport Index** has one top-level identity for a current reader page document, with mode-specific paged and vertical projections that share one semantic map from TextKit document ranges to **Novel Reading Position** ranges.
- The primary **Novel Text Layout** Interface is viewport-first: it publishes a **Novel Text Viewport** context, a **Novel Text Viewport Index**, and index-aware external blocks before any rendered-page compatibility output is derived.
- A **Novel Text Viewport** owns the current reader page document's text flow first; inline images remain index-aware external blocks and are not TextKit attachments unless a later decision explicitly changes that.
- **Novel Text Viewport Index** page entries may contain text ranges and index-aware external block references; SwiftUI and platform adapters render image external blocks through image adapters rather than through rendered-page compatibility blocks.
- A **Novel Text Viewport** preserves original reader page document segment boundaries when composing its TextKit document; inserted separators are layout glue and must not become saved **Novel Reading Position** offsets.
- Persisted **Novel Reading Position** segment offsets use Swift `Character` offsets in the displayed text after translation-mode transformation.
- TextKit adapters may use `NSTextLocation`, `NSTextRange`, `NSRange`, or UTF-16 offsets internally, but conversion to and from persisted **Novel Reading Position** offsets belongs inside **Novel Text Layout** and must not leak into SwiftUI.
- Production **Novel Text Layout** derives page ranges and chunk ranges from the complete composed **Novel Text Viewport** document through TextKit 2; `TextSlice` is a temporary internal compatibility or test Adapter shape and the final migration target is to remove `TextSlice`.
- **Novel Text Layout** owns the **Novel Text Attributed Document** semantics; `AttributedString` is shorthand for that ownership, not a requirement that callers traffic in Swift `AttributedString` values.
- **Novel Text Attributed Document** is an internal Module behind the **Novel Text Layout** seam; callers must not receive or provide `AttributedString`, `NSAttributedString`, platform text storage, or `NSTextLayoutManager` objects.
- The external drawing Interface of **Novel Text Layout** is high-level **Novel Text Viewport** creation and update; SwiftUI and platform adapters ask **Novel Text Layout** to create or update viewport surfaces rather than materializing attributed documents themselves.
- Text measurement belongs to the same **Novel Text Viewport** creation and update path; callers must not use a separate text-height measurement Interface such as measuring a **Novel Text Display Value** directly.
- UIKit and AppKit TextKit 2 adapters materialize the **Novel Text Attributed Document** into platform text storage for `NSTextLayoutManager`; SwiftUI must not assemble chapter title styling, paragraph indentation, font family, kerning, line height, or justification itself.
- In paged reading mode, SwiftUI hosts a UIKit collection-view pager through `UIViewRepresentable`; collection-view cells are page or spread surfaces that share one current-reader-page-document **Novel Text Viewport** context.
- Paged collection-view cells consume **Novel Text Viewport Index** page and spread identities only; they do not compute page ranges, chapter starts, spread pairing, or **Novel Reading Position** offsets.
- In vertical reading mode, SwiftUI hosts a UIKit-backed **Novel Text Viewport** scroll view through `UIViewRepresentable`; SwiftUI must not host text chunks or sample text positions from view-frame heuristics.
- **Novel Reading Session** remains a pure-value `Sendable` state machine and must not own live TextKit objects or become main-actor isolated.
- A session-scoped `@MainActor` runtime owner is held by the **Novel Reading Workflow** for the current **Novel Reading Session** lifecycle; all live TextKit 2 object graphs remain hidden inside the **Novel Text Layout** Implementation.
- The runtime owner and its UIKit/AppKit TextKit 2 adapters live in `YamiboReaderCore`, preserving the dependency direction in which `YamiboReaderUI` depends on Core.
- The **Novel Reading Workflow** creates, updates, and releases the runtime owner; the runtime owner is not stored in **Novel Reading Snapshot** or any other pure-value `Sendable` state.
- `YamiboReaderUI` consumes opaque **Novel Text Viewport** display references issued by Core and does not access the runtime owner itself.
- A **Novel Text Viewport** display reference is a main-actor-isolated opaque reference containing only a weak runtime-owner reference, a runtime generation, and a **Novel Text Viewport Index** page identity.
- A display reference does not retain `NSTextLayoutManager`, text fragments, attributed documents, or platform views.
- Changes to the reader page document, reading mode, container layout, or text display semantics increment the runtime generation and make previously issued display references explicitly stale.
- A stale display reference must report staleness and must not draw previous content, rebuild a TextKit object graph, or silently resolve itself against a newer runtime generation.
- `YamiboReaderUI` requests current display references through the **Novel Reading Workflow** by **Novel Text Viewport Index** page identity; attributed-document reuse remains an internal runtime-owner decision across generation changes.
- A **Novel Text Viewport** update is an atomic runtime transaction: the runtime owner builds the next attributed document or layout projection, complete **Novel Text Viewport Index**, layout metrics, and runtime generation from one TextKit 2 object graph.
- The **Novel Reading Workflow** publishes the resulting pure-value **Novel Text Layout** result to the **Novel Reading Session** only after the runtime transaction succeeds completely.
- If an update transaction fails, the **Novel Reading Workflow** preserves the previous **Novel Reading Snapshot**, runtime generation, and drawable **Novel Text Viewport**; an initial transaction failure publishes no readable content and surfaces a reader error.
- **Novel Reading Session** consumes successful pure-value **Novel Text Layout** results for position resolution and state transitions; it does not invoke a pagination or layout closure and does not independently rebuild a **Novel Text Viewport Index**.
- The **Novel Text Viewport Index**, layout metrics, display references, and drawn fragments for one published generation must all derive from the same active TextKit 2 layout projection.
- HTML text transformation, chapter annotation, and semantic attributed-document preparation may run off the main actor when their outputs remain pure-value and `Sendable`.
- Creating or mutating `NSTextContentStorage`, `NSTextLayoutManager`, TextKit layout fragments, the complete **Novel Text Viewport Index**, and the committed runtime generation occurs inside the main-actor runtime transaction.
- An initial runtime transaction shows loading UI until the complete **Novel Text Viewport Index** is ready; it does not publish approximate page counts or readable content.
- When a readable generation already exists, a settings, layout, or reading-mode update may keep displaying that generation until the replacement transaction commits atomically.
- Runtime update transactions are cancellable and latest-wins: superseded appearance, rotation, container-layout, or reading-mode requests must not commit after a newer request.
- Prefetch prepares only pure-value reader page documents and semantic inputs; it does not create a second live TextKit runtime.
- Each **Novel Reading Workflow** owns at most one live **Novel Text Viewport** runtime owner, and that runtime represents only the current reader page document.
- Promoting a prefetched reader page document performs an atomic replacement transaction on the existing runtime owner; success invalidates the previous generation and its display references, while failure preserves the current document, generation, and readable content.
- Closing the reader or releasing the **Novel Reading Workflow** releases the live TextKit object graph immediately.
- Memory pressure may remove semantic attributed-document caches and non-current generation data, but it must not invalidate the currently drawable generation.
- Live TextKit runtimes are not retained in an LRU across reader page documents; only pure-value **Novel Text Viewport Index** data and semantic inputs may be cached across documents.
- One current reader page document has one shared TextKit 2 content storage inside that runtime owner.
- The runtime owner has one active TextKit 2 layout projection for the current reading mode and container layout; paged and vertical projections do not stay live concurrently.
- Changing reading mode or container layout rebuilds the active layout projection while reusing the reader page document's semantic attributed document when its text-affecting appearance settings have not changed.
- Page, spread, and vertical chunk surfaces must not create per-surface `NSTextContentStorage`, `NSTextLayoutManager`, or attributed document copies.
- The runtime owner is the only `NSTextViewportLayoutControllerDelegate` for the active layout projection.
- Page, spread, and vertical chunk surfaces hold opaque display references identified by runtime generation and **Novel Text Viewport Index** page identity; they do not hold **Novel Text Display Values** or live TextKit objects.
- Platform coordinators report visible **Novel Text Viewport Index** page identities to the runtime owner; they do not directly request TextKit layout fragments or invalidate TextKit caches.
- The runtime owner converts visible page identities into the active TextKit document viewport, performs viewport-lazy layout, draws visible fragments, samples **Novel Reading Position**, and resolves restoration anchors.
- UIKit and AppKit expose lightweight **Novel Text Viewport** surface adapters backed only by an opaque display reference.
- A surface adapter passes its page-local bounds, graphics context, sampling points, and restoration requests through the display reference; it does not own TextKit objects, perform text measurement, or decide layout invalidation.
- The runtime owner maps page-local surface coordinates into the shared TextKit document layout, performs viewport-lazy fragment drawing, and maps sampling or restoration results back into **Novel Reading Position** semantics.
- Reusing a page or chunk cell replaces its display reference without rebuilding the shared TextKit object graph.
- A surface presented with a stale display reference draws no previous text and reports that the caller must request a current display reference.
- SwiftUI, UIKit, and AppKit platform adapters hold short-lived display references only; coordinators, pagers, and cells must not own the **Novel Text Viewport** runtime or decide its cache invalidation.
- The live-runtime migration is complete only when Core tests cover atomic commit, failed-update rollback, latest-wins cancellation, generation invalidation, and prefetched-document promotion.
- UI tests must verify that reused cells replace only their opaque display reference and that stale display references never draw previous content.
- Integration tests must verify that paged, vertical, two-page spread, rotation, appearance changes, and reading-mode changes publish indexes and draw surfaces from one runtime generation.
- Runtime diagnostics for one **Novel Reading Workflow** must report one `NSTextContentStorage`, one active `NSTextLayoutManager`, and zero per-page TextKit document object graphs.
- Completion requires deleting `NovelTextLayoutLiveSurfaceStore`, `NovelTextLayoutLiveSurface`, the per-page `NovelTextViewportDisplayUIView` TextKit object graph, and UI-owned text measurement or TextKit cache invalidation.
- Completion also requires **Novel Reading Session** to remain pure-value and `Sendable`, with no TextKit or platform UI imports.
- A **Novel Reading Position** segment offset is measured in the current displayed text after translation-mode transformation; changing translation mode restores by nearest indexed range, chapter, and intra-page progress rather than promising source-text character identity.
- **Novel Reading Position** is text-only; when a vertical **Novel Text Viewport** reference line falls on an inline image or other external block, save and restore logic snaps to the nearest indexed text range rather than saving an external block identity.
- If a reader page document has no indexed text range, save and restore logic preserves the previous text-only **Novel Reading Position** while the visible web view page may still advance.
- A **Novel Text Display Value** belongs to rendered text blocks in a **Novel Reading Session** and carries text style semantics plus rendered text ranges.
- **Novel Reading Session** derives page-level text ranges from the **Novel Text Display Values** inside a rendered page; rendered pages must not store a separate aggregate text range list.
- A **Novel Text Display Value** must not contain live TextKit objects such as `NSTextLayoutManager`, UIKit/AppKit views, or mutable platform text storage.
- `ReaderPaginationResult` is a temporary compatibility Adapter output derived from the viewport-first **Novel Text Layout** result for callers that have not yet migrated to **Novel Text Viewport Index**; the final migration target is to remove `ReaderPaginationResult`.
- `ReaderRenderedPage` is a temporary compatibility Adapter output for UI paths that have not yet consumed **Novel Text Viewport Index** directly; it must not be the source of page counts, chapter starts, image placement, or **Novel Reading Position** ranges, and the final migration target is to remove `ReaderRenderedPage`.
- SwiftUI and platform adapters materialize a **Novel Text Display Value** into TextKit 2 drawing objects; they do not decide **Novel Reading Position** ranges or text style semantics.
- In paged reading mode, SwiftUI hosts fixed-size page views whose text is drawn from **Novel Text Layout**; text views must not resize the page using their own fitting pass.
- **Novel Text Layout** display failures are reader errors, not opportunities to fall back to SwiftUI text, UIKit text views, AppKit text views, or estimated slicing.
- `ReaderPaginator` is only a compatibility shim; do not reintroduce it, text view fitting, or estimated slicing as a production alternative to **Novel Text Layout**.
- A **Favorite Library** is remote-favorite-first: Yamibo remote favorites decide which remote-backed favorite entries exist, while local metadata preserves user-owned reading and organization state for those entries.
- When a Yamibo remote favorite disappears, the **Favorite Library** removes it from the visible library and archives its local metadata so a later remote re-add can restore reading position, display name, hidden state, and collection membership.
- Archived **Favorite Library** metadata is synchronized through WebDAV with the visible library because reading position and organization state are user-owned data.
- Archived **Favorite Library** metadata is matched by canonical thread URL, not Yamibo remote favorite ID, because a remote favorite ID can change when the same thread is removed and re-added.
- When archived **Favorite Library** metadata restores a favorite whose collection no longer exists, the favorite is restored at the root while preserving display name, hidden state, and reading positions.

## Example Dialogue

> **Dev:** "When the reader is near the end of a chapter, should we append the next **Manga Chapter Document** to the **Manga Chapter Window**?"
> **Domain expert:** "Yes, if the next chapter is adjacent in the **Manga Directory**; preserve the current **Manga Reading Position** while extending the window."

## Flagged Ambiguities

- "loaded documents" refers to the implementation detail behind a **Manga Chapter Window**; use **Manga Chapter Window** when discussing the reader-visible continuity behavior.
- "focus" refers to a **Manga Reading Position** when discussing manga reader continuity; reserve focus for implementation details if needed.
- If a chapter `tid` and chapter URL disagree, the **Manga Chapter Window** trusts the `tid`.
