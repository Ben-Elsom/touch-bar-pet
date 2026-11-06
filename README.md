# Touch Bar Pet

A little pixel cat for the MacBook Pro Touch Bar. It sits in the Control Strip and
pops up full width with a speech bubble when it gets a message, from Claude Code
or from any script.

## Install

```bash
./install.sh
```

This builds with the Xcode Command Line Tools (no full Xcode), puts
`Touch_Bar_Pet.app` in `~/Applications` and `petsay` in `~/.local/bin`.

## petsay

```bash
petsay "Build finished!" --mood done
petsay --mood work            # change what the cat is doing, no bubble
echo "hello" | petsay
petsay --theme ginger         # grey, ginger, cream, blue, calico
petsay --hide                 # put the bubble away
petsay --quit                 # quit; Claude hooks won't relaunch it until you run petsay again
```

Moods: `idle` (sits, grooms), `think` (grooms), `work` (walks), `done` (jumps, green
bubble), `needs` (paws at you, yellow bubble), `alert` (scared, pink bubble), `sleep`.

Tap the cat in the Control Strip to see the last message again. While the bubble
is up, tap the cat to pet it (hearts!) or tap the bubble to dismiss it.

## Claude Code

`~/.claude/settings.json` runs `petsay --hook` on these events:

| Event | What the cat does |
|---|---|
| SessionStart | sits |
| UserPromptSubmit | grooms (thinking) |
| PreToolUse | walks (working) |
| Notification | paws at you and shows the message, e.g. a permission request |
| Stop | jumps and shows the start of Claude's reply |
| SessionEnd | falls asleep |

The hooks are `async`, so they never slow Claude down.

## Notes

- The always-visible cat needs the Touch Bar set to show **App Controls** with the
  Control Strip. With **Expanded Control Strip**, only the pop-up messages appear.
- Uses private Touch Bar APIs, the same ones MTMR and Pock use. A future macOS
  update could break it.
- Moods wear off: working or thinking goes back to idle after 3 minutes, and
  idle turns to sleep after 10.

## Credits

Cat sprite: [2D Pixel Art Cat Sprites](https://elthen.itch.io/2d-pixel-art-cat-sprites)
by Elthen, free for commercial and non-commercial use.
