# YamiboReader Context

This repository now uses multiple domain context documents. Start with `CONTEXT-MAP.md`, then read only the context files relevant to the current task.

The current contexts are:

- `docs/contexts/manga-reader/CONTEXT.md`
- `docs/contexts/novel-reader/CONTEXT.md`
- `docs/contexts/library-account/CONTEXT.md`

## Language

**Transparent Image Data Cache**:
The app-wide, regenerable local store of remote image bytes reused by reader, forum, account, and library surfaces. It is separate from decoded in-memory image caching and from user-retained offline content such as **Manga Offline Cache**, and entries may have different retention policies such as normal evictable bytes or protected avatar bytes.
_Avoid_: manga image cache, image offline cache, decoded image cache

**Reader Chrome**:
The floating reader control layer around reading content, including close, directory, source-thread, progress, settings, and related reader actions. It does not include the novel text viewport or manga image viewport.
_Avoid_: reader viewport, reader content, floating controls

**Reader Chrome Control**:
A reusable control inside **Reader Chrome**, such as a close button, directory button, progress capsule, scrubber, or source-thread action, that a reader surface can arrange for its own layout. It is smaller than the whole **Reader Chrome** layer and does not own reader-specific workflow state.
_Avoid_: whole chrome component, reader model control, viewport control

**Reader Chrome Progress**:
The reader-visible progress value consumed by **Reader Chrome Control** progress UI, expressed as position in an ordered page-like sequence with optional milestones. It is not the authoritative reading position for novel or manga readers.
_Avoid_: novel surface progress, manga reading position, reader progress snapshot
