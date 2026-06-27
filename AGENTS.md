## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Arkalin/YamiboReaderSwift`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a multi-context repo. Start with `CONTEXT-MAP.md`. See `docs/agents/domain.md`.

### Test guardrails

Do not write source-code assertion tests. Tests must not read or scan files under `Sources/**/*.swift` and assert on implementation text, regex matches, symbol spellings, or source layout. Test behavior through public APIs, domain models, focused fixtures, or UI contracts instead.
