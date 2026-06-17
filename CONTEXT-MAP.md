# YamiboReader Context Map

YamiboReader uses multiple domain context documents. Start here, then read the context files relevant to the code or issue you are working on.

## Contexts

| Context | Path | Read when working on |
| --- | --- | --- |
| Manga Reader | `docs/contexts/manga-reader/CONTEXT.md` | Continuous manga chapter loading, manga directories, manga page position, or manga reader ambiguity. |
| Novel Reader | `docs/contexts/novel-reader/CONTEXT.md` | Native novel reading, TextKit 2 layout, runtime generations, reader presentation, positions, surfaces, and SwiftUI adapters. |
| Library and Account | `docs/contexts/library-account/CONTEXT.md` | Favorites, local reading metadata, WebDAV sync, Yamibo accounts, profile display, forum credit progress, security questions, or sign out. |

## ADRs

- Read `docs/adr/` for repo-wide architecture decisions when it exists.
- If a context later gains local ADRs, place them under `docs/contexts/<context>/docs/adr/` and read them with that context.

## Producer Rule

When adding new domain language, update the smallest relevant context file. If a term crosses contexts, define it once in the owning context and reference it by name elsewhere.
