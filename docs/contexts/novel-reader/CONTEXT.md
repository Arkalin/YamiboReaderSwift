# YamiboReader Novel Reader Context

Domain language for native novel reading, TextKit layout, runtime generations, and SwiftUI presentation.

## Language

**Novel Reading Session**:
The pure-value state machine for native novel reading that consumes committed layout results and derives semantic reading position and Presentation revisions without owning prefetched documents or performing layout.
_Avoid_: reader container state, reader model state, document buffer

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
- **Novel Reading Position** is text-only; when a vertical **Novel Text Viewport** reference line falls on an inline image or other external block, save and restore logic snaps to the nearest indexed text range rather than saving an external block identity.
- If a reader page document has no indexed text range, save and restore logic preserves the previous text-only **Novel Reading Position** while the visible web view page may still advance.
- A reader page document containing only external blocks may commit a readable generation with exact external block pages and frozen geometry, but it does not create a new **Novel Reading Position**.
- A transformed reader page document containing neither a valid text semantic run nor an external block fails semantic preparation as an empty document; it must not publish a fabricated empty page or compatibility footer.
- `NovelTextDisplayValue`, `ReaderPaginationResult`, and `ReaderRenderedPage` are temporary compatibility Adapter shapes and must be deleted before the live-runtime migration is complete.
- While those compatibility Adapters still exist, they may only be derived one-way from a committed **Novel Text Layout** result and must never become inputs to the **Novel Reading Session**, runtime owner, **Novel Text Viewport Index**, measurement, or drawing.
- In paged reading mode, SwiftUI hosts fixed-size page views whose text is drawn from **Novel Text Layout**; text views must not resize the page using their own fitting pass.
- **Novel Text Layout** display failures are reader errors, not opportunities to fall back to SwiftUI text, UIKit text views, or estimated slicing.
- `ReaderPaginator` is only a compatibility shim; do not reintroduce it, text view fitting, or estimated slicing as a production alternative to **Novel Text Layout**.
