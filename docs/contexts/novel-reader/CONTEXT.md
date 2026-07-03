# YamiboReader Novel Reader Context

Domain language for native novel reading, TextKit layout, runtime generations, and SwiftUI presentation.

Novel detail parity uses the current KMP/Compose `yamibo-app` implementation as the behavioral reference. Do not use the old Android `YamiboReaderPro` app as an acceptance reference.

## Language

**Novel Reading Session**:
The pure-value state machine for native novel reading that consumes committed layout results and derives semantic reading position and Presentation revisions without owning prefetched documents or performing layout.
_Avoid_: reader container state, reader model state, document buffer

**Novel Detail**:
The shared native intermediate surface for a novel thread before entering novel reading. It follows the current KMP app behavior by presenting novel-thread metadata, chapter or post entry points, favorite state, and reading entry actions rather than reusing the novel reader page document as its data model.
_Avoid_: direct novel reader, reader page document, novel web page

**Novel Reader Projection**:
The derived novel-reading document built from a forum **Thread Page** for native text layout, chapter identity, segment identity, image references, and reader cache management. It is a materialized reader input, not the authoritative cached source of novel-thread content.
_Avoid_: source cache, thread page, web page snapshot

**Novel Offline Cache**:
User-retained novel-thread content saved so native novel reading can continue when online refresh cannot provide current content.
_Avoid_: web page cache, transparent cache, projection cache, expired thread page cache

**Novel Offline Fallback**:
The reader behavior that automatically opens a matching **Novel Offline Cache** entry after the online load path cannot provide readable content.
_Avoid_: explicit offline mode, manual offline entry, projection fallback

**Novel Offline Cache Entry**:
One saved reader view in **Novel Offline Cache**, identified by Yamibo thread `tid`, author identity, content source, and reader view.
_Avoid_: whole novel cache, thread cache, projection entry

**Novel Offline Source Page**:
The author-scoped forum **Thread Page** snapshot persisted as the authoritative readable content for one **Novel Offline Cache Entry**.
_Avoid_: reader projection, flattened text, transparent thread page cache

**Novel Offline Image Asset**:
User-retained image bytes saved for an inline image referenced by a **Novel Offline Source Page** when novel offline image caching is enabled.
_Avoid_: transparent image cache, manga offline image, projection image

**Novel Offline Cache Queue**:
The persistent queue of user-requested **Novel Offline Cache Entry** saves and refreshes, including source-page acquisition, optional image asset acquisition, progress, failure, and retry state.
_Avoid_: cache progress sheet, transparent cache fill, immediate cache operation

**Novel Offline Auto Refresh**:
The setting-controlled behavior that refreshes existing **Novel Offline Cache Entry** records without a per-entry user command.
_Avoid_: ordinary online read, transparent cache refresh, silent new cache creation

**Novel Offline Update Time**:
The last time a **Novel Offline Cache Entry** successfully persisted a **Novel Offline Source Page**.
_Avoid_: enqueue time, failure time, projection prewarm time

**Novel Reading Position**:
The reader's semantic position in a novel thread, identified by reader page document view, chapter identity, text segment identity, and Swift `Character` offset in displayed transformed text.
_Avoid_: page index, progress, scroll position

**Novel Chapter Identity**:
The stable identity assigned by HTML parsing to one chapter occurrence within a reader page document, using owner post provenance when available and deterministic source occurrence when it is not.
_Avoid_: chapter title, chapter ordinal, chapter index

**Novel Text Segment Identity**:
The stable identity assigned by HTML parsing to one text segment within a chapter occurrence, derived from chapter identity and deterministic source occurrence rather than its current document array index.
_Avoid_: segment index, text range, DOM node index

**Novel Reader Presentation**:
The immutable SwiftUI-facing value published for one committed novel reader generation and navigation revision, containing committed appearance, surface and spread projections, current reading position, chapter projection, and reader page document metadata.
_Avoid_: reader view model fields, published pagination state, UI snapshot

**Novel Reader Surface Identity**:
The opaque, generation-scoped identity of one presented text or external-block surface, composed from runtime generation and surface ordinal without exposing page-index semantics.
_Avoid_: page index, rendered page index, collection index path

**Novel Page Turn Direction**:
The user's preferred horizontal page order for paged novel reading modes.
_Avoid_: swipe direction, gesture direction

**Novel Text Layout**:
The native text layout process that turns a novel reader page document's text segments into rendered page ranges, vertical chunk ranges, measured heights, display layouts, and chapter starts.
_Avoid_: layout engine, textkit wrapper, paginator internals, reader paginator, text view fallback

**Novel Text Viewport**:
The stateful TextKit 2 viewport inside **Novel Text Layout** that lazily lays out visible text fragments while maintaining exact page, chapter, and position indexes for native novel reading.
_Avoid_: scroll view text cache, lazy text view, visible text renderer, viewport wrapper

**Novel Text Viewport Index**:
The exact generation-scoped surface, chapter, range, geometry, and position map built internally by **Novel Text Layout** before a committed result reaches the **Novel Reading Session**.
_Avoid_: estimated page cache, lazy page count, progress approximation, scroll offset index

**Novel Text Display Value**:
The cross-platform rendered text value produced by **Novel Text Layout** for platform adapters to materialize into native TextKit 2 drawing.
_Avoid_: display recipe, display plan, attributed string cache, layout manager, text view model

**Novel Text Attributed Document**:
The attributed document semantics owned by **Novel Text Layout** for TextKit 2 measurement and drawing, including chapter title styling, paragraph indentation, font family, kerning, line height, and justification.
_Avoid_: attributed string helper, UI text style factory, platform text builder, display adapter styling

## Relationships

