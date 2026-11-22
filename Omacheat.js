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

function comboId(mods, key) {
  return mods.map(function(m) { return m.toUpperCase() }).sort().join(" ") + "|" + String(key).toUpperCase()
}

// `disabled`: [{mods, key, desc}] switched off by the user. Hyprland no longer
// reports those, so they are merged back in to stay visible (and re-enableable).
// `custom`: [{mods, key, desc, cmd, category}] shortcuts the user added; they take the
// category they were given and are flagged so the window can offer to remove them.
function parse(text, disabled, custom) {
  var rows = []
  var seen = {}
  var off = {}
  var added = {}
  disabled = disabled || []
  custom = custom || []
  for (var c = 0; c < custom.length; c++) added[comboId(custom[c].mods, custom[c].key)] = custom[c]
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
    rows.push(makeRow(mods, key, desc, off, added[comboId(mods, key)]))
  }
  // Added shortcuts that Hyprland did not report (e.g. a failed reload) stay visible and removable.
  for (var a in added) {
    var have = rows.some(function(r) { return comboId(r.mods, r.key) === a })
    if (!have) rows.push(makeRow(added[a].mods, added[a].key, added[a].desc, off, added[a]))
  }
  for (var e = 0; e < disabled.length; e++) {
    var x = disabled[e]
    var present = rows.some(function(r) { return itemId(r.mods, r.desc) === itemId(x.mods, x.desc) })
    if (!present) rows.push(makeRow(x.mods, x.key, x.desc, off))
  }
  return collapseNumbered(rows)
}

var LOCKED = /^(Keybindings|Omarchy menu|System menu)$/

function makeRow(mods, key, desc, off, added) {
  var known = added && byCategory(added.category)
  return {
    mods: mods, key: key, desc: added ? added.desc : desc,
    category: known ? added.category : categoryFor(desc, mods, key),
    items: [{ mods: mods, key: key, desc: added ? added.desc : desc }],
    disabled: !added && !!off[itemId(mods, desc)],
    locked: !added && LOCKED.test(desc),
    custom: !!added
  }
}

function byCategory(id) {
  return CATEGORIES.some(function(c) { return c.id === id })
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
    var hay = (r.desc + " " + tokens(r).join(" ") + " " + r.key + " " + byId[r.category].title).toLowerCase()
    var ok = true
    for (var w = 0; w < q.length; w++) if (hay.indexOf(q[w]) < 0) { ok = false; break }
    if (ok) byId[r.category].rows.push({ desc: r.desc, tokens: tokens(r), items: r.items, disabled: r.disabled, locked: r.locked, custom: r.custom })
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

// Hyprland names for the keys the "add shortcut" form accepts, by Qt key code.
var QT_KEYS = {
  0x20: "SPACE", 0x01000004: "RETURN", 0x01000005: "RETURN", 0x01000001: "TAB",
  0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
  0x2c: "comma", 0x2e: "period", 0x2d: "minus", 0x3d: "equal", 0x2f: "slash", 0x3b: "semicolon",
  0x27: "apostrophe", 0x5b: "bracketleft", 0x5d: "bracketright", 0x5c: "backslash", 0x60: "grave",
  0x01000009: "PRINT", 0x01000010: "HOME", 0x01000011: "END", 0x01000016: "PRIOR", 0x01000017: "NEXT",
  0x01000007: "DELETE", 0x01000003: "BACKSPACE", 0x01000006: "INSERT"
}

// null when the key can't be bound from the form (modifiers, Escape, dead keys …).
function keyFromQt(code) {
  if (code >= 0x41 && code <= 0x5a) return String.fromCharCode(code)        // A-Z
  if (code >= 0x30 && code <= 0x39) return String.fromCharCode(code)        // 0-9
  if (code >= 0x01000030 && code <= 0x0100003b) return "F" + (code - 0x01000030 + 1)
  return QT_KEYS[code] || null
}

// The existing shortcut using this combination, or null. Collapsed rows (workspace 1…0) check each item.
function conflict(rows, mods, key) {
  var want = comboId(mods, key)
  for (var i = 0; i < rows.length; i++)
    for (var j = 0; j < rows[i].items.length; j++)
      if (comboId(rows[i].items[j].mods, rows[i].items[j].key) === want) return rows[i]
  return null
}

// Validation message for the form, or "" when it can be saved.
function validate(form) {
  if (!String(form.desc || "").trim()) return "Give it a name"
  if (!String(form.cmd || "").trim()) return "What should it run?"
  if (!form.key) return "Press a key"
  if (!form.mods.length && !/^(F\d+|PRINT)$/.test(form.key)) return "Pick at least one modifier"
  return ""
}

// `text` (the --print output) without the line for this combination, so a just-removed
// shortcut does not reappear while Hyprland is still reloading.
function dropBinding(text, mods, key) {
  var want = comboId(mods, key)
  return String(text || "").split("\n").filter(function(line) {
    var arrow = line.indexOf("→")
    if (arrow < 0) return true
    var combo = line.substring(0, arrow).trim()
    var plus = combo.indexOf(" + ")
    var m = plus < 0 ? [] : combo.substring(0, plus).split(/\s+/)
    return comboId(m, plus < 0 ? combo : combo.substring(plus + 3)) !== want
  }).join("\n")
}
