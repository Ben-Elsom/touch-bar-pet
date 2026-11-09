# Cat app plan

Agreed with Ben on 2026-11-09. Built, apart from what "Where the code stands" lists. Free tools only (Xcode Command Line Tools).

## The cat

The cat runs on its own, so it works with Claude closed. Most urgent state wins.

| State | When | Cat | Tap |
|---|---|---|---|
| Blocked | A live permission or question | Paws, persistent yellow note | Opens the app |
| Needs you | Anything else in Needs your input | Sits, persistent white note | Opens the app |
| Running | A chat is working, nothing needs you | Walks, as it does today | Opens the app |
| Contented (new) | Claude open, nothing needs you, nothing running | Closed-eye, blushing sit | Opens the app |
| Asleep | Contented for 30 seconds, or Claude app closed | Sleeps | Opens the app |

- Tapping the note does the same as tapping the cat. Better Narrator's copy of the cat behaves the same, so its copy of `Shared/CatMirrorView.swift` needs updating.
- Notes: yellow for a live permission or question ("Fix login bug needs access"), white otherwise ("Fix login bug needs you"), "3 Claudes need you" for several.
- Notes name the chat, using its `title` from the session files, not the project folder (Ben's request, 2026-11-09). Long titles are shortened to fit the bar. If a session has no title yet, fall back to the folder name.
- Awaiting next step never makes the cat nag.
- No petting, purring or belly rub: Ben dropped them on 2026-11-09. Tapping only ever opens the app.

## The app

A normal Mac window, part of Touch_Bar_Pet.app, with its own icon in Applications.

Sections:
1. **Needs your input:** a live permission or question, `needs_action` in Claude's summary, or the last turn ended by asking something (including optional offers: Ben wants to be nagged).
2. **Currently running:** mid-turn.
3. **Awaiting next step:** finished, nothing needed, not archived.

Each row: session title, how long it's been waiting, one line on what it wants, a link to the chat, an archive button and a checkbox. Rows in section 1 can also be moved to section 3 by hand.

Archiving:
- Never automatic.
- Per row, or tick several and press "Archive selected".
- Awaiting next step has an "Archive all" button, and a shortcut that ticks everything older than 7 days since last activity.
- Always confirm first, with the count. The confirmation warns about uncommitted changes (`git status`, only at that moment) and unfinished to-do items, then asks whether to archive anyway.
- A "Recently archived" list can restore a session.
- Refusals (session open on screen or still working) are shown on the row. An on-screen session finishes archiving once Ben moves away from it.

## Where the data comes from

- `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json`, read-only, watched for changes rather than polled: `title`, `isArchived`, `lastActivityAt`, `cliSessionId` (matches the hooks' `session_id`), `postTurnSummary`.
- Hooks, for live state, plus `mcp__ccd_turn__wrap_up`'s `ask` and `update_plan`'s items.
- Chat links: `claude://claude.ai/epitaxy/<sessionId>`.
- These files are private to Claude and an update could change them. If they do, fall back to moving sessions by hand.

## Archive helper

Only tools inside a Claude session can archive, so a small mod calls `archive_session` for the app. Reuse `~/.claude/my_mods/mods/session-watch`, with no polling and no panel. It needs a live chat process; without one the app says so.

## Security rules

- No network port, no server, no account or token storage.
- Archive requests never use distributed notifications: any local app can post those. They go in a request file only Ben's user can read or write, and the helper accepts only well-formed `local_<uuid>` IDs and logs every archive.
- Titles and summaries are shown as plain text and never run. Links are built from validated IDs, never taken from text.
- Permission one-liners are shortened and kept in memory only, because commands can contain secrets.
- Known limit: other software already running as Ben could forge requests, but it could also read and change Claude's files directly.

## Where the code stands

Ask Ben before committing. What's there now: blocked paws, finished sits with a note, working walks, no chats sleeps; no sound; `petsay --demo`, `--status` and `--clear`.

Done, installed and uncommitted:

- `Sources/ClaudeChats.swift` reads the session files. Notes use chat titles and always keep "needs you" when shortened. A chat the Claude app lists clears only when archived; sessions it doesn't list (`claude` in a terminal) still clear when their process exits.
- Chats sort into the three sections, and only Needs your input makes the cat nag. Contented and Asleep work. Tapping the cat or its note always opens the window.
- `Sources/AppWindow.swift` and the app icon (`Tools/make_icon.swift`). Rows show title, time, what the chat wants, Open, Move to Awaiting / Move back, and Archive….
- Because of check 2, Archive… warns about uncommitted files and opens the chat for Ben to archive. So there are no checkboxes, "Archive all", 7-day shortcut, to-do warnings or restore button; Recently archived only opens the chat.

To do later:


Always-visible cat (Ben's request, 2026-11-09): solved with `Helper/`. The Touch Bar blanks about 75 seconds after real input, confirmed by Ben's own eyes with the Mac unlocked and Amphetamine on, and everything short of a real HID device failed: `DFRBrightnessClient` calls, `IOPMAssertionDeclareUserActivity`, `caffeinate -u`, posted `CGEvent`s, `DFRFoundationPostEventWithMouseActivity`, and `IOHIDUserDeviceCreateWithProperties` (needs a restricted entitlement). Karabiner's virtual mouse worked: a one-pixel nudge every 30 seconds kept the capture showing content and the bar at step 1 for 6.5 minutes. `touchbar_nudge` does that only while an Amphetamine assertion holds the display and idle is 30+ seconds. The window's Always-On Touch Bar switch creates or removes `always_on_off` in Application Support; on is the default, and the helper only checks that the file exists. Karabiner is separate software, so if this breaks, suspect it first: the bottom of `README.md` has how to diagnose and update it. Installing needs Ben's password, and auto mode blocks starting the installer, so give Ben the command to run. Driver and client headers are pinned to 8.7.0: the daemon rejects other client protocol versions, so updating the driver means updating `TAG` and `COMMIT` in `Helper/build_helper.sh`.

Still to verify, all needing Ben: a real finger on the bar, notes on the real bar (Better Narrator's bar covers it), actually quitting Claude, and the permanent helper over a few hours, including after a reboot. Ben allowed the macOS screen-recording prompt on 2026-11-09, so `screencapture` is fine.

## Build order

Tell Ben if something needs a purchase (nothing should). Work in `Touch_Bar_Pet`; do the "Check first" list before relying on archiving.

1. Do the three checks below on a throwaway session.
2. Read the session files and sort sessions into the three sections. Use chat titles in the cat's notes.
3. Update the cat: Contented and Asleep states, tap opens the app.
4. Dropped: belly rub frames.
5. Build the window and app icon: sections, rows, links, moving a session by hand.
6. Build the archive helper and archiving: checkboxes, confirm with the count, warnings, Recently archived.
7. Tell the Better Narrator session (`🟩 Better Narrator app`, it may have been renamed) that `Shared/CatMirrorView.swift` changed, and what to copy. Don't edit that repo directly.
8. Test each state and each button on the real bar and window, using `screencapture -b -x` for the Touch Bar, and say plainly what couldn't be tested (a physical finger, for instance).
9. Update the README, then do the last step below.

## Check first, on a throwaway session

1. A link opens the right chat from outside Claude.
2. The mod can call `archive_session`, and whether Claude asks for approval.
3. What happens when archiving a session that's open on screen.

If 2 fails, the app opens the chat instead and Ben archives it in Claude.

Results, 2026-11-09:

1. Passed. `open claude://claude.ai/epitaxy/<sessionId>` opened the right chat (its `lastFocusedAt` updated).
2. Failed in auto mode. The mod reached `archive_session`, but `$.mcp.call` was refused twice: "The server-side auto mode classifier gave no verdict". Other permission modes weren't tested. So the app opens the chat and Ben archives it in Claude, and the archive helper isn't built unless this changes.
3. Called from a chat in auto mode, archiving a session just opened by link went through without a refusal. `unarchive_session` restored it. Whether it was still on screen wasn't confirmed.

## Last step

Done 2026-11-09. No instruction creates the 🟩/🟥 title markers any more; the two open chats that still had one were renamed, and archived chats keep theirs. The app still strips them from titles it shows.
