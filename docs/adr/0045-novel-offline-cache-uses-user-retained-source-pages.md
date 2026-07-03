# Novel offline cache uses user-retained source pages

Novel reader cache management now distinguishes transparent online caches from user-retained offline content. ADR-0017 still applies to regenerable online reading inputs: **Novel Reader Projection** remains a derived performance cache and transparent author-scoped **Thread Page** entries remain governed by the Transparent JSON Cache. For offline semantics, YamiboReader will introduce **Novel Offline Cache** entries that persist author-scoped **Thread Page** snapshots as **Novel Offline Source Pages** outside the transparent cache lifecycle.

The reader may automatically fall back to a matching **Novel Offline Cache** entry when online content acquisition fails, but fallback must be visible as stale offline content and must not hide parser, author-scope, projection-schema, or empty-content errors. Novel cache sheet actions enqueue persistent offline-cache work instead of running only as transient reader progress, and novel work appears in the shared **Download Queue** alongside manga offline-cache work.

Novel offline image caching and novel offline auto refresh are setting-controlled extensions of this model. Image acquisition is optional and must not block readable source-page updates or offline text fallback. Auto refresh updates only existing offline entries when an ordinary online read successfully loads a cached view; it must not silently create new offline entries.

Because this offline-cache product surface has not shipped, the implementation may replace the current manga offline-cache table shape while introducing the novel offline cache. It does not need to preserve, migrate, or remain compatible with the existing unpublished offline-cache tables; the new schema should be designed directly around the final manga and novel offline-cache model.

The new persistence model should use a shared offline-cache work shell for the **Download Queue** while keeping reader-specific offline entries and payloads in reader-owned tables or payload records. Shared work fields include work identity, reader kind, owner/item grouping keys, queue state, failure, insertion order, timestamps, and progress summary. Manga and novel entries keep their own source documents, image assets, and reader-specific identity fields instead of forcing every field into one nullable queue table or preserving two unrelated queue systems.

The implementation should expose this persistence through one generic `OfflineCacheStore` service rather than separate manga and novel offline-cache stores plus a shallow shared facade. The store owns shared queue state, shared work rows, shared image assets, and reader-specific offline entry payloads behind typed APIs for manga and novel behavior.

`OfflineCacheStore` should use strong typed columns for shared identity, grouping, state, update time, byte counts, progress summaries, and UI projection fields, with payload JSON or reader-specific files only for complex data that is not needed for queue listing, cache sheets, cleanup, or sorting.

The public API should keep typed reader operations on top of the generic store: manga and novel callers enqueue, query, delete, and load through reader-specific methods, while the shared **Download Queue** consumes generic queue projections. Reader code should not parse generic payloads or switch over unrelated reader kinds for normal cache operations.

The implementation should replace the old manga offline-cache protocol surface rather than preserving compatibility adapters with the old protocol names. Manga and novel call sites should move directly to the new `OfflineCacheStore` typed API.

Offline-cache retained files should live under a unified offline-cache directory rather than manga-specific legacy paths. Shared image files and reader-specific JSON bodies should be organized under clear subdirectories such as images, novel source pages, and novel projections.

System settings should expose user-retained offline content through unified offline-cache management and total offline-cache usage across manga and novel. Transparent cache cleanup remains separate from user-retained offline-cache deletion.

Application data reset clears the entire `OfflineCacheStore`: shared work rows, global run state, manga and novel offline entries, reader-specific references, shared image assets, retained source/projection files, and any queued progress metadata.

Shared offline-cache work uses an explicit lifecycle: queued, running, paused, or failed. Successful completion removes the work row and leaves the reader-specific offline entry as the durable cached content; the **Download Queue** is not a download-history table.

The **Download Queue** also keeps a global run state that records whether the user has allowed queue execution to continue. The global run state controls scheduling, while each work row records its own lifecycle. After app restart or execution recovery, the queue is restored as paused and any previously running work is no longer treated as actively running until the user continues the queue.

Shared work rows use a generated stable work id as their primary key for queue UI selection and row commands, while reader-specific natural identity is protected by a uniqueness constraint for idempotent enqueue behavior.

Offline image bytes should use a shared image asset index so identical remote image URLs map to one retained file record across manga and novel offline caches. Reader-specific tables still own the relationships from manga chapters or novel source pages to image assets, including order, requirement, and progress semantics.

Shared offline image assets use a canonical image URL hash as the storage key and file-name basis, while retaining the canonical and original URL strings for diagnostics and reacquisition. Canonicalization must avoid merging URLs that can represent different authenticated, transformed, or sized image bytes.
Deleting offline-cache entries or work removes only their reader-specific references to shared image assets. The retained image file and shared asset row are deleted only when no remaining manga or novel entry/work references them.

Novel offline source-page and projection JSON bodies should live in the file system, with GRDB storing identity, filenames, schema or fingerprint metadata, byte counts, update time, and queue relationships. Replacing a source page must be atomic from the reader's perspective: a failed refresh cannot remove the previously durable offline source page.

Novel offline entry metadata may store presentation snapshots such as thread title, author display name, forum label, and max view for cache sheets and queue rows, but those fields do not participate in identity. Title or display metadata changes must update presentation without creating a different offline entry.

When novel offline auto refresh has already obtained a fresh source page through ordinary online reading, replacing the offline source page is a direct persistence update rather than visible **Download Queue** work. Optional image-asset acquisition after that replacement may use queue work without blocking the reader.

The new system settings are scoped to novel offline caching: novel offline image caching defaults off, while novel offline auto refresh defaults on. This keeps initial disk and network usage conservative for novel images while keeping already user-selected novel offline entries fresh after successful online reads. Manga offline image caching remains part of manga cache completion, and manga offline auto refresh is not introduced by this decision.

Novel fallback intentionally differs from manga fallback: novel fallback must visibly indicate stale offline content, while manga fallback may open cached image pages without an offline-version notice.
