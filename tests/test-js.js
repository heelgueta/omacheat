// Unit tests for Omacheat.js. Run: node tests/test-js.js
const fs = require("fs"), vm = require("vm"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Omacheat.js"), "utf8").replace(/^\.pragma library/, "")
const O = {}; vm.runInNewContext(src, O)

let pass = 0, fail = 0
function t(name, fn) { try { fn(); pass++; console.log("  ok   " + name) } catch (e) { fail++; console.log("  FAIL " + name + "\n       " + e.message) } }

const sample = [
  "SUPER + K   → Keybindings",
  "SUPER SHIFT + RETURN   → Browser",
  "SUPER + 1   → Switch to workspace 1",
  "SUPER + 2   → Switch to workspace 2",
  "SUPER + 3   → Switch to workspace 3",
  "SUPER SHIFT + 1   → Move window to workspace 1",
  "SUPER SHIFT + 2   → Move window to workspace 2",
  "SUPER SHIFT + 3   → Move window to workspace 3",
  "SUPER ALT + RETURN   → Tmux",
  "XF86AudioRaiseVolume   → Volume up",
  "SUPER SHIFT + S   → Spotify",
  "SUPER + SHIFT + CTRL + Z   → Something odd",
  "garbage line without an arrow"
].join("\n")

console.log("parse / categories")
t("parses combos into mods and key", () => {
  const rows = O.parse(sample, [], [])
  const b = rows.find(r => r.desc === "Browser")
  assert.deepStrictEqual(Array.from(b.mods), ["SUPER", "SHIFT"]); assert.strictEqual(b.key, "RETURN")
})
t("ignores lines without an arrow", () => assert.ok(!O.parse(sample).some(r => /garbage/.test(r.desc))))
t("collapses numbered workspace binds", () => {
  const rows = O.parse(sample), w = rows.find(r => r.desc === "Switch to workspace N")
  assert.ok(w); assert.strictEqual(w.key, "1…0"); assert.strictEqual(w.items.length, 3)
  assert.ok(!rows.some(r => r.desc === "Switch to workspace 2"))
})
t("categorizes by description", () => {
  const cat = d => O.parse(sample).find(r => r.desc === d).category
  assert.strictEqual(cat("Browser"), "apps"); assert.strictEqual(cat("Tmux"), "apps")
  assert.strictEqual(cat("Switch to workspace N"), "workspaces"); assert.strictEqual(cat("Volume up"), "media")
})
t("unknown Super+Shift shortcut falls back to apps", () => assert.strictEqual(O.parse(sample).find(r => r.desc === "Spotify").category, "apps"))
t("anything else falls back to other", () => assert.strictEqual(O.parse(sample).find(r => r.desc === "Something odd").category, "other"))
t("Keybindings row is locked", () => assert.ok(O.parse(sample).find(r => r.desc === "Keybindings").locked))
t("search filters by description and key", () => {
  const rows = O.parse(sample)
  const names = q => O.categories(rows, q).flatMap(c => c.rows.map(r => r.desc))
  assert.deepStrictEqual(Array.from(names("browser")), ["Browser"]); assert.ok(names("volume").includes("Volume up"))
  assert.ok(names("super return").includes("Browser")); assert.strictEqual(names("nonsense").length, 0)
})
t("masonry keeps every category exactly once", () => {
  const cats = O.categories(O.parse(sample), ""), cols = O.toColumns(cats, 3)
  assert.strictEqual(cols.flat().length, cats.length); assert.strictEqual(cols.length, 3)
})

console.log("switched-off shortcuts")
t("disabled entries are merged back and flagged", () => {
  const off = [{ mods: ["SUPER", "ALT"], key: "RETURN", desc: "Tmux" }]
  const rows = O.parse(sample.replace("SUPER ALT + RETURN   → Tmux\n", ""), off)
  const tmux = rows.find(r => r.desc === "Tmux"); assert.ok(tmux && tmux.disabled)
})
t("mod order and case do not matter for matching", () => {
  const rows = O.parse(sample, [{ mods: ["alt", "super"], key: "RETURN", desc: "Tmux" }])
  assert.ok(rows.find(r => r.desc === "Tmux").disabled)
})

console.log("added shortcuts")
const custom = [{ mods: ["SUPER", "ALT"], key: "F", desc: "Files", cmd: "nautilus", category: "capture" }]
t("an added shortcut uses its chosen category and is flagged custom", () => {
  const rows = O.parse(sample + "\nSUPER ALT + F   → Files", [], custom), f = rows.find(r => r.desc === "Files")
  assert.strictEqual(f.category, "capture"); assert.ok(f.custom); assert.ok(!f.locked)
})
t("an added shortcut Hyprland did not report is still listed", () => {
  const f = O.parse(sample, [], custom).find(r => r.desc === "Files"); assert.ok(f && f.custom)
})
t("an invalid category falls back to the rules", () => {
  const c = [{ mods: ["SUPER"], key: "B", desc: "Browser two", cmd: "x", category: "nope" }]
  assert.strictEqual(O.parse("", [], c)[0].category, "apps")
})
t("custom flag survives into category output", () => {
  const cats = O.categories(O.parse(sample, [], custom), "files"); assert.ok(cats[0].rows[0].custom)
})
t("custom row cannot be switched off (flag only, no disabled)", () => {
  const r = O.parse(sample, [{ mods: ["SUPER", "ALT"], key: "F", desc: "Files" }], custom).find(r => r.desc === "Files")
  assert.ok(!r.disabled)
})

t("dropBinding removes only that combination's line", () => {
  const out = O.dropBinding(sample + "\nSUPER ALT + F   → Files", ["ALT", "SUPER"], "f")
  assert.ok(!/Files/.test(out)); assert.ok(/Browser/.test(out)); assert.strictEqual(out.split("\n").length, sample.split("\n").length)
})

console.log("form helpers")
t("letters, digits and F keys map to Hyprland names", () => {
  assert.strictEqual(O.keyFromQt(0x41), "A"); assert.strictEqual(O.keyFromQt(0x35), "5")
  assert.strictEqual(O.keyFromQt(0x01000030), "F1"); assert.strictEqual(O.keyFromQt(0x0100003b), "F12")
})
t("punctuation and navigation keys use raw names", () => {
  assert.strictEqual(O.keyFromQt(0x2c), "comma"); assert.strictEqual(O.keyFromQt(0x20), "SPACE")
  assert.strictEqual(O.keyFromQt(0x01000004), "RETURN"); assert.strictEqual(O.keyFromQt(0x01000012), "LEFT")
})
t("modifiers and Escape are not bindable from the form", () => {
  for (const code of [0x01000020, 0x01000021, 0x01000023, 0x01000022, 0x01000000]) assert.strictEqual(O.keyFromQt(code), null)
})
t("conflict finds an existing combo regardless of order/case", () => {
  const rows = O.parse(sample)
  assert.strictEqual(O.conflict(rows, ["shift", "super"], "return").desc, "Browser")
  assert.strictEqual(O.conflict(rows, ["SUPER"], "Q"), null)
})
t("conflict sees inside collapsed workspace rows", () => assert.strictEqual(O.conflict(O.parse(sample), ["SUPER"], "2").desc, "Switch to workspace N"))
t("validate asks for what is missing", () => {
  const ok = { desc: "x", cmd: "y", key: "F", mods: ["SUPER"] }
  assert.strictEqual(O.validate(ok), "")
  assert.match(O.validate({ ...ok, desc: " " }), /name/i); assert.match(O.validate({ ...ok, cmd: "" }), /run/i)
  assert.match(O.validate({ ...ok, key: "" }), /key/i); assert.match(O.validate({ ...ok, mods: [] }), /modifier/i)
  assert.strictEqual(O.validate({ ...ok, mods: [], key: "F9" }), "")
})
t("prettyKey/tokens render keycaps", () => {
  assert.deepStrictEqual(Array.from(O.tokens({ mods: ["SUPER", "SHIFT"], key: "RETURN" })), ["Super", "Shift", "Enter"])
  assert.strictEqual(O.prettyKey("XF86AudioMute"), "Audio Mute")
})

console.log("\n" + pass + " passed, " + fail + " failed"); process.exit(fail ? 1 : 0)
