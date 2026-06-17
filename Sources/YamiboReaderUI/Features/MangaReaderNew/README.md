# MangaReaderNew

`MangaReaderNew` is the temporary phase 1 workspace for the manga reader parallel rewrite.

It is not routed in production during phase 1. `Sources/YamiboReaderUI/Features/MangaReader` remains the only production native manga reader route until parity tests pass and a single cutover change is made.

## Presentation

SwiftUI-facing reader adapter and immutable presentation snapshots.

Target ownership:

- `MangaReaderView`
- `MangaReaderModel` as an adapter over Core Application workflows
- `MangaReaderPresentation`
- page projection values for image rendering, progress, comments, and navigation

The future model should publish one core presentation snapshot plus minimal UI-only transient state.

## Chrome

Reader chrome controls and command surfaces.

Target ownership:

- navigation buttons
- progress controls
- top/bottom bars
- transient reader command UI

## Directory

SwiftUI surfaces for **Manga Directory** display and edits.

Target ownership:

- directory sheet
- directory management controls
- rename/search keyword draft state

Directory update behavior itself belongs in Core Application.

## Settings

SwiftUI settings sheet and draft state.

Target ownership:

- settings draft UI
- presentation-only controls
- adapter calls to committed settings workflow

Persisted settings representation and successful commit coordination belong outside the sheet.

## WebFallback

WebKit-specific fallback and probe adapters.

Target ownership:

- `MangaWebFallbackView`
- `MangaProbeService`
- WebKit JavaScript extraction
- hidden probe web view handling

Core may own pure probe decisions and recovery policy, but this directory owns `WKWebView` usage.

## Cutover Policy

Do not wire this directory into `RootTabView` during phase 1.

After parity tests pass, perform one explicit cutover:

1. Rename old `MangaReader` to `MangaReaderLegacy` or delete it if rollback is not needed.
2. Rename `MangaReaderNew` to `MangaReader`.
3. Update `RootTabView` once.
4. Remove duplicate route and test references.
