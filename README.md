# Touch Bar Pet

A little pixel cat that lives on the far left of the MacBook Pro Touch Bar and
shows what Claude Code is doing. Apple's Control Strip (brightness, volume and so
on) stays on the right.

The cat nags until you've dealt with everything. Walking is the reward.

| Claude is… | The cat… |
|---|---|
| blocked | paws at you, with a yellow note: "Combo Caller needs access" for a permission prompt, "Combo Caller needs help" for a question |
| finished, waiting for you | sits, with a white note: "Combo Caller needs you" |
| working, and nothing needs you | walks back and forth (hops once when you clear the last one) |
| nothing to do | sleeps, with little z's |

The most urgent wins, across every session: one blocked or waiting Claude outranks
any number of working ones. Several show as "3 Claudes need you". The name is the
session's project folder.

A note stays until you answer that Claude or close it. The cat watches each Claude's
process, so a closed session clears itself, and a restart of the pet remembers who's
waiting. One known gap: there's no event for approving a permission, so "needs
access" stays until the approved tool finishes.

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
petsay --pet --seconds 5           # pet the cat from here
petsay --demo                      # show each state in turn, about a minute
petsay --status                    # list what the cat thinks each Claude is doing
petsay --clear                     # forget every Claude, for a note that's stuck
petsay --show                      # put the cat's bar back
petsay --quit                      # quit; Claude hooks won't relaunch it until you run petsay again
```

## Petting

Touch the cat and it purrs silently: eyes closed, a blush, a tiny shiver, floating
hearts and a little "prr". Keep your finger on it (up to 30 seconds) and it keeps
purring. Lift your finger and it carries on for 2.5 seconds. The sprite pack has no
petting animation, so this is its sitting tail-swish with an edited face.

## Notes

- macOS puts an ⓧ to the left of the cat that can't be removed. Tapping it
  hides the cat so you can see the front app's own buttons. The cat comes back
  when Claude's state changes, or within a minute.
- Only one bar can be visible at a time, and Better Narrator's full-width bar sits
  on top of the cat's while it's up. To keep the cat visible during a reading,
  Better Narrator hosts `Shared/CatMirrorView.swift`, a small copy of the cat that
  follows the state the pet broadcasts (`com.benelsom.touchbarpet.state`). Touching
  the copy pets the real cat. When Better Narrator's bar closes, the real cat is
  underneath again.
- Uses private Touch Bar APIs, the same ones MTMR, Pock and Better Narrator use.
  A future macOS update could break it.

## Credits

Cat sprite: [2D Pixel Art Cat Sprites](https://elthen.itch.io/2d-pixel-art-cat-sprites)
by Elthen, free for commercial and non-commercial use.
