# The WoW Forever API

Reach for this when a change calls the game, sends or reads addon messages, or touches the saved variables. Why Forever only: [decision 0006](../decisions/0006-forever-only-with-a-plain-toc.md).

## The client

- WoW Forever, client 1.60.1, `## Interface: 16001`, `WOW_PROJECT_ID` 18 (`WOW_PROJECT_CAMELOT`, reported). Its addon API is the Mainline family (Retail 12.x), not Classic Era. Blizzard's UI source for Forever is the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever): read it before trusting a wiki page.
- Lua 5.1: no `goto`, no `//`, no bitwise operators (use `bit`), no `require`, `dofile`, `loadfile`, `io` or `os`. Files share state through the addon namespace: every file starts with `local addonName, ns = ...`.
- Most facts below come from community sources in November 2026. When one turns out wrong in the game, fix this page in the same pull request.

## Names

- A character's full name is `First Last`, unique in the region; there are no realms ([decision 0003](../decisions/0003-the-full-name-is-the-key.md)). On Forever, `UnitName` returns `name, surname`: the second value is the surname, not the realm, whatever the generated docs call it. `GetUnitName(unit)` returns `"First Last"`: on Forever it is `NameUtil.FormatUnitNameForDisplay(unit)` (`Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`), which joins `UnitName`'s two values with the client's separator and ignores a second argument.
- The `sender` of `CHAT_MSG_ADDON` is `"First Last"`, with no realm suffix (Questie, APR). Whispers accept `"First Last"` and `"First-Last"`.
- "My Secondary Name" hides the surname in the world, not in chat: a tooltip can give only a first name. Map it through the GUID learned from chat lines and group members, never through the first name alone.

## Chat

Read in Blizzard's UI source for build 1.60.1.70938 (`Blizzard_ChatFrameBase`):

- **The name hook** is `ChatFrameUtil.AddSenderNameFilter(callback)`. The default chat frames call it for every `CHAT_MSG_*` line they show, Communities channels included, as `callback(event, decoratedName, text, sender, ...)` with the event's payload after `decoratedName`. `decoratedName` is the sender's name as it will show, class color included; it goes inside the player link's `[...]`, so a suffix reads `[Hugh Jass (Tony)]`. Return the new name, or nil to leave it. The callback is skipped when `decoratedName` is secret, but the other arguments can still be.
- **The message filters** are `ChatFrameUtil.AddMessageEventFilter(event, callback)`; `ChatFrame_AddMessageEventFilter` is its deprecated alias. A filter runs only when every argument is readable, and can rewrite the text or drop the line, not the name.
- **The payload** of `CHAT_MSG_*`: the sender is the 2nd value, the sender's GUID the 12th. Both can be secret: the events are `SecretInChatMessagingLockdown`. In `CHAT_MSG_WHISPER_INFORM` the 2nd value is the recipient.
- **Hovering a link** in a chat frame triggers `EventRegistry` callbacks, `"ChatFrame.OnHyperlinkEnter"` `(owner, chatFrame, link, text, ...)` and `"ChatFrame.OnHyperlinkLeave"`. A character's link is `player:First Last:lineID:chatType:target`, or `playerCommunity:First Last:clubId:streamId:epoch:position` in a Communities channel.
- **The Communities window** formats its own lines (`CommunitiesChatMixin:FormatMessage`) and calls neither filter: only a Communities channel shown in a chat frame goes through the name hook.
- **The Communities window's hook** (`Blizzard_Communities`, load on demand, the frame is `CommunitiesFrame.Chat`): it offers no filter, so post-hook its methods with `hooksecurefunc` and rewrite the stored line through its `ScrollingMessageFrame`'s `TransformMessages(predicate, transform)`, the call it uses itself to update an edited message. `Chat:AddMessage(clubId, streamId, message, backfill)` adds each line (`DisplayChat` and `BackfillMessages` add up to 100 at once, and the window keeps up to 5000); `Chat:RefreshMessages(predicate)` reformats lines after an edit or when an author's name arrives. A stored line is `text, r, g, b, clubId, streamId, messageId, memberId`; its text is `[|HplayerCommunity:First Last:clubId:streamId:epoch:position|hshown name|h]: message` (`GetPlayerCommunityLink`, class color inside the link's text, a timestamp or a Discord icon before it), and `BNplayerCommunity` for a Battle.net author. `TransformMessages` walks every stored line, so batch the lines added together into one pass.

## Rules

