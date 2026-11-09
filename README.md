# Touch Bar Pet

A little pixel cat that lives on the far left of the MacBook Pro Touch Bar and
shows what Claude Code is doing. Apple's Control Strip (brightness, volume and so
on) stays on the right.

The cat nags until you've dealt with everything. Walking is the reward.

| Claude is… | The cat… |
|---|---|
| blocked | paws at you, with a yellow note: "Fix login bug needs access" for a permission prompt, "Fix login bug needs help" for a question |
| waiting on you: it asked something or left you something to do | sits, with a white note: "Fix login bug needs you" |
| working, and nothing needs you | walks back and forth (hops once when you clear the last one) |
| open, nothing needs you, nothing running | sits contented, eyes closed and blushing |
| quiet for 30 seconds, or the Claude app is closed | sleeps, with little z's |

A chat that simply finished, with nothing left for you, never makes the cat nag.
Tapping the cat or its note always opens the window.

The most urgent wins, across every session: one blocked or waiting Claude outranks
any number of working ones. Several show as "3 Claudes need you". The name is the
chat's title in the Claude app, shortened if it's long, or the project folder if the
chat has no title yet.

A note stays until you answer that Claude or archive the chat. Quitting Claude doesn't
clear it, and a restart of the pet remembers who's waiting. A session the Claude app
doesn't list, such as `claude` in a terminal, clears when its process exits. One known
gap: there's no event for approving a permission, so "needs access" stays until the
approved tool finishes.

## The window

Open Touch Bar Pet from `~/Applications`, or tap the cat. Closing the window leaves the cat running.

Every open chat is listed under **Needs your input**, **Currently running** or
**Awaiting next step**, with how long it's been there, what it wants, and a button to
open it. **Move to Awaiting** quiets a chat until a later turn wants something.
**Archive…** warns about uncommitted files, then opens the chat for you to archive in
Claude: the app can't archive chats itself. The titles and statuses come from Claude's
private session files, read-only, so a Claude update could break this list.

## Staying visible while you're away

The Touch Bar normally goes dark about 75 seconds after your last input, even with
Amphetamine holding the screen on. While something is holding the display awake, the
cat keeps the bar at its dimmed level so a glance still shows whether Claude needs
you. When nothing is holding the display awake, the bar dims as usual.

```bash
defaults write com.benelsom.touchbarpet barAwayStep -int 1     # stay at normal brightness
defaults write com.benelsom.touchbarpet keepBarLit -bool false # turn this off
```

The bar is OLED, so hours at normal brightness with a note in one place risks burn-in.
This uses a private Apple API; if an update removes it, the bar just dims as usual.

## Install

```bash
./install.sh
```

This builds with the Xcode Command Line Tools (no full Xcode), puts
`Touch_Bar_Pet.app` in `~/Applications` and `petsay` in `~/.local/bin`.

Your Touch Bar needs to be set to **App Controls** with **Show Control Strip** on
(System Settings → Keyboard → Touch Bar Settings).

## Claude Code hooks

`~/.claude/settings.json` runs `petsay --hook` (async, so it never slows Claude
down) on SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse,
PostToolUseFailure, Notification, Stop, StopFailure and SessionEnd.

To see which events really arrive, create `~/Library/Logs/Touch_Bar_Pet_hooks.log`;
`petsay` appends to it only while it exists.

## petsay

```bash
petsay "Backup done" --mood done   # a short note beside the cat for a few seconds
petsay --mood working              # change what the cat is doing for a few seconds
petsay --theme ginger              # grey, ginger, cream, blue, calico
petsay --demo                      # show each state in turn, about a minute
petsay --status                    # list what the cat thinks each Claude is doing
petsay --clear                     # forget every Claude, for a note that's stuck
petsay --show                      # put the cat's bar back
petsay --quit                      # quit; Claude hooks won't relaunch it until you run petsay again
```

## Notes

- macOS puts an ⓧ to the left of the cat that can't be removed. Tapping it
  hides the cat so you can see the front app's own buttons. The cat comes back
  when Claude's state changes, or within a minute.
- Only one bar can be visible at a time, and Better Narrator's full-width bar sits
  on top of the cat's while it's up. To keep the cat visible during a reading,
  Better Narrator hosts `Shared/CatMirrorView.swift`, a small copy of the cat that
  follows the state the pet broadcasts (`com.benelsom.touchbarpet.state`). Tapping
  the copy opens the window. When Better Narrator's bar closes, the real cat is
  underneath again.
- Uses private Touch Bar APIs, the same ones MTMR, Pock and Better Narrator use.
  A future macOS update could break it.

## Credits

Cat sprite: [2D Pixel Art Cat Sprites](https://elthen.itch.io/2d-pixel-art-cat-sprites)
by Elthen, free for commercial and non-commercial use.
