# Manga Paged Reader Behavior

Status: accepted

Stage 10 makes **Manga Reading Mode** real behavior rather than settings-only presentation: vertical mode keeps the existing continuous collection viewport, while paged mode supports slide, quick fade, and page curl on iOS. Paged manga uses manga-specific viewports and may extract small neutral paging tools under `Sources/YamiboReaderUI/Features/Reader/Shared`, but it must not depend on `NovelReaderSurface`, novel text display adapters, or whole novel viewport containers.

**Manga Page Turn Direction** changes horizontal navigation, two-page visual ordering, page-curl before/after mapping, and the paged horizontal directory progress fill direction, but it does not reorder underlying page projections or reverse `localIndex`. **Manga Page Spread** is a viewport display group; comments, resume, adjacent prefetch, scrubber targets, and progress writes remain page-level **Manga Reading Position** behavior. Page-curl manga uses the novel-reader-consistent book-spine/double-sided model, with required blank page surfaces not creating reading positions.

**Manga Page Scale Mode** applies to the complete page surface: fit-width pages include top and bottom blank space in the surface that turns, and fit-height pages either include left/right blank space or allow horizontal overflow panning with initial alignment following **Manga Page Turn Direction**. **Manga Page Zoom** is a single-page interaction enabled only while reader chrome is hidden; zoom state is not persisted and does not affect reading position.
