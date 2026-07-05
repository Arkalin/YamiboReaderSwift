## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Arkalin/YamiboReaderSwift`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a multi-context repo. Start with `CONTEXT-MAP.md`. See `docs/agents/domain.md`.

### Test guardrails

Do not write source-code assertion tests. Tests must not read or scan files under `Sources/**/*.swift` and assert on implementation text, regex matches, symbol spellings, or source layout. Test behavior through public APIs, domain models, focused fixtures, or UI contracts instead.

## Refactoring policy

Prefer clean breaks over compatibility layers.

When modifying this codebase, do not default to preserving old interfaces, old data shapes, legacy behavior, or transitional compatibility logic. Optimize for the future shape of the codebase, not for minimizing short-term change risk.

If the current interface, data model, module boundary, naming, or architecture is wrong, redesign it directly. Do not keep the old shape merely to reduce diff size or avoid touching call sites. A larger but cleaner refactor is preferred over a smaller change that preserves bad abstractions.

### Default behavior

When making code changes:

1. Prefer replacing flawed APIs instead of wrapping them.
2. Prefer updating all call sites instead of keeping compatibility overloads.
3. Prefer deleting obsolete code instead of marking it deprecated.
4. Prefer changing data models directly instead of supporting both old and new shapes.
5. Prefer one canonical implementation instead of fallback logic.
6. Prefer explicit breakage at compile time over hidden runtime compatibility.
7. Prefer simple, coherent architecture over defensive legacy support.

### Avoid unless explicitly requested

Do not introduce:

- temporary adapters
- compatibility layers
- old/new dual-path logic
- deprecated method aliases
- fallback parsing for obsolete data
- silent migrations
- redundant DTO/model copies
- optional fields only used for legacy compatibility
- branching logic such as `if oldFormat else newFormat`
- comments like "keep for backward compatibility"
- transitional APIs intended to be removed later

These patterns are only acceptable if the user explicitly asks for backward compatibility, staged migration, production-safe rollout, or old data preservation.

### Interface changes

Changing public or internal interfaces is allowed and encouraged when it improves the design.

When an interface changes:

- update all affected call sites immediately
- remove the old interface
- remove unused parameters, types, and wrappers
- rename concepts to match the new architecture
- let the compiler reveal remaining breakage
- do not preserve the old API shape as a bridge

Do not ask for permission merely because a change is breaking. Breaking changes are acceptable when they make the design cleaner.

### Data model changes

Do not preserve old data formats by default.

When a data model is wrong:

- replace it with the desired model
- update persistence, decoding, encoding, tests, and call sites accordingly
- delete obsolete model fields
- delete obsolete migration paths
- fail loudly if old data is encountered, unless compatibility was explicitly requested

Assume old local data can be discarded, reset, regenerated, or handled manually unless the user explicitly says otherwise.

### Migration policy

Do not create migrations automatically.

Only implement migrations when the user explicitly says that existing production data must be preserved. If migration is not explicitly required, prefer a clean schema or model reset over compatibility code.

### Risk philosophy

Do not optimize primarily for low-risk patches. This codebase accepts short-term breakage during refactoring in exchange for long-term maintainability.

The preferred workflow is:

1. define the correct final design
2. apply the breaking change
3. update all affected code
4. remove obsolete code
5. fix compile errors and tests
6. leave no compatibility residue

### Decision rule

When choosing between two approaches:

- choose the approach that leaves the codebase cleaner after the change
- do not choose the approach that merely minimizes the current diff
- do not keep old abstractions alive unless they still represent the correct domain model
- do not introduce code that exists only to make the transition safer

Before completing any task, check whether the change introduced unnecessary compatibility logic. If yes, remove it.

The final result should look as if the codebase had always been designed this way, not as if it is halfway through a migration.

### Exception

Backward compatibility, migrations, staged rollouts, and legacy data preservation are required only when the user explicitly asks for them. In all other cases, prefer bold destructive refactoring.
