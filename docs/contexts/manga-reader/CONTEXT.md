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

**Manga Offline Cache**:
The user-selected manga chapters intended to be readable without network access, including explicit offline-cache membership, the needed **Manga Chapter Documents**, and manga image bytes.
_Avoid_: manga cache, chapter cache, transparent cache

**Manga Offline Cache State**:
The chapter-level availability of a **Manga Offline Cache** item in the manga reader cache sheet: cached, uncached, or caching. A chapter is cached only when it has offline-cache membership, its **Manga Chapter Document**, and all image bytes for that document locally available.
_Avoid_: partial cache, image cache hit, document cache hit

**Manga Offline Cache Work**:
A persisted user intent to make a manga chapter readable without network access. It remains meaningful across app launches until the chapter becomes cached, fails in the **Manga Offline Cache Queue**, the user cancels it, or the user deletes it from the **Manga Offline Cache**.
_Avoid_: download task, operation, transient queue item

**Manga Offline Cache Queue**:
The active set of **Manga Offline Cache Work** shown to the user while chapters are being made available for offline reading.
_Avoid_: download list, task manager, temporary progress sheet

**Manga Offline Cache Progress**:
The chapter-level completion of **Manga Offline Cache Work**, measured by completed manga image count after the **Manga Chapter Document** is available.
_Avoid_: byte progress, document progress, network progress

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
- A **Manga Offline Cache** depends on one or more **Manga Chapter Documents** and their manga image bytes being available locally.
- A **Manga Offline Cache** is managed at chapter granularity from the chapters in a **Manga Directory**.
- A chapter belongs to the **Manga Offline Cache** only through explicit offline-cache membership; transparent document or image cache hits do not by themselves create that membership.
- **Manga Offline Cache** membership is owned by a **Favorite Library** entry and chapter `tid`, with the normalized chapter URL retained as recovery and loading metadata.
- When cached work has a chapter `tid`, the `tid` remains authoritative and a stale chapter URL may be rebuilt or normalized before treating the work as failed.
- **Manga Offline Cache** image bytes are user-retained offline content and are not governed by the transparent image byte cache's reclaim policy.
- A completed **Manga Offline Cache** preserves the cached **Manga Chapter Document** and image URL set as the offline-readable version; later remote chapter changes do not automatically invalidate that membership.
- A **Manga Offline Cache State** is chapter-level; the first version does not expose a partial-cache state.
- A **Manga Offline Cache State** of caching means there is **Manga Offline Cache Work** for that chapter, including work recovered after an app restart.
- A **Manga Offline Cache Queue** groups **Manga Offline Cache Work** by the owning **Favorite Library** entry when presented outside the manga reader.
- A **Manga Offline Cache Queue** group uses the owning **Favorite Library** entry identity, while keeping the favorite's canonical thread URL and display title as recovery metadata.
- A manga chapter can enter the **Manga Offline Cache Queue** only through an owning **Favorite Library** entry; non-favorite manga must be added to the **Favorite Library** first.
- System storage management clears **Manga Offline Cache** content by owning **Favorite Library** entry rather than by individual chapter.
- Clearing **Manga Offline Cache** content for a **Favorite Library** entry removes that entry's completed memberships, unfinished or failed work, and offline image bytes, while reusable transparent manga caches may remain available.
- Adding a chapter to the **Manga Offline Cache Queue** is idempotent; existing cached or caching chapters are not duplicated or reordered.
- Adding a chapter from the manga reader cache sheet does not retry failed work; failed work resumes only through continuing the **Manga Offline Cache Queue**.
- **Manga Offline Cache Work** executes in the order it was added; queue groups are ordered by their earliest unfinished work, while chapters inside a group follow **Manga Directory** order.
- The first-version **Manga Offline Cache Queue** does not support user-driven reordering.
- Removing the owning **Favorite Library** entry cancels its **Manga Offline Cache Work** and deletes its cached chapter membership and image bytes.
- Canceling **Manga Offline Cache Work** stops that chapter from becoming cached and removes locally stored image bytes for that chapter, while reusable **Manga Directory** and **Manga Chapter Document** data may remain available.
- Canceling a **Manga Offline Cache Queue** group cancels that group's unfinished or failed work without deleting already completed cached chapters that have left the queue.
- Deleting a cached chapter from the **Manga Offline Cache** removes its offline-cache membership and locally stored image bytes, while reusable **Manga Directory** and **Manga Chapter Document** data may remain available.
- Deleting a chapter from the **Manga Offline Cache** also cancels any unfinished or failed work for that same chapter so the queue cannot recreate the deleted membership.
- Deleting **Manga Offline Cache** membership preserves image bytes still required by remaining offline-cache memberships, including when multiple memberships are deleted together.
- **Manga Offline Cache** storage has no first-version size limit, but its disk usage is visible to the user.
- A cached chapter can be read offline without a local **Manga Directory**, but adjacent reading, directory display, and reader cache management depend on the relevant **Manga Directory**.
- **Manga Offline Cache Progress** counts cached images within a chapter; loading or reusing the **Manga Chapter Document** is preparation for that count rather than part of the percentage.
- Failed **Manga Offline Cache Work** remains in the **Manga Offline Cache Queue** until the user continues it, cancels it, or deletes it; the manga reader cache sheet does not expose a separate failed state.
- Failed **Manga Offline Cache Work** appears as caching in the manga reader cache sheet because it still represents outstanding user intent in the **Manga Offline Cache Queue**.
- The **Manga Offline Cache Queue** downloads one chapter at a time, while the active chapter may download multiple images concurrently.
- Pausing the **Manga Offline Cache Queue** cancels in-flight image downloads and preserves completed image progress for later continuation.
- Pause and continue are **Manga Offline Cache Queue**-level controls; individual chapter and group actions cancel work rather than pausing it independently.
- A recovered **Manga Offline Cache Queue** is paused after app restart until the user explicitly continues it.
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
