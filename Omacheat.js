.pragma library

// Turns the lines of `omarchy-menu-keybindings --print` ("SUPER + K   → Keybindings")
// into rows grouped by what the shortcut does.

var CATEGORIES = [
  { id: "apps",       title: "Open apps",              blurb: "Terminal, browser, files and your web apps" },
  { id: "focus",      title: "Move around",            blurb: "Jump focus between windows, or shove them around" },
  { id: "state",      title: "Window behavior",        blurb: "Full screen, floating, closing, layout" },
  { id: "resize",     title: "Resize windows",         blurb: "Make the active window bigger or smaller" },
  { id: "workspaces", title: "Workspaces",             blurb: "Switch desktops and send windows to them" },
  { id: "groups",     title: "Window groups (tabs)",   blurb: "Stack several windows into one tabbed slot" },
  { id: "monitors",   title: "Monitors & zoom",        blurb: "Multiple screens, scaling and magnification" },
  { id: "capture",    title: "Capture & clipboard",    blurb: "Screenshots, recordings, copy/paste, emojis" },
  { id: "menus",      title: "Menus & panels",         blurb: "Omarchy menus and the bar's popup panels" },
  { id: "notif",      title: "Notifications & reminders", blurb: "" },
  { id: "system",     title: "System & voice",         blurb: "Lock, night light, dictation" },
  { id: "media",      title: "Media & hardware keys",  blurb: "Volume, brightness, playback" },
  { id: "other",      title: "Everything else",        blurb: "" }
]

// First match wins, so order matters.
var RULES = [
  ["media",    /^(Volume|Next track|Previous track|Play|Pause|Mute|Brightness|Keyboard brightness|Mic)|XF86/i],
  ["apps",     /^(Terminal|Browser|File manager|Tmux|Herdr|Calculator|Apps menu|Editor)\b/i],
  ["groups",   /group/i],
  ["monitors", /monitor|display|mirroring|scaling|zoom/i],
  ["workspaces", /workspace|scratchpad|^Scroll active/i],
  ["resize",   /^(Resize|Expand|Shrink)|window width/i],
  ["focus",    /^Focus|^Swap window|^Move window$|^Reveal active|^Cycle to/i],
  ["state",    /^Close|full ?screen|full width|floating|split|^Pop window|transparency|gaps|layout|aspect|^Pseudo/i],
  ["notif",    /notification|reminder/i],
  ["capture",  /screenshot|screenrecord|color picker|\bOCR\b|extract text|clipboard|^Universal|emoji|webcam|download video|copy url|transcode|^Share$/i],
  ["system",   /^Lock|nightlight|idle|dictation/i],
  ["menus",    /menu|^Keybindings$|^Background switcher|^Bar panel|^(Audio|Bluetooth|Network|Power|Activity|Display|Calendar)$|top bar|battery|^Show |weather/i]
]

var MOD_NAMES = { SUPER: "Super", SHIFT: "Shift", CTRL: "Ctrl", ALT: "Alt" }
var KEY_NAMES = {
  RETURN: "Enter", ESCAPE: "Esc", SPACE: "Space", BACKSPACE: "⌫", DELETE: "Del", TAB: "Tab",
  MINUS: "-", EQUAL: "=", COMMA: ",", PERIOD: ".", SLASH: "/", BRACKETLEFT: "[", BRACKETRIGHT: "]",
  LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓", PRINT: "PrtSc", BAR: "|", HOME: "Home",
  "LEFT MOUSE BUTTON": "Drag", "RIGHT MOUSE BUTTON": "Right-drag", "MIDDLE MOUSE BUTTON": "Middle-click",
  MOUSE_DOWN: "Scroll ↓", MOUSE_UP: "Scroll ↑"
}

function prettyKey(key) {
  var up = key.toUpperCase()
  if (KEY_NAMES[up] !== undefined) return KEY_NAMES[up]
  if (up.indexOf("XF86") === 0) return key.substring(4).replace(/([a-z])([A-Z])/g, "$1 $2")
  return key.length === 1 ? up : key.charAt(0).toUpperCase() + key.substring(1).toLowerCase()
}

function categoryFor(desc, mods, key) {
  if (/^XF86/i.test(key || "")) return "media"
  for (var i = 0; i < RULES.length; i++)
    if (RULES[i][1].test(desc)) return RULES[i][0]
  // Remaining Super+Shift(+X) binds are the user's app / web-app launchers.
  if (mods.indexOf("SUPER") >= 0 && mods.indexOf("SHIFT") >= 0) return "apps"
  return "other"
}

