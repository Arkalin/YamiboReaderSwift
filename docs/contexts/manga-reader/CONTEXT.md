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

**Manga Reading Mode**:
The user's preferred manga page navigation model, either continuous vertical reading or paged reading.
_Avoid_: reader mode, viewport type, settings mode

**Manga Page Turn Direction**:
The user's preferred horizontal page order for paged manga reading modes.
_Avoid_: swipe direction, gesture direction

**Manga Page Scale Mode**:
The user's preferred image fit strategy for paged manga reading modes.
_Avoid_: zoom level, image layout mode

**Manga Page Edge Fill**:
The user's preferred fill color for blank page-surface areas around scaled manga pages in paged reading modes.
_Avoid_: reader background, page padding color

**Manga Page Zoom**:
The user's optional magnification interaction inside a manga paged viewport. In single-page paged reading it magnifies one manga page surface; in two-page iPad landscape paged reading it magnifies the current visible **Manga Page Spread** from the viewport center tap zone.
_Avoid_: browser zoom, persistent zoom state, image browser

**Manga Page Spread**:
A paged reader display group containing one or two manga pages. It is a viewport arrangement and does not replace the page-level **Manga Reading Position**.
_Avoid_: double page position, two-page progress, spread position

## Relationships

- A **Manga Directory** contains zero or more **Manga Chapter Documents** by chapter identity.
- A **Manga Chapter Window** contains one or more loaded **Manga Chapter Documents** from a **Manga Directory**.
- A **Manga Chapter Window** preserves the current **Manga Reading Position** while adding or trimming **Manga Chapter Documents**.
- A **Manga Reader Presentation** projects a **Manga Chapter Window** into reader-visible pages and current position without changing the window.
- A **Manga Reader Presentation** may carry the current **Manga Reader Settings** so visible reader behavior reflects accepted preferences, not draft controls.
- **Manga Reader Settings** includes the current **Manga Reading Mode** so the reader can choose continuous vertical or paged navigation.
- **Manga Reader Settings** includes a **Manga Page Turn Direction** for paged **Manga Reading Mode** behavior.
- **Manga Reader Settings** includes a **Manga Page Scale Mode** for paged **Manga Reading Mode** behavior.
- **Manga Reader Settings** includes a **Manga Page Edge Fill** for blank page-surface areas in paged **Manga Reading Mode** behavior.
- A **Manga Page Spread** may show two adjacent pages in iPad landscape, but the current **Manga Reading Position** remains page-level. In two-page paged reading, the current position uses the visual page on the progress edge: right page for left-to-right page turns, left page for right-to-left page turns, falling back to the only real page when the progress-edge slot is blank.
- In paged **Manga Reading Mode**, **Manga Page Turn Direction** also controls directional chrome feedback such as progress fill direction, while progress identity remains based on page `localIndex`.
- In paged **Manga Reading Mode**, **Manga Page Scale Mode** applies to the whole page surface: fit-width pages may include top and bottom blank space, and page turns move that complete surface rather than only the image.
- In paged **Manga Reading Mode**, fit-height pages may include left and right blank space or horizontally draggable overflow. Initial overflow alignment follows **Manga Page Turn Direction**.
- In paged **Manga Reading Mode**, **Manga Page Edge Fill** colors blank page-surface areas without changing the manga image content.
- **Manga Page Zoom** is available only when reader chrome is hidden, is triggered from the paged viewport's horizontal middle third, and it does not change **Manga Reading Position**.
- Page-curl paged reading presents **Manga Page Spreads** with a book-spine model consistent with the novel reader, while comments, resume, and progress remain tied to page-level **Manga Reading Position**.
- Empty page surfaces required by the page-curl book-spine model do not create **Manga Reading Positions**.
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