- **Novel Detail** uses its own detail model and repository while reusing lower-level Yamibo fetching, parsing utilities, favorite state, and reading progress stores where appropriate.
- **Novel Detail** header metadata is driven by the structured forum **Thread Page**: parsed thread title, first-post author, post time, view/reply counts, forum label, and the first valid non-emoticon image cover candidate. Unfiltered all-posts **Thread Page** data may supply only header-level metadata and author-scope discovery; novel preview text and readable chapter entry points require an author-scoped **Thread Page**.
- A forum **Thread Page** is the authoritative source model for novel-thread content that can be reused by native novel reading. A **Novel Reader Projection** may be cached for layout and offline prewarming, but it is derived from a **Thread Page** rather than being a second source of truth.
- Native novel reading must not use a cached **Novel Reader Projection** as an offline substitute when the corresponding authoritative **Thread Page** is unavailable for that reader view and author scope.
- Legacy cached **Novel Reader Projection** data that cannot be validated against an author-scoped **Thread Page** is invalid for novel reading and cache-management state; it may be cleaned up lazily during view update or deletion.
- Novel reader cache management reports, creates, updates, and deletes cached reader views according to **Novel Offline Cache Entry** records. A cached transparent **Thread Page** or **Novel Reader Projection** alone must not make a view appear cached or offline-ready.
- Novel reader cache management should use offline-cache and download-queue language rather than "web page cache" language, because reader cache actions create user-retained **Novel Offline Cache** entries.
- Novel reader cache sheet row state remains coarse: cached, uncached, or caching. Failed, queued, paused, and running details belong in the shared **Download Queue** sheet rather than in each reader cache row.
- In the novel reader cache sheet, unfinished **Novel Offline Cache Queue** work makes the matching row appear caching even when an older **Novel Offline Cache Entry** is already offline-readable. The row's displayed update time still comes from the last successful **Novel Offline Update Time**.
- Deleting a cached novel reader view removes its **Novel Offline Cache Entry** without clearing transparent **Thread Page** or **Novel Reader Projection** caches.
- Creating or updating a cached novel reader view enqueues **Novel Offline Cache Queue** work rather than running only as an in-reader transient progress operation.
- **Novel Offline Cache Queue** work appears in the shared **Download Queue** alongside manga offline-cache work, with queue rows preserving their reader context.
- **Novel Offline Cache Queue** work executes one reader view at a time. When novel offline image caching is enabled, image acquisition within the active work may use bounded concurrency.
- Adding a **Novel Offline Cache Entry** to the queue is idempotent. Existing unfinished work is not duplicated, already cached entries are not queued by a plain cache action, and explicit update or retry commands target existing failed or paused work before creating new refresh work.
- Novel reader prefetch prioritizes fetching and saving the next author-scoped **Thread Page**. Prewarming the next **Novel Reader Projection** is a nonfatal optimization.
- **Novel Offline Cache** saves reader views as **Novel Offline Cache Entry** records. A whole-novel cache action is a batch operation over entries rather than a separate authoritative cache unit.
- A **Novel Offline Cache Entry** is created or refreshed only by user cache intent. Successful ordinary online reading may update transparent caches and projection prewarming, but it must not silently create user-retained offline content.
- Creating **Novel Offline Cache Queue** work does not require the novel thread to exist in the **Favorite Library**. Favorite metadata may help presentation, but it does not own **Novel Offline Cache** identity, state, or deletion.
- A **Novel Offline Cache Entry** owns a **Novel Offline Source Page** as its authoritative offline content, its **Novel Offline Update Time**, and any user-retained **Novel Offline Image Asset** records acquired for that entry. Any persisted **Novel Reader Projection** for that entry is optional prewarming and may be regenerated from the **Novel Offline Source Page**.
- A **Novel Offline Cache Entry** is offline-readable only when its **Novel Offline Source Page** is durable. Batch cache actions may partially succeed across entries, and successful entries remain offline-readable even when neighboring entries fail.
- Novel offline image caching is controlled by system settings. When enabled, **Novel Offline Cache Queue** work should acquire **Novel Offline Image Asset** records for cached source pages; when disabled, text and structure remain the offline success boundary and inline images may rely on ordinary image caching or network availability.
- For manual cache update, durable **Novel Offline Source Page** replacement updates the entry and its **Novel Offline Update Time** even if optional **Novel Offline Image Asset** acquisition later fails and leaves queue work failed for retry.
- Enabling novel offline image caching is not retroactive by itself. Existing entries acquire missing **Novel Offline Image Asset** records only through later update, retry, or **Novel Offline Auto Refresh** work.
- Disabling novel offline image caching does not delete existing **Novel Offline Image Asset** records. It only stops later work from acquiring additional offline image assets unless the setting is enabled again.
- **Novel Offline Auto Refresh** refreshes existing **Novel Offline Cache Entry** records without creating new offline entries for ordinary online reading. When enabled, an ordinary online read that successfully loads current content for an already cached view replaces that entry's **Novel Offline Source Page** and updates its last successful source-page update time.
- **Novel Offline Auto Refresh** must not block readable online content on **Novel Offline Image Asset** acquisition. When novel offline image caching is enabled, image acquisition may continue through **Novel Offline Cache Queue** after the refreshed source page is durable.
- **Novel Offline Auto Refresh** source-page replacement is not itself visible **Download Queue** work when the online read already has the source page. Optional image-asset acquisition after that replacement may enter the queue.
- **Novel Offline Auto Refresh** replaces an offline source page only with readable current content. Parser, author-scope, projection-schema, or empty-content errors preserve the previous offline-readable source page.
- Saving a **Novel Offline Cache Entry** may promote a valid author-scoped transparent **Thread Page** into a **Novel Offline Source Page**, but it must copy the content into **Novel Offline Cache** instead of depending on transparent cache lifetime.
- Refreshing a **Novel Offline Cache Entry** atomically replaces its **Novel Offline Source Page** only after the new source page is durable. Refresh failure preserves the previous offline-readable content, and projection prewarming remains nonfatal.
- Deleting a **Novel Offline Cache Entry** removes user-retained offline membership, source page, and any offline projection prewarm for that entry without clearing transparent **Thread Page** or **Novel Reader Projection** caches.
- Deleting a **Novel Offline Cache Entry** also cancels unfinished or failed **Novel Offline Cache Queue** work for the same identity so the queue cannot recreate deleted offline content.
- Normal online novel reading must attempt the online load path before using **Novel Offline Fallback**. A matching **Novel Offline Cache** entry may provide readable content when the online path cannot.
- **Novel Offline Fallback** applies only when the online path cannot acquire current content, such as no network, timeout, server failure, or an expired transparent **Thread Page** refresh failure. Parser failures, projection schema incompatibility, missing author scope, and empty readable content remain reader content errors rather than fallback triggers.
- **Novel Offline Fallback** must be visible to the reader as stale offline content rather than silently masquerading as current online content, and the reader must retain a way to retry the online load path.
- **Novel Offline Fallback** does not wait for **Novel Offline Image Asset** acquisition. Available offline image assets may render, while missing image assets produce image placeholders or failures without blocking readable text.
- **Novel Offline Fallback** resolves **Novel Reading Position** against the offline-derived reader document with the same restoration fallback chain as ordinary reader opening, without fabricating chapter or segment identity for content that is missing from the offline source page.
- Reading through **Novel Offline Fallback** may update reading recency and progress, but any persisted **Novel Reading Position** must be resolved from the offline-derived reader document currently shown to the user.
- When **Novel Offline Fallback** finds a missing or stale offline **Novel Reader Projection**, it derives one from the **Novel Offline Source Page** and may write the refreshed projection back as nonfatal prewarming.
- Persisted **Novel Reader Projection** data is a performance cache and must be validated against the corresponding **Thread Page** identity, freshness, and projection schema before reuse.
- Opening the current reader view requires a valid **Novel Reader Projection** before readable content is shown. Missing, stale, or invalid persisted projection data is synchronously rederived from the valid author-scoped **Thread Page**; derivation failure is a reader content error.
- A **Novel Reader Projection** with no readable novel content is a reader content error rather than an empty readable page.
- Deriving a **Novel Reader Projection** from a **Thread Page** must preserve reader semantics such as chapter identity, text segment identity, post provenance, author-reply metadata, inline images, and styled text ranges. Flattened post text is not a sufficient projection source.
- Native novel reading must derive a **Novel Reader Projection** only from an author-scoped **Thread Page**. An unfiltered all-posts **Thread Page** may help discover author scope, but it must not produce reader content.
- If native novel reading cannot determine the author scope for a novel thread, opening reader content fails with a retryable author-scope error instead of deriving content from an unfiltered all-posts **Thread Page**.
- **Novel Detail** entry behavior follows the current KMP/Compose app: continue reading opens saved reading history when present and otherwise starts from the beginning, while selecting a chapter or post row opens that selected entry in the novel reader.
- **Novel Detail** launch context carries the thread identity, display title, and optional author identity. When the caller already knows the author identity, it passes that hint; otherwise the detail repository may recover it from thread metadata.
- Native novel reading uses Yamibo thread `tid` plus reader view, author identity, and content source as persistent thread-page and reader-cache identity; thread URLs are boundary inputs rather than stored reader identity.
- Thread or find-post links classified as novel still open **Novel Detail**. A target post identity does not bypass **Novel Detail** and does not require the detail surface to focus or highlight that post.
- **Novel Detail** may provide a secondary native discussion action that opens the same thread in **Native Thread Reader**. It does not need a separate proactive web-original action.
- A **Novel Reading Session** consumes the committed **Novel Text Layout** result for exactly one current reader page document; prefetched reader page documents remain pure-value inputs owned by the **Novel Reading Workflow** until atomic promotion.
- A **Novel Reading Session** preserves the **Novel Reading Position** when layout or reading mode changes cause repagination.
- The **Novel Reading Workflow** can atomically promote a prefetched reader page document to become the current reader page document when navigation crosses the web view page boundary; one runtime generation never merges multiple reader page documents.
- **Novel Text Layout** is the single source of rendered text ranges, measured text heights, native text display layouts, and chapter starts for native novel reading.
- The live-runtime migration targets the iOS novel reader; UIKit is the production TextKit 2 Runtime Adapter, while the test Runtime Adapter exercises the same package-internal Interface.
- Core pure-value **Novel Text Layout**, **Novel Reading Session**, offset mapping, and semantic document inputs remain cross-platform, but macOS live viewport support is deferred.
- Deferred macOS support must add a complete platform Runtime Adapter at the same seam; it must not preserve a separate shallow pagination or measurement Implementation.
- Reader settings preview uses a separate short-lived **Novel Text Layout** preview surface that reuses attributed-document styling but does not build a **Novel Text Viewport Index**, create a reader runtime generation, or mutate the active **Novel Reading Workflow**.
- SwiftUI settings UI passes preview text and draft appearance semantics to that preview surface; it does not duplicate body-text font, kerning, paragraph spacing, indentation, or justification rules.
- On supported Apple platforms, **Novel Text Layout** uses TextKit 2 as the authoritative layout implementation and does not fall back to estimated text slicing when layout fails.
- **Novel Text Layout** exposes layout failures explicitly so the **Novel Reading Session** can surface them instead of treating them as empty content.
- **Novel Text Layout** must preserve **Novel Reading Position** semantics by returning segment offsets and intra-page progress rather than TextKit-internal positions.
- **Novel Text Viewport Index** build failure is a reader error; native novel reading may retry indexing or open the source web view, but must not fall back to old pagination, estimated slicing, SwiftUI text chunks, or page-level offset fallbacks.
- A **Novel Text Viewport** belongs to **Novel Text Layout** and owns the live TextKit 2 viewport object graph; SwiftUI observes it through platform adapters rather than hosting text chunks directly.
- A **Novel Text Viewport** must keep page counts, chapter starts, and **Novel Reading Position** restoration exact when the reader opens, even if drawing of text fragments remains viewport-lazy.
- A **Novel Text Viewport Index** must be complete before the **Novel Reading Session** publishes readable content; loading UI is preferable to showing approximate page counts or chapter positions.
- Paged and vertical projections are built from complete TextKit 2 line fragments in one continuous document graph; a page or chunk boundary must fall between line fragments and must never split, duplicate, or clip a text line.
- Fixed-size paged surfaces may leave unused space below the last complete line fragment rather than moving part of that line into the next surface.
- Each committed page or vertical chunk freezes its TextKit document clip rect, visible content height, and page-local coordinate transform during index preparation.
- Runtime drawing, sampling, and restoration consume that frozen clip and transform; they must not infer a page origin from its first character, divide continuous coordinates by nominal page height, or repack fragments after commit.
- During the live-runtime migration, a new runtime generation must build and validate its authoritative **Novel Text Viewport Index** from its own candidate TextKit 2 object graph; only semantic pure-value inputs and offset maps may be reused across generations.
- Cross-generation or disk **Novel Text Viewport Index** reuse is deferred until cached indexes carry text, layout, font, platform, and TextKit implementation fingerprints and can be validated against the candidate graph before publication.
- A **Novel Text Viewport Index** has one top-level identity for a current reader page document and one active reading-mode projection backed by a semantic map from TextKit document ranges to **Novel Reading Position** ranges.
- The primary **Novel Text Layout** Interface is viewport-first: it publishes a **Novel Text Viewport** context, a **Novel Text Viewport Index**, and index-aware external blocks before any rendered-page compatibility output is derived.
- Candidate preparation may force one complete TextKit 2 layout pass to build and validate the authoritative **Novel Text Viewport Index**; after commit, the active runtime must not call `ensureLayout` for the full document range again.
- After its single complete indexing pass, the candidate freezes the pure-value Index and geometry, invalidates full-document layout information in the same TextKit graph, and uses its viewport controller to rematerialize only the initial visible and adjacent preheat surfaces.
- Before commit, the candidate verifies that rematerialized fragment anchors agree with the frozen surface ranges and geometry. Any mismatch fails the transaction rather than publishing a divergent Runtime and Index.
- Post-index compaction, viewport rematerialization, and geometry deviation are recorded in generation diagnostics.
- Each active `NSTextLayoutManager` has exactly one `NSTextViewportLayoutController`, which is the only Interface allowed to advance committed viewport layout.
- UIKit Adapters report generation-scoped visible page or chunk identities. The runtime maps them to the union of their frozen document clip rects and may include at most one adjacent surface on each side for viewport preheating.
- Committed drawing enumerates fragments only within the requested surface's frozen document range and clip rect; scrolling, page turns, and cell reuse update viewport projection without rebuilding the Index or TextKit object graph.
- A **Novel Text Viewport** owns the current reader page document's text flow first; inline images remain index-aware external blocks and are not TextKit attachments unless a later decision explicitly changes that.
- **Novel Text Viewport Index** surface entries may contain text ranges or index-aware external block references; Presentation projects image surfaces for SwiftUI image Adapters rather than rendered-page compatibility blocks.
- During the first live-runtime migration, every external block occupies its own page or vertical chunk surface; text before and after it belongs to separate text surfaces, and one surface does not mix TextKit fragments with external block content.
- The Index merges text surfaces and external block surfaces by typed semantic-run order. External blocks do not enter the TextKit document as attachments, replacement characters, or fabricated spacing glyphs.
- Supporting text-and-external-block mixed surfaces later requires an explicit composite-surface projection with multiple source slices; it must not mutate the committed single-range clip and coordinate-transform model implicitly.
- **Novel Text Layout** freezes every external block identity and frame in the committed layout projection; asynchronous image loading draws inside that frame and must not mutate the current generation's index, metrics, or geometry.
- Changing whether inline images participate in layout creates a new generation; using image intrinsic dimensions requires those dimensions as pure-value transaction input before candidate layout begins.
- A **Novel Text Viewport** preserves original reader page document segment boundaries when composing its TextKit document; inserted separators are layout glue and must not become saved **Novel Reading Position** offsets.
- Persisted **Novel Reading Position** segment offsets use Swift `Character` offsets in the displayed text after translation-mode transformation.
- A persisted **Novel Reading Position** is anchored by reader page document view, **Novel Chapter Identity**, **Novel Text Segment Identity**, and displayed-text Character offset. Runtime generation, surface identity, collection position, and displayed page number are never persisted.
- Chapter ordinal, chapter title, legacy segment index, page number, and intra-page progress may remain schema-migration hints, but they are not authoritative restoration identity.
- Restoration resolves exact text segment identity and offset first, then chapter identity, then nearest retained text in the same view, and finally the first text position in that view; equal chapter titles are never used as an identity match.
- Legacy positions may attempt one migration using their stored segment index against the matching legacy reader page document. Successful migration writes the new schema lazily; failed migration follows chapter or view fallback without fabricating identity.
- TextKit adapters may use `NSTextLocation`, `NSTextRange`, `NSRange`, or UTF-16 offsets internally, but conversion to and from persisted **Novel Reading Position** offsets belongs inside **Novel Text Layout** and must not leak into SwiftUI.
- Production **Novel Text Layout** derives page ranges and chunk ranges from the complete composed **Novel Text Viewport** document through TextKit 2; `TextSlice` is a temporary internal compatibility or test Adapter shape and the final migration target is to remove `TextSlice`.
- **Novel Text Layout** owns the **Novel Text Attributed Document** semantics; `AttributedString` is shorthand for that ownership, not a requirement that callers traffic in Swift `AttributedString` values.
- **Novel Text Attributed Document** is an internal Module behind the **Novel Text Layout** seam; callers must not receive or provide `AttributedString`, `NSAttributedString`, platform text storage, or `NSTextLayoutManager` objects.
- **Novel Text Attributed Document** is built only from typed semantic runs whose text segment, chapter title, inserted separator, external block anchor, segment identity, and chapter identity are fixed before TextKit materialization.
- Translation transformation completes before semantic run offset maps are built; chapter styling comes from run type rather than title-string parsing, and inserted separators remain explicit layout glue outside persisted **Novel Reading Position** offsets.
- A chapter title and its body may use separate semantic runs for styling, but they share one source text segment identity and one continuous persisted Character-offset space; title characters and original line breaks remain valid **Novel Reading Position** offsets.
- Only separators inserted by **Novel Text Layout** are excluded from persisted offsets; HTML parsing supplies the chapter-title range instead of requiring attributed-document code to rediscover it by matching strings.
- Text reader segments persist explicit chapter identity and a validated chapter-title Character range within segment content; the HTML parser is the only producer of that range, and image segments reference chapter identity rather than repeating title inference.
- The HTML parser assigns each chapter occurrence a stable **Novel Chapter Identity** before **Novel Text Layout** begins; owner post identity is preferred, with reader page document identity and deterministic source occurrence used when owner post provenance is unavailable.
- Chapter title is metadata and must not be used as **Novel Chapter Identity**; repeated or changed titles must not merge, split, or recreate chapter identity.
- The HTML parser assigns each text segment a stable **Novel Text Segment Identity** from its **Novel Chapter Identity** and deterministic source occurrence within that chapter; current document array index is only an Implementation detail.
- Refresh, author filtering, translation transformation, attributed-document preparation, and layout preserve the identity of every retained source text segment.
- A **Novel Text Viewport Index** derives chapter ordinal only from the document order of explicit **Novel Chapter Identity** values in that committed generation; ordinal is a presentation projection rather than persisted identity.
- Text segments, external image blocks, chapter comment targets, semantic chapter browsing, and restoration fallback reference the same **Novel Chapter Identity**.
- New reader page document encoding writes the explicit chapter structure. Legacy `chapterTitle` decoding may synthesize a title range only when the normalized title unambiguously matches the segment prefix; otherwise it preserves chapter metadata without title styling.
- Legacy reader page documents synthesize **Novel Chapter Identity** from reader page document identity and source occurrence, not by grouping equal chapter titles.
- Reader page document persistence carries a schema version and upgrades legacy documents lazily on the next successful save; no eager disk migration is required.
- Ambiguous legacy title-range migration degrades only title styling while preserving full text, Character offsets, chapter identity, and navigation. Corrupt segment content or an out-of-range explicit title range invalidates the cached document and requires source reload.
- **Novel Text Viewport Index** ranges and viewport samples resolve through semantic run identities and the internal Character-to-UTF-16 mapping rather than reconstructing segment or chapter meaning from rendered strings.
- The external drawing Interface of **Novel Text Layout** is high-level **Novel Text Viewport** creation and update; SwiftUI and platform adapters ask **Novel Text Layout** to create or update viewport surfaces rather than materializing attributed documents themselves.
- Text measurement belongs to the same **Novel Text Viewport** creation and update path; callers must not use a separate text-height measurement Interface such as measuring a **Novel Text Display Value** directly.
- The UIKit TextKit 2 Runtime Adapter materializes the **Novel Text Attributed Document** into platform text storage for `NSTextLayoutManager`; SwiftUI must not assemble chapter title styling, paragraph indentation, font family, kerning, line height, or justification itself.
- In paged reading mode, SwiftUI hosts a UIKit collection-view pager through `UIViewRepresentable`; collection-view cells consume Presentation surfaces and spreads backed by one current-reader-page-document **Novel Text Viewport**.
- Paged collection-view cells consume **Novel Reader Surface Identity** and Presentation spread projection only; they do not inspect the Index or compute ranges, chapter starts, spread pairing, or **Novel Reading Position** offsets.
- In vertical reading mode, SwiftUI hosts a UIKit-backed **Novel Text Viewport** scroll view through `UIViewRepresentable`; SwiftUI must not host text chunks or sample text positions from view-frame heuristics.
- Vertical reading presents a variable-height collection of line-fragment-aligned surfaces. Runtime preparation targets roughly 1.5 to 2 viewport heights for each text chunk but moves every boundary to a complete line-fragment boundary.
- A committed text chunk's presentation height is its frozen content height; UIKit collection layout consumes that size directly and must not remeasure text or substitute viewport-height estimates.
- Adjacent text chunks are visually continuous, with paragraph and line spacing supplied only by the attributed document. Collection spacing between text chunks is zero; explicit presentation spacing may separate external-block surfaces.
- The viewport controller preheats at most one chunk before and after the visible chunk set. Vertical reading position is sampled where a fixed viewport reference line intersects a generation-scoped surface, not inferred from content-offset percentage.
- **Novel Reading Session** remains a pure-value `Sendable` state machine and must not own live TextKit objects or become main-actor isolated.
- A session-scoped `@MainActor` runtime owner is held by the **Novel Reading Workflow** for the current **Novel Reading Session** lifecycle; all live TextKit 2 object graphs remain hidden inside the **Novel Text Layout** Implementation.
- The runtime owner and UIKit TextKit 2 Runtime Adapter live in `YamiboReaderCore`, preserving the dependency direction in which `YamiboReaderUI` depends on Core.
- The **Novel Reading Workflow** creates, updates, and releases the runtime owner; the runtime owner is not stored in **Novel Reading Snapshot** or any other pure-value `Sendable` state.
- `YamiboReaderUI` consumes opaque **Novel Text Viewport** display references issued by Core and does not access the runtime owner itself.
- `YamiboReaderUI` publishes readable content through one immutable **Novel Reader Presentation** field; each committed generation or accepted navigation revision atomically replaces that value, and its surfaces, chapters, geometry, spreads, committed settings, and position are not independently published.
- Loading and replacement-failure states may be published separately, but they must not mutate the current committed **Novel Reader Presentation**.
- `ReaderContainerModel` is a SwiftUI Adapter over the **Novel Reading Workflow** rather than a second reader state owner. Presented surfaces, chapters, current view and position, committed settings, presentation geometry, and spread projection are computed from its single published **Novel Reader Presentation**.
- `ReaderContainerModel` must not retain duplicate current or prefetched reader page documents, author identity, document page counts, pagination closures, or independently synchronized reader-layout fields.
- SwiftUI-only transient state such as chrome visibility, sheet presentation, settings drafts, and error presentation may remain in the Adapter; chapter comments and cache operations remain separate Modules with their own state.
- All reader navigation and layout commands pass through the Workflow Interface. The Adapter must not paginate, rebuild an Index, or synchronize a Presentation by assigning its fields one at a time.
- `NovelTextLayoutResult`, `NovelTextViewportContext`, the composed semantic document, offset maps, authoritative **Novel Text Viewport Index**, frozen TextKit document geometry, and runtime diagnostics are package-internal Core values.
- The public **Novel Reader Presentation** exposes only UI surface projections: runtime generation and revision, surface identity and kind, presentation size, external block projection, chapter metadata, spread projection, committed settings, and current semantic reading state.
- A **Novel Reader Surface Identity** is a pure `Hashable` and `Sendable` value containing opaque runtime generation and surface ordinal. Presentation values carry surface identities rather than main-actor display references or bare page indexes.
- SwiftUI requests an opaque display reference from the Workflow Interface using the complete **Novel Reader Surface Identity**; the Workflow returns one only when that identity belongs to the active generation.
- Visible-surface reports, viewport samples, scrub targets, restoration requests, cell reuse, and spread projection use complete **Novel Reader Surface Identity** values. A new generation may restart surface ordinal numbering, but every identity from an older generation remains invalid.
- Presentation exposes an ordered surface collection and current selected surface identity. SwiftUI may use collection offsets and `IndexPath` values only for local rendering and progress labels within that exact Presentation revision.
- Collection offsets, `IndexPath` values, and displayed page numbers never cross the Workflow Interface. Previous, next, and chapter-navigation commands are resolved by the Workflow from the current Presentation revision.
- Selection, completed scrolling, and scrub interactions return a **Novel Reader Surface Identity** together with the generation and revision from which the interaction began.
- Navigation revisions within one generation preserve the surface collection and identities while changing only semantic position and selection. A new layout generation atomically replaces the complete surface collection, and platform collections treat every new-generation surface as a new item.
- The authoritative Index produces only an ordered paged-surface projection. The Workflow derives one-page or two-page spread presentation from that committed surface collection and current device presentation environment.
- In paged reading mode, **Novel Page Turn Direction** controls physical collection order, tap-zone navigation, horizontal boundary gestures, page-curl book order, and directional chrome feedback such as progress fill direction. It does not change **Novel Reading Position** identity or semantic surface ordering.
- A spread references one or two **Novel Reader Surface Identity** values, never crosses reader page document identity, and may pair adjacent chapters or an external-block surface with its neighbor.
- An odd trailing surface uses an empty presentation slot rather than a fabricated surface. Changing single-page versus two-page presentation publishes a new revision in the same generation when text container geometry is unchanged.
- Container width, readable height, padding, or any other change that alters text surface geometry requires a new generation even when the resulting spread mode is unchanged.
- SwiftUI must not inspect segment ranges, document offsets, internal clip rects, composed attributed-document inputs, or TextKit layout metrics. A text surface receives only its opaque display reference and presentation geometry.
- Viewport samples return through the Workflow Interface, where Core resolves them to **Novel Reading Position** and publishes a new Presentation revision; UI code does not translate samples through the Index.
- Runtime and Index diagnostics are exposed only to tests and explicit Debug Interfaces, not through production SwiftUI presentation values.
- Settings whose fingerprints affect the attributed document or TextKit layout commit only through a prepared layout transaction; they replace committed Presentation settings and persist to the Settings Store only after that transaction succeeds.
- Surface appearance settings publish a new revision in the active generation without rebuilding the TextKit graph, then persist. Apple Pencil and other non-reader-layout settings commit and persist through their independent Modules.
- Failed layout settings leave committed settings unchanged, restore the SwiftUI draft to the committed Presentation, and publish a nonfatal reader error. Superseded drafts never persist.
- A Settings Store write failure after a successful Runtime or Presentation commit does not roll back readable state; it is reported as a separate retryable persistence failure.
- Runtime generation appearance identity includes only attributed-document and layout semantics. Background and other surface-only appearance belong to Presentation revision identity.
- Runtime generation identifies immutable layout payload: reader page document, committed appearance, container projection, Index, and frozen geometry. Page turns, viewport sampling, chapter selection within the current document, and other navigation do not create a new TextKit generation.
- Each accepted navigation change publishes a new immutable **Novel Reader Presentation** revision carrying the same runtime generation; revisions increase monotonically within that generation and restart from zero when a new generation commits.
- Runtime-originated events must match the Presentation generation, and asynchronous navigation results must also match the latest Presentation revision before they may publish.
- A **Novel Text Viewport** display reference is a main-actor-isolated opaque reference containing only a weak runtime-owner reference and one **Novel Reader Surface Identity**.
- A display reference does not retain `NSTextLayoutManager`, text fragments, attributed documents, or platform views.
- Changes to the reader page document, reading mode, container layout, or text display semantics increment the runtime generation and make previously issued display references explicitly stale.
- A stale display reference must report staleness and must not draw previous content, rebuild a TextKit object graph, or silently resolve itself against a newer runtime generation.
- `YamiboReaderUI` requests current display references through the **Novel Reading Workflow** by **Novel Reader Surface Identity**; attributed-document reuse remains an internal runtime-owner decision across generation changes.
- Surface identities, visible-surface reports, selection changes, viewport samples, scrub targets, and restoration requests are valid only within their **Novel Reader Presentation** generation and must carry that generation through the Workflow Interface.
- The **Novel Reading Workflow** silently ignores events from stale generations; a generation change cancels in-flight page scrub, scroll sampling, and restoration retries, then restores from the captured semantic **Novel Reading Position**.
- A reused platform cell replaces both its **Novel Reader Surface Identity** and opaque display reference; an old collection offset or surface identity must never be applied to a newer generation.
- A **Novel Text Viewport** update is an atomic runtime transaction: the runtime owner builds the next attributed document or layout projection, complete **Novel Text Viewport Index**, frozen geometry, and runtime generation from one TextKit 2 object graph.
- The runtime owner allocates an opaque, monotonically increasing generation identity when a TextKit candidate graph is created; the identity is never reused and belongs to that candidate's Index, frozen geometry, diagnostics, and eventual Presentation from the start.
- Commit activates the candidate's existing generation identity rather than assigning or rewriting it. Superseded and failed candidates consume their identities, so gaps in committed generation values are expected.
- Workflow request sequence is only a latest-wins scheduling token and must not be published or used as runtime generation identity.
- One opaque, main-actor-isolated prepared transaction owns the candidate TextKit graph, generation-scoped Index and frozen geometry, committed settings and container projection, current reader page document, and the Session-prepared revision-zero **Novel Reader Presentation**.
- Before commit, the **Novel Reading Session** deterministically derives that Presentation as a pure value without mutating the active Session and without a failure path.
- Commit is one synchronous main-actor operation with no suspension: it activates the candidate graph, replaces Session state, and publishes the Workflow Presentation together. SwiftUI must never observe a new Index with the old graph or new settings with the old Presentation.
- The previous active graph is released only after the atomic replacement completes. Any failure before commit discards the entire prepared transaction and leaves active Runtime, Session, Workflow Presentation, settings, layout, and reading position unchanged.
- Navigation-only Presentation revisions bypass layout transactions and must not replace or mutate the active TextKit graph.
- The **Novel Reading Workflow** publishes the resulting pure-value **Novel Text Layout** result to the **Novel Reading Session** only after the runtime transaction succeeds completely.
- If an update transaction fails, the **Novel Reading Workflow** preserves the previous **Novel Reading Snapshot**, runtime generation, and drawable **Novel Text Viewport**; an initial transaction failure publishes no readable content and surfaces a reader error.
- A runtime transaction finishes as committed, superseded, or failed; superseded transactions are silent and failed transactions carry a stage-specific **Novel Text Layout** failure without exposing TextKit types.
- Layout-affecting settings and container inputs become committed reader state only with the generation they produced; Presentation-only inputs commit with their revision. A failed replacement keeps the previous committed inputs and restores UI controls to them.
- **Novel Text Layout** failures distinguish semantic document preparation, offset mapping, TextKit indexing, committed geometry validation, and external block projection; lower-level diagnostics remain inside the **Novel Text Layout** Implementation.
- **Novel Reading Session** consumes successful pure-value **Novel Text Layout** results for position resolution and state transitions; it does not invoke a pagination or layout closure and does not independently rebuild a **Novel Text Viewport Index**.
- The **Novel Text Viewport Index**, frozen geometry, display references, and drawn fragments for one published generation must all derive from the same active TextKit 2 layout projection.
- HTML text transformation, chapter annotation, and semantic attributed-document preparation may run off the main actor when their outputs remain pure-value and `Sendable`.
- Off-main semantic preparation receives one immutable `Sendable` snapshot containing parsed document schema, chapter and segment identities, transformed text and Character offset maps, external-block descriptors, and semantic settings and layout fingerprints.
- Semantic output is structurally validated before TextKit materialization and, after candidate creation begins, the transaction never rereads mutable Workflow, SwiftUI Adapter, or Settings Store state.
- Creating or mutating `NSTextContentStorage`, `NSTextLayoutManager`, TextKit layout fragments, the complete **Novel Text Viewport Index**, and the committed runtime generation occurs inside the main-actor runtime transaction.
- Main-actor TextKit materialization resolves actual platform fonts and fallbacks, builds the platform attributed document, creates the candidate graph, builds the Index, and freezes geometry.
- Runtime generation identity is allocated only when TextKit candidate graph creation begins; cancellation or supersession during pure semantic preparation does not consume a generation identity.
- Font fingerprints use the actual resolved platform font descriptors and fallback information rather than only the `ReaderFontFamily` setting. The committed result retains semantic, text, layout, font, platform, and TextKit implementation fingerprints for diagnostics and future cache validation.
- An initial runtime transaction shows loading UI until the complete **Novel Text Viewport Index** is ready; it does not publish approximate page counts or readable content.
- When a readable generation already exists, a settings, layout, or reading-mode update may keep displaying that generation until the replacement transaction commits atomically.
- Runtime update transactions are cancellable and latest-wins: superseded appearance, rotation, container-layout, or reading-mode requests must not commit after a newer request.
- A runtime owner may retain at most one active TextKit 2 object graph and one candidate graph; receiving newer work must not create a third graph.
- Pure semantic preparation may coalesce to the latest request, but TextKit candidate preparation is serialized. A superseded candidate is discarded at its next transaction-stage checkpoint before the latest candidate graph is created.
- Memory pressure discards any uncommitted candidate first, then rebuildable semantic attributed-document and offset-map caches; it must preserve the active committed generation and its drawable TextKit graph.
- Candidate allocation or indexing failure caused by memory pressure follows normal transaction failure semantics: an existing committed generation remains readable, while initial loading publishes an explicit failure.
- Prefetch prepares only pure-value reader page documents and semantic inputs; it does not create a second live TextKit runtime.
- Browsing chapters for a non-current reader page document uses semantic chapter identities, titles, and segment anchors only; it does not create a preview TextKit graph or promise exact page numbers.
- Selecting a chapter in a non-current reader page document starts the normal replacement transaction, and the committed generation resolves the semantic segment anchor to its exact page.
- Exact chapter page numbers are available only for the current committed **Novel Text Viewport Index**.
- Each **Novel Reading Workflow** owns at most one live **Novel Text Viewport** runtime owner, and that runtime represents only the current reader page document.
- Promoting a prefetched reader page document performs an atomic replacement transaction on the existing runtime owner; success invalidates the previous generation and its display references, while failure preserves the current document, generation, and readable content.
- Closing the reader or releasing the **Novel Reading Workflow** releases the live TextKit object graph immediately.
- Memory pressure may remove semantic attributed-document caches and non-current generation data, but it must not invalidate the currently drawable generation.
- Live TextKit runtimes are not retained in an LRU across reader page documents; during the migration only semantic pure-value inputs and offset maps may be cached across documents.
- One current reader page document has one shared TextKit 2 content storage inside that runtime owner.
- The runtime owner has one active TextKit 2 layout projection for the current reading mode and container layout; paged and vertical projections do not stay live concurrently.
- Changing reading mode or container layout rebuilds the active layout projection while reusing the reader page document's semantic attributed document when its text-affecting appearance settings have not changed.
- Page, spread, and vertical chunk surfaces must not create per-surface `NSTextContentStorage`, `NSTextLayoutManager`, or attributed document copies.
- The runtime owner is the only `NSTextViewportLayoutControllerDelegate` for the active layout projection.
- Text and external-block surfaces hold opaque display references identified by **Novel Reader Surface Identity**; they do not hold **Novel Text Display Values** or live TextKit objects.
- Platform coordinators report visible **Novel Reader Surface Identity** values through the Workflow Interface; they do not directly request TextKit layout fragments or invalidate TextKit caches.
- The runtime owner resolves visible surface identities to frozen document geometry, updates the active TextKit viewport, draws visible fragments, samples **Novel Reading Position**, and resolves restoration anchors.
- UIKit exposes lightweight **Novel Text Viewport** surface adapters backed only by an opaque display reference.
- A surface adapter passes its page-local bounds, graphics context, sampling points, and restoration requests through the display reference; it does not own TextKit objects, perform text measurement, or decide layout invalidation.
- The runtime owner maps page-local surface coordinates into the shared TextKit document layout, performs viewport-lazy fragment drawing, and maps sampling or restoration results back into **Novel Reading Position** semantics.
- Reusing a page or chunk cell replaces its display reference without rebuilding the shared TextKit object graph.
- A surface presented with a stale display reference draws no previous text and reports that the caller must request a current display reference.
- SwiftUI and UIKit platform Adapters hold short-lived display references only; coordinators, pagers, and cells must not own the **Novel Text Viewport** runtime or decide its cache invalidation.
- The live-runtime migration is complete only when Core tests cover atomic commit, failed-update rollback, latest-wins cancellation, generation invalidation, and prefetched-document promotion.
- **Novel Reading Session** tests consume committed pure-value **Novel Text Layout** fixtures; they do not inject pagination or construct live TextKit objects.
- **Novel Reading Workflow** tests use a package-internal runtime Interface with production TextKit and test Adapters; the test Adapter controls committed, superseded, and failed outcomes without exposing or faking TextKit objects.
- TextKit integration tests use the production Adapter to verify that index, frozen geometry, position conversion, sampling, and drawing belong to the same runtime generation.
- UI tests must verify that reused cells replace only their opaque display reference and that stale display references never draw previous content.
- Integration tests must verify that paged, vertical, two-page spread, rotation, appearance changes, and reading-mode changes derive internal indexes and public surface projections from one runtime generation.
- Runtime diagnostics for one **Novel Reading Workflow** report current and peak active-plus-candidate TextKit graph counts; the current count is at most two during preparation, one after commit settles, and the historical peak must never exceed two.
- Generation diagnostics report exactly one complete candidate indexing pass and zero full-document `ensureLayout` calls after that generation commits.
- Viewport diagnostics report `NSTextViewportLayoutController` updates and their generation-scoped visible and adjacent preheat surface identities.
- Drawing diagnostics report the **Novel Reader Surface Identity** and accessed fragment document range; every access must remain within that surface's frozen document range and clip rect.
- Transaction diagnostics report committed, superseded, and failed counts plus the typed failure stage, while stale-event diagnostics report rejected interaction and drawing attempts.
- Runtime signposts may measure semantic preparation, TextKit indexing, commit, viewport update, and drawing duration, but device-specific elapsed-time thresholds are performance observations rather than migration correctness requirements.
- The live-runtime migration proceeds in compileable, testable stages: parser schema and legacy migration; Runtime Interface and atomic prepared transaction; paged single-graph tracer; Presentation, Surface Identity, and Session/Workflow data flow; SwiftUI Adapter narrowing; vertical chunks, viewport controller, and post-index compaction; settings transactions and persistence; compatibility and shallow macOS-support removal; then diagnostics and full integration coverage.
- After the paged tracer commits, paged reading may use the new Runtime while vertical reading temporarily remains on its legacy path until the vertical stage completes. The legacy vertical path must not become an input, fallback, or cache source for the new Runtime.
- Each stage must leave the repository compiling and its affected tests passing; compatibility Adapters may bridge outward from committed results only until their scheduled deletion.
- Completion requires deleting `NovelTextLayoutLiveSurfaceStore`, `NovelTextLayoutLiveSurface`, the per-page `NovelTextViewportDisplayUIView` TextKit object graph, and UI-owned text measurement or TextKit cache invalidation.
- Completion also requires **Novel Reading Session** to remain pure-value and `Sendable`, with no TextKit or platform UI imports.
- A **Novel Reading Position** segment offset is measured in the current displayed text after translation-mode transformation; changing translation mode restores by text segment identity and nearest valid Character offset, then chapter identity, rather than promising source-text character identity.
- In paged two-page spread reading, current progress, save/restore, chapter context, and chrome use the visual surface on the progress edge: right surface for left-to-right page turns, left surface for right-to-left page turns, falling back to the only real surface when the progress-edge slot is blank.
- **Novel Reading Position** is text-only; when a vertical **Novel Text Viewport** reference line falls on an inline image or other external block, save and restore logic snaps to the nearest indexed text range rather than saving an external block identity.
- If a reader page document has no indexed text range, save and restore logic preserves the previous text-only **Novel Reading Position** while the visible web view page may still advance.
- A reader page document containing only external blocks may commit a readable generation with exact external block pages and frozen geometry, but it does not create a new **Novel Reading Position**.
- A transformed reader page document containing neither a valid text semantic run nor an external block fails semantic preparation as an empty document; it must not publish a fabricated empty page or compatibility footer.
- `NovelTextDisplayValue`, `ReaderPaginationResult`, and `ReaderRenderedPage` are temporary compatibility Adapter shapes and must be deleted before the live-runtime migration is complete.
- While those compatibility Adapters still exist, they may only be derived one-way from a committed **Novel Text Layout** result and must never become inputs to the **Novel Reading Session**, runtime owner, **Novel Text Viewport Index**, measurement, or drawing.
- In paged reading mode, SwiftUI hosts fixed-size page views whose text is drawn from **Novel Text Layout**; text views must not resize the page using their own fitting pass.
- **Novel Text Layout** display failures are reader errors, not opportunities to fall back to SwiftUI text, UIKit text views, or estimated slicing.
- `ReaderPaginator` is only a compatibility shim; do not reintroduce it, text view fitting, or estimated slicing as a production alternative to **Novel Text Layout**.
