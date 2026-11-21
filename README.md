# Omacheat

A friendlier keybindings help window for [Omarchy](https://omarchy.org/).

The stock window is one long flat list. Omacheat groups the same shortcuts by what they do
(open apps, move around, window behavior, resize, workspaces, groups, monitors, capture,
menus, notifications, system, media), draws them as keycaps, and lets you search.

- **Search**: type to filter by description, key, or category. Esc clears, then closes.
- **Switch shortcuts off**: each row has a toggle (or click the row). Switched-off shortcuts
  are unbound in Hyprland, stay visible dimmed and struck through, and can be switched back on.
  Keybindings, Omarchy menu and System menu cannot be switched off, so you can't lock yourself out.
- **Closes when you use a shortcut**: pressing Super/Ctrl/Alt closes the window. Turn this off
  with the "Close after using a shortcut" switch in the footer.

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
| `bin/omacheat-apply` | stores switched-off shortcuts and settings, writes the unbind file, reloads Hyprland |

State lives in `~/.config/omarchy/omacheat-disabled.json` and `omacheat-settings.json`; the generated
`~/.config/hypr/omacheat-disabled.lua` holds the `hl.unbind(...)` lines.

## Uninstall

Remove the `-- omacheat plugin` block from `~/.config/hypr/bindings.lua`, delete the plugin
directory and the files above, then `hyprctl reload`.

## Notes

Categories are assigned by pattern matching on shortcut descriptions (`RULES` in `Omacheat.js`).
Unrecognized Super+Shift shortcuts are treated as app launchers.
