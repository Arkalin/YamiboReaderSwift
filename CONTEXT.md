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
The reader's semantic position in a novel thread, identified by web view page, chapter, segment index, segment offset, and intra-page progress.
_Avoid_: page index, progress, scroll position

**Novel Text Layout**:
The native text layout process that turns a novel reader page document's text segments into rendered page ranges, vertical chunk ranges, measured heights, display layouts, and chapter starts.
_Avoid_: layout engine, textkit wrapper, paginator internals

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
- **Novel Text Layout** is the single source of rendered text ranges, measured text heights, and native text display layouts for native novel reading.
- On iOS, **Novel Text Layout** uses TextKit 2 as the authoritative layout implementation and does not fall back to estimated text slicing when layout fails.
- **Novel Text Layout** exposes layout failures explicitly so the **Novel Reading Session** can surface them instead of treating them as empty content.
- **Novel Text Layout** must preserve **Novel Reading Position** semantics by returning segment offsets and intra-page progress rather than TextKit-internal positions.
- In paged reading mode, SwiftUI hosts fixed-size page views whose text is drawn from **Novel Text Layout**; text views must not resize the page using their own fitting pass.
- On iOS, **Novel Text Layout** display failures are reader errors, not opportunities to fall back to SwiftUI text or UIKit text views.
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
