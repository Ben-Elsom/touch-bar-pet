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
approved tool finishes. Tools that show their own "Allow…?" card in the Claude app,
such as computer use's app access request, count as "needs access" too.

## The window

Open Touch Bar Pet from `~/Applications`, or tap the cat. Closing the window leaves the cat running.

Every open chat is listed under **Needs your input**, **Currently running** or
**Awaiting next step**, with how long it's been there, what it wants, and a button to
open it. **Move to Awaiting** quiets a chat until a later turn wants something.
**Archive…** warns about uncommitted files, then opens the chat for you to archive in
Claude: the app can't archive chats itself. The titles and statuses come from Claude's
private session files, read-only, so a Claude update could break this list.

## Staying visible while you're away

The Touch Bar goes blank about 75 seconds after your last input, even with Amphetamine
on, and only a real input device wakes it. The optional helper in `Helper/` fixes that:
while the display is being held awake and you've been idle for 30 seconds, it moves
the pointer one pixel and back through Karabiner's free virtual mouse.

The display counts as held while an Amphetamine session is on, or while the Claude app
is open (or a terminal Claude is working or waiting on you). The pet keeps the display
awake itself then, with no time limit, so you can leave it overnight and see at a
glance whether Claude is still working (walking), stuck (pawing), waiting on you
(sitting) or all done (asleep). The bar only goes dark once Claude is closed.

1. Install [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) 8.7.0 and allow its driver extension in System Settings.
2. Run `Helper/install_helper.sh`, which asks for your password.

The **Always-On Touch Bar** switch in the window turns this on or off; it starts on.
Run `Helper/uninstall_helper.sh` to remove the helper, adding `--driver` to remove the
driver too. `build/touchbar_nudge --check` shows what the helper would do right now.

Things to know: the helper and Karabiner's service run as root at every boot, because
Karabiner only accepts root clients. The nudges count as activity, so the screen saver
and auto-lock won't start while Amphetamine is on or Claude is
open. The bar is OLED, so a note left
showing for many hours risks burn-in.

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

## Karabiner is separate software

The always-on Touch Bar depends on Karabiner-DriverKit-VirtualHIDDevice, which is made
by pqrs-org and installed separately, not part of this project. If the bar starts going
blank while Amphetamine is on, especially after a macOS update, suspect Karabiner first:
it may need updating.

To diagnose:

- `build/touchbar_nudge --check` shows whether the switch, Amphetamine and idle time
  would allow a nudge. Run `Helper/build_helper.sh` first if it's missing.
- `systemextensionsctl list | grep pqrs` should say `activated enabled`.
- `launchctl print system/com.benelsom.touchbarpet.nudge` and
  `launchctl print system/com.benelsom.touchbarpet.karabiner-daemon` should both say
  `state = running`.
- Check [its releases](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases)
  for a newer version and macOS support notes.

To update it, the driver and the client headers must match, because its service rejects
a different `client_protocol_version`:

1. Check the new package: `pkgutil --check-signature` should show Fumihiko Takayama
   (G43BCU2T37), notarized by Apple, and its hash should match the release page.
2. Install it. A new driver may need approval in System Settings.
3. Change `TAG` and `COMMIT` in `Helper/build_helper.sh` to that release and delete
   `build/karabiner_src`.
4. Run `Helper/install_helper.sh`.

To tell whether the bar is really showing, look at it. Its brightness step can report a
lit level while it shows nothing.
