# Omacheat

A friendlier keybindings help window for [Omarchy](https://omarchy.org/).

The stock window is one long flat list. Omacheat groups the same shortcuts by what they do
(open apps, move around, window behavior, resize, workspaces, groups, monitors, capture,
menus, notifications, system, media), draws them as keycaps, and lets you search.

- **Search**: type to filter by description, key, or category. Esc clears, then closes.
- **Switch shortcuts off**: each row has a toggle (or click the row). Switched-off shortcuts
  are unbound in Hyprland, stay visible dimmed and struck through, and can be switched back on.
  Keybindings, Omarchy menu and System menu cannot be switched off, so you can't lock yourself out.
- **Add your own**: **+ Add shortcut** (or Ctrl+N) takes a name, a command, modifiers, a key and the
  group to list it under. It warns if the combination is already taken (saving then replaces it).
  Added shortcuts get a ✕ to remove them.
- **Closes when you use a shortcut**: not when you merely tap Super or Ctrl. Turn this off with the
  "Close after using a shortcut" switch in the footer. See [How closing works](#how-closing-works).

## Install

```bash
git clone https://github.com/heelgueta/omacheat.git ~/.config/omarchy/plugins/heelgueta.omacheat
~/.config/omarchy/plugins/heelgueta.omacheat/install.sh
```

`install.sh` makes Omacheat the default keybindings window:

- appends a block to `~/.config/hypr/bindings.lua` that rebinds Super+K and loads the
  switched-off list (the block is only added once);
- enables the plugin and reloads Hyprland.

To make Learn → Keybindings in the Omarchy menu open it too, add this to
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"learn.keybindings": {"action":"omarchy-shell shell toggle heelgueta.omacheat"},
```

Or open it directly any time: `omarchy-shell shell toggle heelgueta.omacheat`.

## Files

| Path | What |
|------|------|
| `Omacheat.qml` | the overlay window |
| `Omacheat.js` | parses `omarchy-menu-keybindings --print` and sorts shortcuts into categories |
| `bin/omacheat-apply` | stores switched-off and added shortcuts and settings, writes the Hyprland lua file, reloads Hyprland |
| `tests/` | `tests/run.sh` runs the JS and shell tests |

State lives in `~/.config/omarchy/omacheat-disabled.json`, `omacheat-custom.json` and
`omacheat-settings.json`. The generated `~/.config/hypr/omacheat-disabled.lua` holds the
`hl.unbind(...)` lines, the `o.bind(...)` lines for shortcuts you added, and the key listener below.

## How closing works

Hyprland swallows the key that completes a shortcut, so a window with keyboard focus never sees it.
While Omacheat is open, the generated lua file reports the scancode of each key press (and nothing else:
no text, no history, only the latest code) to `$XDG_RUNTIME_DIR/omacheat-keys`. If the window did not
receive that key itself a moment later, a shortcut fired and the window closes. A key the window did
receive (typing, or a combination nothing is bound to) leaves it open. Reporting only happens while a
flag file written by the open window is under 15 minutes old.

## Uninstall

Remove the `-- omacheat plugin` block from `~/.config/hypr/bindings.lua`, delete the plugin
directory and the files above, then `hyprctl reload`.

## Notes

Categories are assigned by pattern matching on shortcut descriptions (`RULES` in `Omacheat.js`).
Unrecognized Super+Shift shortcuts are treated as app launchers.