function itemId(mods, desc) {
  return mods.map(function(m) { return m.toUpperCase() }).sort().join(" ") + "|" + desc
}

// `disabled`: [{mods, key, desc}] switched off by the user. Hyprland no longer
// reports those, so they are merged back in to stay visible (and re-enableable).
function parse(text, disabled) {
  var rows = []
  var seen = {}
  var off = {}
  disabled = disabled || []
  for (var d = 0; d < disabled.length; d++) off[itemId(disabled[d].mods, disabled[d].desc)] = true
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var arrow = lines[i].indexOf("→")
    if (arrow < 0) continue
    var combo = lines[i].substring(0, arrow).trim()
    var desc = lines[i].substring(arrow + 1).trim()
    if (!combo || !desc || seen[combo + "|" + desc]) continue
    seen[combo + "|" + desc] = true

    var plus = combo.indexOf(" + ")
    var mods = plus < 0 ? [] : combo.substring(0, plus).split(/\s+/)
    var key = plus < 0 ? combo : combo.substring(plus + 3)
    rows.push(makeRow(mods, key, desc, off))
  }
  for (var e = 0; e < disabled.length; e++) {
    var x = disabled[e]
    var present = rows.some(function(r) { return itemId(r.mods, r.desc) === itemId(x.mods, x.desc) })
    if (!present) rows.push(makeRow(x.mods, x.key, x.desc, off))
  }
  return collapseNumbered(rows)
}

var LOCKED = /^(Keybindings|Omarchy menu|System menu)$/

function makeRow(mods, key, desc, off) {
  return {
    mods: mods, key: key, desc: desc, category: categoryFor(desc, mods, key),
    items: [{ mods: mods, key: key, desc: desc }],
    disabled: !!off[itemId(mods, desc)],
    locked: LOCKED.test(desc)
  }
}

// "Switch to workspace 1" … "…9" become one row: Super + 1…0 → "Switch to workspace N".
function collapseNumbered(rows) {
  var groups = {}
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!/^[0-9]$/.test(r.key) || !/\d+$/.test(r.desc)) continue
    var gid = r.mods.join(" ") + "|" + r.desc.replace(/\d+$/, "")
    ;(groups[gid] = groups[gid] || []).push(i)
  }
  var drop = {}
  for (var gid in groups) {
    var idx = groups[gid]
    if (idx.length < 3) continue
    var first = rows[idx[0]]
    first.desc = first.desc.replace(/\d+$/, "N")
    first.key = "1…0"
    for (var j = 1; j < idx.length; j++) {
      drop[idx[j]] = true
      first.items.push(rows[idx[j]].items[0])
      first.disabled = first.disabled && rows[idx[j]].disabled
    }
  }
  var out = []
  for (var k = 0; k < rows.length; k++) if (!drop[k]) out.push(rows[k])
  return out
}

function tokens(row) {
  var t = []
  for (var i = 0; i < row.mods.length; i++) t.push(MOD_NAMES[row.mods[i]] || row.mods[i])
  t.push(row.key === "1…0" ? row.key : prettyKey(row.key))
  return t
}

// Rows filtered by `query`, bucketed into categories (empty ones dropped).
function categories(rows, query) {
  var q = String(query || "").toLowerCase().trim().split(/\s+/).filter(function(s) { return s.length })
  var byId = {}
  for (var c = 0; c < CATEGORIES.length; c++)
    byId[CATEGORIES[c].id] = { id: CATEGORIES[c].id, title: CATEGORIES[c].title, blurb: CATEGORIES[c].blurb, rows: [] }

  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var hay = (r.desc + " " + tokens(r).join(" ") + " " + byId[r.category].title).toLowerCase()
    var ok = true
    for (var w = 0; w < q.length; w++) if (hay.indexOf(q[w]) < 0) { ok = false; break }
    if (ok) byId[r.category].rows.push({ desc: r.desc, tokens: tokens(r), items: r.items, disabled: r.disabled, locked: r.locked })
  }

  var out = []
  for (var d = 0; d < CATEGORIES.length; d++) {
    var cat = byId[CATEGORIES[d].id]
    if (cat.rows.length) out.push(cat)
  }
  return out
}

// Greedy masonry: each category goes to the currently shortest column.
function toColumns(cats, n) {
  var cols = [], heights = []
  for (var i = 0; i < n; i++) { cols.push([]); heights.push(0) }
  for (var c = 0; c < cats.length; c++) {
    var best = 0
    for (var j = 1; j < n; j++) if (heights[j] < heights[best]) best = j
    cols[best].push(cats[c])
    heights[best] += cats[c].rows.length + 3
  }
  return cols
}
