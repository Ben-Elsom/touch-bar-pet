# Cat app plan

Agreed with Ben on 2026-11-09. Not built yet. Free tools only (Xcode Command Line Tools).

## The cat

The cat runs on its own, so it works with Claude closed. Most urgent state wins.

| State | When | Cat | Tap |
|---|---|---|---|
| Blocked | A live permission or question | Paws, persistent yellow note | Opens the app |
| Needs you | Anything else in Needs your input | Sits, persistent white note | Opens the app |
| Running | A chat is working, nothing needs you | Walks, as it does today | Opens the app |
| Contented (new) | Claude open, nothing needs you, nothing running | Closed-eye, blushing sit | Rolls over, makes biscuits |
| Asleep | Contented for 5 minutes, or Claude app closed | Sleeps | Wakes, rolls over, makes biscuits |

- Tapping the note does the same as tapping the cat. Better Narrator's copy of the cat behaves the same, so its copy of `Shared/CatMirrorView.swift` needs updating.
- Notes: yellow for a live permission or question ("Combo Caller needs access"), white otherwise ("Combo Caller needs you"), "3 Claudes need you" for several.
- Awaiting next step never makes the cat nag.
- Belly rub art doesn't exist in the sprite. Draw about 8 frames in the same style, preview them large with Ben first, and reuse the hearts. If they aren't good enough, look for a free sprite.

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

The cat's current changes are installed but uncommitted (`git status` in this repo). Ben hasn't asked for a commit, so ask before committing. What's there now: blocked paws, finished sits with a note, working walks, no chats sleeps; no sound; `petsay --demo`, `--status` and `--clear`.

Known problem to fix: `Sessions.tidy()` in `Sources/main.swift` clears a session when its process stops, but most open sessions have no process, so quitting Claude wipes the notes. Use `isArchived` from the session files instead. Nothing clears a note by process any more.

## Build order

Tell Ben if something needs a purchase (nothing should). Work in `Touch_Bar_Pet`; do the "Check first" list before relying on archiving.

1. Do the three checks below on a throwaway session.
2. Read the session files and sort sessions into the three sections.
3. Update the cat: Contented and Asleep states, tap opens the app, belly rub in Contented and Asleep.
4. Draw the belly rub frames and show Ben a large preview before wiring them in.
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

## Last step

Remove the 🟩/🟥 title markers. The instruction wasn't in the main `CLAUDE.md` or memory files, so find where it lives.
