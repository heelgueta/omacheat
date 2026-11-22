#!/bin/bash
# Tests for bin/omacheat-apply against a throwaway HOME, with a stub hyprctl.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export OMACHEAT_FOREGROUND=1 HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run"
mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy" "$XDG_RUNTIME_DIR" "$tmp/bin"
printf '#!/bin/sh\necho "$@" >> "%s/hyprctl.log"\n' "$tmp" >"$tmp/bin/hyprctl"; chmod +x "$tmp/bin/hyprctl"
export PATH="$tmp/bin:$PATH"
apply="$here/bin/omacheat-apply"
gen="$HOME/.config/hypr/omacheat-disabled.lua"

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; [[ -n ${2:-} ]] && echo "       $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

# A minimal Hyprland config the scanner can run: two described binds plus the one we will add.
cat >"$HOME/.config/hypr/hyprland.lua" <<'LUA'
o = { bind = function(keys, desc, cmd) hl.bind(keys, cmd, { description = desc }) end }
o.bind("SUPER + SHIFT + RETURN", "Terminal", "x")
o.bind("SUPER + ALT + RETURN", "Tmux", "x")
o.bind("SUPER + SHIFT + CTRL + G", "Gemini", "x")
LUA

# Harness that loads the generated file with recording stubs for hl and o.
load_generated() {
  lua - "$gen" <<'LUA'
local calls, handler = {}, nil
hl = { unbind = function(k) calls[#calls+1] = "unbind " .. k end,
       on = function(ev, fn) calls[#calls+1] = "on " .. ev; handler = fn end }
o = { launch = function(c) return "LAUNCH(" .. c .. ")" end,
      shell_quote = function(v) return "Q(" .. v .. ")" end,
      bind = function(k, d, c) calls[#calls+1] = "bind " .. k .. " | " .. d .. " | " .. c end }
local ok, err = pcall(dofile, arg[1])
if not ok then print("LOAD-ERROR " .. tostring(err)) os.exit(1) end
for _, c in ipairs(calls) do print(c) end
LUA
}

echo "defaults"
"$apply" apply
check "files created" '[[ -s $HOME/.config/omarchy/omacheat-custom.json && -s $HOME/.config/omarchy/omacheat-disabled.json ]]'
check "empty state generates a loadable file" 'load_generated >/dev/null'
check "listener registered" 'load_generated | grep -q "^on input.keyboard.key"'
check "hyprctl reload called" 'grep -q reload "$tmp/hyprctl.log"'

echo "switching off"
"$apply" set off '[{"mods":["SUPER","ALT"],"key":"RETURN","desc":"Tmux"}]'
check "unbinds the matching raw key" 'load_generated | grep -qx "unbind SUPER + ALT + RETURN"'
check "does not unbind others" '! load_generated | grep -q "unbind SUPER + SHIFT + RETURN"'
"$apply" set on '[{"mods":["SUPER","ALT"],"key":"RETURN","desc":"Tmux"}]'
check "switching back on removes the unbind" '! load_generated | grep -q "^unbind"'

echo "adding shortcuts"
"$apply" add '{"mods":["SUPER","ALT"],"key":"F","desc":"Files \"quoted\" é","cmd":"nautilus --new-window \"$HOME\"","category":"apps"}'
out=$(load_generated)
check "generated file loads" '[[ $out != LOAD-ERROR* ]]' "$out"
check "unbinds first, then binds" 'grep -n . <<<"$out" | grep -q "unbind SUPER + ALT + F" && grep -q "^bind SUPER + ALT + F | Files" <<<"$out"'
check "description survives quoting" 'grep -qF "Files \"quoted\" é" <<<"$out"'
check "command goes through sh -c" 'grep -qF "LAUNCH(sh -c Q(nautilus --new-window \"\$HOME\"))" <<<"$out"'
"$apply" add '{"mods":["ALT","SUPER"],"key":"f","desc":"Files again","cmd":"thunar","category":"apps"}'
check "same combo replaces instead of duplicating" '[[ $("$apply" custom | jq length) == 1 && $("$apply" custom | jq -r ".[0].desc") == "Files again" ]]'
"$apply" add '{"mods":["SUPER"],"key":"comma","desc":"Evil\u0001 \u001bname","cmd":"echo a\nb","category":"other"}'
out=$(load_generated)
check "control characters cannot break the lua" '[[ $out != LOAD-ERROR* ]]' "$out"
"$apply" add '{"mods":[],"key":"F9","desc":"No modifier","cmd":"true","category":"other"}'
check "bind without modifiers uses the bare key" 'load_generated | grep -q "^bind F9 | No modifier"'
"$apply" remove '{"mods":["SUPER","ALT"],"key":"F"}'
"$apply" remove '{"mods":["SUPER"],"key":"comma"}'
"$apply" remove '{"mods":[],"key":"F9"}'
check "remove takes them all away" '[[ $("$apply" custom | jq length) == 0 ]] && ! load_generated | grep -q "^bind"'

echo "key listener"
# Drive the listener: load the generated file, fire events, read the output file.
listener() {
  lua - "$gen" "$@" <<'LUA'
local handler
hl = { unbind = function() end, on = function(_, fn) handler = fn end }
o = { launch = function() end, shell_quote = function() end, bind = function() end }
dofile(arg[1])
for i = 2, #arg do
  local code, state = arg[i]:match("(%d+):(%d)")
  handler(tonumber(code), 0, tonumber(state))
end
LUA
}
"$apply" apply
keys="$XDG_RUNTIME_DIR/omacheat-keys"
listener 133:1 46:1 133:0; check "nothing recorded while the window is closed" '[[ ! -e $keys ]]'
"$apply" watch on
check "watch on creates flag" '[[ -s $XDG_RUNTIME_DIR/omacheat-watch ]]'
listener 133:1 46:1 46:0 133:0; check "Super+key reports the key code" '[[ $(awk "{print \$3}" "$keys") == 46 ]]'
: >"$keys"; listener 133:1 133:0 ;  check "a bare modifier tap reports nothing" '[[ ! -s $keys ]]'
: >"$keys"; listener 46:0 ;         check "key releases are not reported" '[[ ! -s $keys ]]'
: >"$keys"; listener 123:1;         check "media key is reported" '[[ $(awk "{print \$3}" "$keys") == 123 ]]'
: >"$keys"; listener 38:1 39:1;     check "only the latest code is kept" '[[ $(wc -l <"$keys") == 1 && $(awk "{print \$3}" "$keys") == 39 ]]'
echo $(( $(date +%s) - 200 )) >"$XDG_RUNTIME_DIR/omacheat-watch"
: >"$keys"; listener 133:1 46:1;  check "stale flag (>2 min) records nothing" '[[ ! -s $keys ]]'
"$apply" watch on; echo $(( $(date +%s) - 200 )) >"$XDG_RUNTIME_DIR/omacheat-watch"; "$apply" watch touch
: >"$keys"; listener 133:1 46:1; check "watch touch keeps the flag fresh" '[[ $(awk "{print \$3}" "$keys") == 46 ]]'
"$apply" watch off; "$apply" watch touch
check "watch touch does not recreate a removed flag" '[[ ! -e $XDG_RUNTIME_DIR/omacheat-watch ]]'
"$apply" watch on; "$apply" watch off
check "watch off removes the files" '[[ ! -e $XDG_RUNTIME_DIR/omacheat-watch && ! -e $keys ]]'

echo; echo "$pass passed, $fail failed"; [[ $fail -eq 0 ]]
