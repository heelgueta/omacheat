#!/usr/bin/env bash
# Make Omacheat the default keybindings window (Super+K and Learn > Keybindings).
set -euo pipefail

id="heelgueta.omacheat"
dir="$HOME/.config/omarchy/plugins/$id"
bindings="$HOME/.config/hypr/bindings.lua"
marker="-- omacheat plugin"

chmod +x "$dir/bin/omacheat-apply"

if ! grep -qF -- "$marker" "$bindings"; then
  cat >>"$bindings" <<LUA

$marker: friendlier Super+K window, plus the shortcuts switched off inside it
hl.unbind("SUPER + K")
o.bind("SUPER + K", "Keybindings", "omarchy-shell shell toggle $id")
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/omacheat-disabled.lua")
LUA
fi

"$dir/bin/omacheat-apply" apply
omarchy plugin enable "$id" 2>/dev/null || omarchy-shell shell enablePlugin "$id" '{}'
echo "Done. Press Super+K."
