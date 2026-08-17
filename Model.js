.pragma library

// Shape before `wordsmith` has answered. "idle" is the honest default: the
// widget has nothing to show and should say so rather than imply a stale result
// is current.
var EMPTY = {
  status: "idle",
  mode: "",
  modeLabel: "",
  source: "",
  original: "",
  result: "",
  error: "",
  chars: 0,
  resultChars: 0,
  elapsedMs: 0,
  model: "",
  startedAt: 0
}

var MODES = [
  { id: "professional", label: "Professional polish", hint: "Clear, correct, businesslike" },
  { id: "shorten",      label: "Shorten",             hint: "Same message, fewer words" },
  { id: "soften",       label: "Soften",              hint: "Warmer, without dropping the ask" },
  { id: "firm",         label: "Firm follow-up",      hint: "Explicit ask, stated deadline" }
]

function parse(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || typeof parsed !== "object") return null
    return parsed
  } catch (e) {
    return null
  }
}

function modeLabel(id) {
  for (var i = 0; i < MODES.length; i++)
    if (MODES[i].id === id) return MODES[i].label
  return id || ""
}

// The bar glyph's one-line story. Kept short — it shares a tooltip with the
// keybinding hint and there is no room for prose.
function summary(state) {
  switch (String(state.status)) {
    case "working": return "rewriting — " + (state.modeLabel || "…")
    case "done":    return (state.modeLabel || "rewrite") + " ready"
    case "error":   return "failed"
    default:        return "idle"
  }
}

function elapsed(state) {
  var ms = Number(state.elapsedMs)
  if (!isFinite(ms) || ms <= 0) return ""
  return (ms / 1000).toFixed(1) + "s"
}

// "selection" and "clipboard" are worth distinguishing in the panel: if a
// rewrite looks like it operated on the wrong text, this is the field that
// explains why.
function sourceLabel(state) {
  switch (String(state.source)) {
    case "selection": return "from your selection"
    case "clipboard": return "from the clipboard"
    case "stdin":     return "from stdin"
    default:          return ""
  }
}

function charCount(n) {
  var v = Number(n)
  if (!isFinite(v) || v <= 0) return ""
  if (v < 1000) return v + " chars"
  return (v / 1000).toFixed(1) + "k chars"
}

// Shown above the original so a long mail does not push the result off screen.
function preview(text, limit) {
  var s = String(text || "").replace(/\s+/g, " ").trim()
  if (s.length <= limit) return s
  return s.slice(0, limit - 1) + "…"
}

// Rough delta so you can see at a glance whether "Shorten" actually shortened.
function deltaLabel(state) {
  var a = Number(state.chars), b = Number(state.resultChars)
  if (!isFinite(a) || !isFinite(b) || a <= 0 || b <= 0) return ""
  var pct = Math.round(((b - a) / a) * 100)
  if (pct === 0) return "same length"
  return (pct > 0 ? "+" : "") + pct + "%"
}
