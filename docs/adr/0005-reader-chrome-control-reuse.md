# Reader Chrome Control Reuse

Status: accepted

Reuse reader chrome at the **Reader Chrome Control** level rather than by sharing a whole top or bottom chrome layout between novel and manga readers. Shared controls preserve the novel reader's capsule and button styling, accept display values, enabled state, and action closures only, and leave novel and manga readers to arrange those controls in their own layout containers.

This keeps manga free to arrange controls for image reading while still sharing button, panel, progress, scrubber, comments, cache, and bookmark visuals. Progress controls consume neutral **Reader Chrome Progress** rather than novel surfaces or manga reading positions. First-stage manga cache and bookmark controls are visible but disabled until real behavior exists, while the comments control remains tappable and the manga reader decides whether to show real comments or an empty comments state without changing the global chapter-comments module's `nil` target semantics.

Implementation should first move and genericize the shared controls while preserving novel reader behavior, then adopt those controls from the manga reader in a separate step. Whole novel-specific layout containers stay under `NovelReader/Chrome` and should be named `NovelReaderTopChrome` and `NovelReaderBottomChrome` rather than reader-wide names.
