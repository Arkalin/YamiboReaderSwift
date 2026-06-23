# YamiboReader Manga Reader Context

Domain language for continuous native manga reading.

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
The reader's current page position within a manga chapter, identified by chapter `tid` and local page index. It is page-level and does not include intra-page scroll offset.
_Avoid_: focus, progress, page focus

**Manga Reader Presentation**:
The immutable reader-visible snapshot of the manga reader's current loading, readable, or error state.
_Avoid_: reader view model fields, published loading state, UI snapshot

**Manga Reader Settings**:
The user's accepted manga reading preferences, distinct from transient settings drafts.
_Avoid_: draft settings, reader controls, settings fields

**Manga Page Turn Direction**:
The user's preferred horizontal page order for paged manga reading modes.
_Avoid_: swipe direction, gesture direction

**Manga Page Scale Mode**:
The user's preferred image fit strategy for paged manga reading modes.
_Avoid_: zoom level, image layout mode

## Relationships

- A **Manga Directory** contains zero or more **Manga Chapter Documents** by chapter identity.
- A **Manga Chapter Window** contains one or more loaded **Manga Chapter Documents** from a **Manga Directory**.
- A **Manga Chapter Window** preserves the current **Manga Reading Position** while adding or trimming **Manga Chapter Documents**.
- A **Manga Reader Presentation** projects a **Manga Chapter Window** into reader-visible pages and current position without changing the window.
- A **Manga Reader Presentation** may carry the current **Manga Reader Settings** so visible reader behavior reflects accepted preferences, not draft controls.
- **Manga Reader Settings** may include a **Manga Page Turn Direction** for paged modes even before paged manga behavior is implemented.
- **Manga Reader Settings** may include a **Manga Page Scale Mode** for paged modes even before paged manga behavior is implemented.
- A **Manga Chapter Window** uses chapter `tid` as the canonical chapter identity; chapter URLs are loading and display metadata.
- A local **Manga Directory** can be recovered by contained chapter `tid` when launch context lacks the directory name.
- A **Manga Chapter Window** extends continuous reading by inserting adjacent **Manga Chapter Documents** and handles distant jumps through an explicit reset.
- If a **Manga Reading Position** points past the available pages in its **Manga Chapter Document**, the **Manga Chapter Window** resolves it to the nearest valid page in that chapter.
- A **Manga Chapter Window** can reset to a **Manga Chapter Document** that is not yet known by the **Manga Directory**, but adjacent insertion requires directory adjacency.

## Example Dialogue

> **Dev:** "When the reader is near the end of a chapter, should we append the next **Manga Chapter Document** to the **Manga Chapter Window**?"
> **Domain expert:** "Yes, if the next chapter is adjacent in the **Manga Directory**; preserve the current **Manga Reading Position** while extending the window."

## Flagged Ambiguities

- "loaded documents" refers to the implementation detail behind a **Manga Chapter Window**; use **Manga Chapter Window** when discussing the reader-visible continuity behavior.
- "focus" refers to a **Manga Reading Position** when discussing manga reader continuity; reserve focus for implementation details if needed.
- If a chapter `tid` and chapter URL disagree, the **Manga Chapter Window** trusts the `tid`.
