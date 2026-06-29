# Reader navigation history ownership

Reader navigation history is session-scoped reader interaction state, not persisted reading progress or layout/runtime state. YamiboReaderCore owns a generic pure-value `ReaderNavigationHistory<Anchor>` for stack rules such as capacity and back/forward transfer, while `MangaReaderModel` and `ReaderContainerModel` own concrete history instances and decide when visible user navigation should push or restore anchors. `MangaReaderWorkflow` and `NovelReadingWorkflow` remain responsible only for resolving and jumping to semantic reading positions.
