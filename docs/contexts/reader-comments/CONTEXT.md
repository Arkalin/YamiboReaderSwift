# YamiboReader Reader Comments Context

Domain language for chapter comments shared by native manga and novel readers.

## Language

**Reader Chapter Comment Target**:
The cross-reader value that identifies the Yamibo owner post whose comments should be shown for the current reader chapter or page. It carries the thread `tid`, forum page view, owner post id, optional display title, and optional author filter needed by comment loading.
_Avoid_: novel comment target, manga comment target, post comment key

## Relationships

- Manga and novel readers both derive a **Reader Chapter Comment Target** from their current reader-visible position before opening the shared comments UI.
- `nil` **Reader Chapter Comment Target** means the current reader state does not support chapter comments and should use the shared unsupported/empty comments behavior.
- A **Reader Chapter Comment Target** is not a persisted reading position, chapter identity, or navigation anchor; it is a loading target for the shared chapter-comments module.
