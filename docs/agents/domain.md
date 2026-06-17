# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT-MAP.md`** at the repo root. It points at the repo's per-context `CONTEXT.md` files.
- **The relevant context files** listed in `CONTEXT-MAP.md`. Read only the contexts that touch the area you're about to work in.
- **`docs/adr/`** -- read ADRs that touch the area you're about to work in. If a context later has local ADRs, also check `docs/contexts/<context>/docs/adr/`.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The producer skill (`/grill-with-docs`) creates them lazily when terms or decisions actually get resolved.

## File structure

This repo uses a multi-context layout:

```
/
|-- CONTEXT-MAP.md
|-- CONTEXT.md
|-- docs/adr/
`-- docs/contexts/
    |-- manga-reader/
    |   `-- CONTEXT.md
    |-- novel-reader/
    |   `-- CONTEXT.md
    `-- library-account/
        `-- CONTEXT.md
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the relevant context file from `CONTEXT-MAP.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal -- either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) -- but worth reopening because..._
