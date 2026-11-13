# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`docs/decisions/`**: read decision records that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `mattpocock-skills:domain-modeling` skill (also used by `mattpocock-skills:grilling` and `mattpocock-skills:codebase-design`) creates them lazily when terms or decisions actually get resolved.

## File structure

This repo is single-context:

```text
/
├── CONTEXT.md
├── docs/decisions/
│   ├── 0001-identities-spread-second-hand-first-hand-wins.md
│   └── 0002-sync-by-whisper-with-digests.md
└── src/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts an existing decision record, surface it explicitly rather than silently overriding:

> _Contradicts decision 0001 (identities spread second-hand), but worth reopening because…_
