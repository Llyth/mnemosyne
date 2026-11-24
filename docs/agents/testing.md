# Testing the addon

Reach for this when writing or changing a test. How to run them is in [CONTRIBUTING.md](../../CONTRIBUTING.md#tests).

Work in vertical slices, a *tracer bullet*: one behavior, one failing test (red), the smallest code that passes, repeat. Test at two seams only ([decision 0004](../decisions/0004-a-pure-core-two-adapters-no-libraries.md)):

1. **The pure modules, with busted, outside the game:** `Protocol`, `Memory`, `Self`, `Sync`, `News`, `Recognition`, `Strangers`, `Scope`, `Report`, `Outbox` and `Inbox` (`src/core/`), each through its own interface. Most behavior lives here and is tested here.
   - **The multi-peer simulation** wires several peers (`Memory`, `Self`, `Sync` and `Protocol` each) through an in-memory transport and checks how identities spread: D learns A through B and C, first-hand overrides a forged copy, an unregistration reaches everyone, a dispute settles, the per-peer limits hold.
2. **The adapters, by hand in the game:** `Client` (with `Encounter`), `Interface` (with `Chat`, `Commands`, `Prompt`, `Panel`, `Window`, `Identities` and `ReportWindow`) and `Debug` call the WoW API and have no automated test. A pull request that changes one says in its description what was checked in the game, on which build, or that it was not. Syncs need two clients (or a friend) and `/mnemosyne debug`.

- **Other UI addons.** Recognition adds the nickname only through the hooks other addons respect (the chat message filters and name hooks, `TooltipDataProcessor`) and redraws nothing itself; the Communities window offers no hook, so its stored lines are rewritten the way it rewrites an edited message ([wow-api.md](wow-api.md)). A change to chat or tooltip recognition is checked by hand with [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui) and its chat module ([EllesmereUI: Standalone Chat](https://www.curseforge.com/wow/addons/eui-chat)) as well as with the default UI. Other addons are best-effort: a breakage there is a bug report, not a release blocker.
- Keep the WoW API out of the pure modules ([wow-api.md](wow-api.md)), so a behavior can move to seam 1 instead of staying untested in seam 2.
- Do not write a fake of the WoW API to test an adapter: it would test the fake. Move the logic into a pure module instead.
- Name each test as a sentence in the words of [CONTEXT.md](../../CONTEXT.md), for example `it("lets a first-hand identity replace a second-hand one")`.
- Inject the clock: pure modules take the time as an argument and never call `time()`, `GetTime()` or `GetServerTime()`.
- Everything that arrives from another player gets a test for what is dropped, not only for what is accepted: malformed messages, other versions, escape sequences, control characters, oversized fields, more changes than a peer may send in a day.
