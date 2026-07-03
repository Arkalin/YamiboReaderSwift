# Manga reader projections derive from thread pages

Manga native reading will use author-scoped forum **Thread Page** data as the regenerable online source for chapter content, matching the source/projection split used by the novel reader. Online manga opening may use an unfiltered all-posts **Thread Page** for metadata, same-page link discovery, and author-scope discovery, but readable image pages are derived only from the author-scoped `forum_thread_pages` entry. The resulting **Manga Reader Projection** contains the chapter identity, title metadata, owner-post metadata, and ordered image references needed by the manga reader.

`manga_reader_projections` is a Transparent JSON Cache namespace under `yamibo_cache`, not a GRDB structured source table. It replaces the unpublished `manga_chapter_documents` and `manga_chapter_document_images` table model from ADR-0036 and supersedes ADR-0004's independent manga chapter document cache. Cached projections are performance artifacts: they may be reused only when validated against the corresponding **Thread Page**, and stale or incompatible projections are regenerated from source.

Manga projection identity uses the same source identity shape as novel reader projections: thread `tid`, author identity, content source, and reader page/view. The content source should remain the source descriptor such as `authorFilteredPage`; reader kind is expressed by the projection namespace and typed API rather than by inventing manga-specific source names.

New manga reader seams and domain values should use **Manga Reader Projection** naming directly. The old `MangaChapterDocument` model, store, and loader names should be removed rather than retained as compatibility wrappers or internal transition types.

`MangaReaderProjection` should remain a dedicated Swift domain type rather than sharing the novel reader's `ReaderPageDocument` shape. Manga and novel projections may share identity, fingerprint, and Transparent JSON Cache utilities, but their reader-facing document models stay separate.

Manga projection reuse must validate source **Thread Page** fingerprint, projection schema version, parser/projection version, and full source identity (`tid`, author identity, content source, and reader page/view). A projection keyed only by `tid` or cached time is not reusable.

Implementation should land the manga source/projection refactor before the unified `OfflineCacheStore` work so offline-cache design can depend on the final reader source model rather than on the removed `MangaChapterDocument` interfaces.

This removes the special Manga Chapter Document exception in ADR-0038 for new implementation work. Manga offline-cache entries still retain user-selected offline content through `OfflineCacheStore`, but their source snapshots and image assets are user-retained offline data, not the transparent `manga_reader_projections` cache.
