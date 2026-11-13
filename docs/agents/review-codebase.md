# Rechecking the whole codebase

Reach for this when auditing, security-checking or reviewing the whole of `main`: after a stack merges, before a release, or on a schedule. A single pull request has its own, smaller loop in [review-pr.md](review-pr.md).

1. **Orient.** Pull `main` in the main checkout and let the post-merge hook rebuild the graph (do not run `graphify update` yourself); run `graphify update .` once in the main checkout only when `graphify-out/` is missing. The readers then see the code as merged.
2. **Read in parallel.** Start one read-only agent per lens: `security-review`, `ponytail:ponytail-audit`, `code-review` (correctness) and `mattpocock-skills:code-review` (Standards axis, no spec). Add `mattpocock-skills:codebase-design` as a fifth reader for module depth. Hand each the list of what earlier rounds fixed and the decisions kept on purpose (`ponytail:ponytail-debt` lists every `shortcut:` comment), so findings do not come back. Brief each reader to start from graphify in the main checkout and to end its report with the graphify commands it ran; a report with none goes back to be redone. Say in the brief that the agent changes nothing: no git writes.
3. **Verify first.** A finding is verified when a failing test, a measurement, a debug log line or the code beside Blizzard's UI source shows it. Check the findings yourself or give each to an agent whose first job is to prove or refute it. A finding that claims a bug or a red CI run goes through `mattpocock-skills:diagnosing-bugs` (a red loop you can run) or, when the cause is unclear or intermittent, `caveman:investigate-first`. A claim about the WoW API or a tool is checked against its primary sources with `mattpocock-skills:research`. A refuted finding gets a one-line reason and no change.
4. **Fix the verified ones**, one agent per finding, each in its own worktree from `origin/main` (see [AGENTS.md](../../AGENTS.md)), red test first (`mattpocock-skills:tdd`). Pick the fix skill by kind: `caveman:surgical-patch` for a bug, `caveman:safe-refactor` for a restructure that keeps behavior (the test count stays the same), `caveman:migration` for a protocol or saved-variables change, `caveman:lean-build` for new behavior. An agent that cannot verify its finding changes nothing and reports the evidence.
5. **Stack and gate.** Stack the branches as AGENTS.md says, then run every gate on the top: busted, luacheck, StyLua, the `package` build and `pre-commit` read to the end. `caveman:verify-and-stop` runs these and stops at the result.
6. **Merge, pull, go again.** The loop is done when a round yields no verified finding.

## What each lens is for

- `ponytail:ponytail-audit` finds the most real defects: what breaks under load (a guild of hundreds, a memory at the cap), missing tests, steps in the docs that would not work.
- `security-review` is most useful on what peers send: malformed or hostile addon messages, forged first-hand claims, floods. Read its below-threshold list as well as its findings.
- `code-review` finds correctness bugs in a diff and is noisy over a whole repository. Expect about half of its findings to need refuting.
- `mattpocock-skills:codebase-design` finds shallow modules and grab-bag files; no other reader checks module depth.
- `mattpocock-skills:code-review` holds the code to this repository's written standards (the glossary's words, the injected clock, test names).
- `simplify` and `ponytail:ponytail-review` are worth running on a diff before its pull request opens.

## What went wrong, and the habit that prevents it

- An agent's report can be empty or claim more than it did. Read its branch and its diff, not its summary.
- Agents can lose each other's work through `git stash`, which every worktree shares. Set work aside with a WIP commit or `git diff > file`, and commit on a named branch, never on a detached `HEAD`.
- A test written after its fix proves little. Say in the report when the red run was skipped.
