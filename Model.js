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

// ---------------------------------------------------------- placeholders -----

// The model is told to mark anything it could not fill in as [like this]. That
// convention only earns its keep if the marks are impossible to miss on the way
// past, so the panel renders them in the urgent colour rather than as ordinary
// prose. Plain-text copy keeps the brackets, which is what survives into the
// mail as the reminder.
var PLACEHOLDER_RE = /\[[^\][]{1,60}\]/g

function placeholders(text) {
  var m = String(text || "").match(PLACEHOLDER_RE)
  return m ? m : []
}

function escapeHtml(s) {
  return String(s === undefined || s === null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

// Escaping happens before the bracket pass so a literal "<" in the mail cannot
// smuggle markup in, and the bracket characters survive escaping untouched.
function highlightHtml(text, bodyColor, markColor) {
  var html = escapeHtml(text)
  html = html.replace(PLACEHOLDER_RE, function(match) {
    return '<span style="color:' + markColor + '; font-weight:bold">' + match + '</span>'
  })
  html = html.replace(/\r\n/g, "\n").replace(/\n/g, "<br/>")
  return '<span style="color:' + bodyColor + '; white-space:pre-wrap">' + html + '</span>'
}

function placeholderNote(text) {
  var n = placeholders(text).length
  if (n === 0) return ""
  return n === 1
    ? "1 placeholder to complete before sending"
    : n + " placeholders to complete before sending"
}

// ---------------------------------------------------------- dropped facts ----

// The expensive failure here is not clumsy prose, it is a figure quietly going
// missing — row 42 becoming "the relevant row", or an invoice number vanishing.
//
// Deliberately narrow: numbers of two or more digits, percentages, money,
// emails and URLs. Single digits are excluded because a rewrite spelling "3" as
// "three" is correct and would otherwise cry wolf, and names are excluded
// because they are rephrased legitimately all the time. A check that fires on
// nothing real gets ignored, which is worse than not having one.
function factTokens(text) {
  var s = String(text || "")
  var out = []
  var res = [
    /https?:\/\/[^\s<>"')\]]+/g,
    /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g,
    /[$€£¥฿]\s?\d[\d.,]*/g,
    /\b\d[\d.,]*\s?%/g,
    /\b\d{2}[\d.,:\/-]*\b/g
  ]
  for (var i = 0; i < res.length; i++) {
    var m = s.match(res[i])
    if (m) for (var j = 0; j < m.length; j++) {
      var t = String(m[j]).replace(/[.,;:]+$/, "")
      if (t.length > 0 && out.indexOf(t) === -1) out.push(t)
    }
  }
  // The patterns overlap on purpose — "12%" and "$1,200" are also matched by the
  // bare-number pattern. Report the richer token only, or the warning reads
  // "12%, 12" and looks broken.
  return out.filter(function(t) {
    return !out.some(function(u) { return u !== t && u.indexOf(t) !== -1 })
  })
}

function digitsOf(s) { return String(s).replace(/[^\d]/g, "") }

function droppedFacts(original, result) {
  if (!original || !result) return []
  var toks = factTokens(original)
  var res = String(result)
  var resDigits = digitsOf(res)
  var missing = []
  for (var i = 0; i < toks.length; i++) {
    var t = toks[i]
    if (res.indexOf(t) !== -1) continue
    // "1,000" rewritten as "1000" is not a dropped fact.
    var d = digitsOf(t)
    if (d.length > 0 && resDigits.indexOf(d) !== -1) continue
    missing.push(t)
  }
  return missing
}

function droppedNote(original, result) {
  var m = droppedFacts(original, result)
  if (m.length === 0) return ""
  var shown = m.slice(0, 4).join(", ")
  return "Not found in the rewrite: " + shown + (m.length > 4 ? " (+" + (m.length - 4) + " more)" : "")
}

// -------------------------------------------------------------- history ------

function historyLabel(entry, index) {
  if (!entry) return ""
  var label = String(entry.modeLabel || entry.mode || "rewrite")
  if (entry.mode === "custom") label = "Custom"
  return (index === 0 ? "current" : label)
}

function quotedNote(state) {
  var n = Number(state.quotedLines)
  if (!isFinite(n) || n <= 0) return ""
  return n + " quoted line" + (n === 1 ? "" : "s") + " left untouched"
}

// -------------------------------------------------------------- backends -----

// All three are subscriptions the user already pays for, not metered API keys.
// The privacy note is not cosmetic: codex runs --ephemeral and writes nothing,
// while opencode records every prompt in its own database — wordsmith deletes
// the session afterwards, but there is a window, and that is worth saying out
// loud next to the button that switches to it.
var BACKENDS = [
  { id: "codex",        label: "ChatGPT",      hint: "codex — ephemeral, read-only sandbox, nothing written to disk" },
  { id: "opencode-go",  label: "OpenCode Go",  hint: "via opencode — prompt hits its database, session deleted after" },
  { id: "ollama-cloud", label: "Ollama Cloud", hint: "via opencode — prompt hits its database, session deleted after" },
  { id: "claude",       label: "Claude",       hint: "claude CLI directly, not through opencode — no transcript kept" }
]

function backendLabel(id) {
  for (var i = 0; i < BACKENDS.length; i++)
    if (BACKENDS[i].id === id) return BACKENDS[i].label
  return id || ""
}

// Only codex keeps the text off disk entirely; the others need the session
// cleanup to have run.
function backendIsEphemeral(id) {
  var v = String(id)
  return v === "codex" || v === "claude"
}

// The footer used to hardcode codex's guarantees. With four backends the
// honest sentence differs per backend, and this is the one place the user reads
// before pasting, so it has to track what actually ran.
function privacyNote(backend) {
  var base = "Text is held in tmpfs, never on disk. "
  switch (String(backend)) {
    case "codex":
      return base + "Codex runs with --ephemeral, so it keeps no transcript — but the words go to OpenAI under your ChatGPT plan."
    case "claude":
      return base + "claude -p keeps no transcript — but the words go to Anthropic under your Claude plan."
    case "opencode-go":
      return base + "opencode records the prompt in its own database and Wordsmith deletes the session afterwards — the words go to OpenCode Go."
    case "ollama-cloud":
      return base + "opencode records the prompt in its own database and Wordsmith deletes the session afterwards — the words go to Ollama Cloud."
    default:
      return base + "The words leave this machine to whichever backend is selected."
  }
}