- **Keep the WoW API in the adapters**, `Client` and `Interface`. `Memory`, `Self`, `Protocol` and `Sync` are pure: they take the clock and their saved tables as arguments, so the tests run them outside the game ([testing.md](testing.md), [decision 0004](../decisions/0004-a-pure-core-two-adapters-no-libraries.md)).
- **Declare every WoW global in `.luacheckrc`.** An undeclared global fails luacheck: a typo, or an API missing on Forever.
- **Use the namespaced APIs.** Missing on Forever (reported): `GetSpellInfo`, `GetItemInfo` (use `C_Spell.GetSpellInfo`, which returns a table, and `C_Item.GetItemInfo`), `GetSpellBookItemName`, the talent and skill-line globals, `CombatLogGetCurrentEventInfo`.
- **Expect secret values.** Unit names, GUIDs and chat lines can be secret (unreadable by addon code) during combat and chat lockdown. Check every value read from a unit or an event with `issecretvalue` and treat a secret as unknown; comparing or concatenating one raises an error. A chat line that is secret shows without a nickname.
- **Treat addon messages as untrusted input.** Anyone can send on the `Mnemosyne` prefix. Read them only through `Protocol`, which drops what does not parse, other versions and oversized fields; never run received text as code; store a first-hand identity only under the sender the server gives, never under a name in the message; refuse `|` (the client's escape character: colors, textures, links), control characters and invalid UTF-8 in a nickname, and more than 32 characters, counted as UTF-8 characters, not bytes; respect the per-peer limits ([decision 0001](../decisions/0001-identities-spread-second-hand-first-hand-wins.md)).
- **Respect the message limits.** A message is 255 bytes at most, the prefix 16 characters. Each prefix has 10 messages, refilled at 1 per second, except whispers outside instances. Check `C_ChatInfo.SendAddonMessage`'s result (`AddonMessageThrottle`, `ChannelThrottle`, `AddOnMessageLockdown`, `TargetOffline`). Everything goes through the paced queue of `Client` ([decision 0002](../decisions/0002-sync-by-whisper-with-digests.md)).
- **Nothing goes out during lockdown.** Addon messages are blocked during Mythic+ runs, PvP matches and boss encounters: check `C_ChatInfo.InChatMessagingLockdown()` before sending (`ADDON_RESTRICTION_STATE_CHANGED` fires as a restriction starts and ends). `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` is not lockdown: it is set realm by realm and, when true, nothing can ever be sent there. Trial accounts cannot send addon messages at all (`IsTrialAccount() or IsVeteranTrialAccount()`, what Blizzard's `GameLimitedMode_IsActive` checks).
- **Saved variables may not come back.** Some Forever builds wrote saved variables without restoring them. Initialize every field on `ADDON_LOADED` (`db.x = db.x or {}`), carry a schema version, and never assume what an earlier session saved is there.
- **Every player-facing string goes through the locale table.** enUS is the base locale: write each string in enUS in the table as you add it, never inline in code. frFR is a translation of it; a string missing from a translation falls back to enUS. Pick the locale with `GetLocale()`.
- **No network, no files, no clipboard, no browser.** The only ways out of the game are the saved variables and a text box the player copies from. `/mnemosyne report` (and the popup after a caught Lua error) shows a link to the bug report form pre-filled through its query parameters, which are the field `id`s of `.github/ISSUE_TEMPLATE/bug_report.yml` (`report`, `version`): renaming a field there breaks the link. Keep the link to a few KB, and fall back to the full text for Ctrl+C. Never put other players' names or nicknames in a report: label them per report (`peer1`, `peer2`...). A short hash of a name, even salted, can be matched against a guild roster.

## Check in the game

Open, to settle in the game and record here:

- the suffix the client reads for a flavor .toc (`_Camelot` or `_Forever`; the plain file works either way);
- whether `UnitName` ever returns the joined `"First Last"` as its first value;
- whether `TooltipDataProcessor` and `Enum.TooltipDataType.Unit` behave as on Mainline;
- how fast addon whispers really go before the server throttles them;
- whether a chat line's sender is `"First Last"`, as the sender of an addon message is;
- whether `UnitNameUnmodified` gives the surname of a group member who hides it;
- whether the Communities window shows the nickname on new lines, on a page of history and on an edited message, and whether a message's author name is `"First Last"`;
- whether EllesmereUI: Standalone Chat calls the sender name filters and the hyperlink callbacks.
- whether `UnitName` gives no surname for a character that hides it ("My Secondary Name"): asking a stranger relies on it to never whisper a first name alone;
- whether addon whispers reach a character of the other faction (asking a stranger skips them, by `UnitFactionGroup`).
- whether an error message names its file as `Interface/AddOns/Mnemosyne/...` (Mnemosyne's handler, `seterrorhandler` chained to the previous one, keys on it). With !BugGrabber loaded the handler is never set: BugGrabber replaces `seterrorhandler` with a no-op, and its own callback needs CallbackHandler;
- whether `BasicFrameTemplateWithInset`, `InputBoxTemplate` and `UIPanelScrollFrameTemplate` exist on Forever, for the report window.

`/dump select(4, GetBuildInfo())` prints the Interface number; `/dump WOW_PROJECT_ID` the project.
