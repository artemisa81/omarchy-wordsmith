#!/usr/bin/env node
// Unit tests for Model.js, the pure-JS half of the widget. QML cannot be
// exercised from a shell, but Model.js is exactly the part that decides what
// the panel shows — placeholder highlighting, the dropped-fact check, the
// privacy sentence — so it is worth testing without a compositor.
//
//   node tests/model-test.js
//
// Exits non-zero if any assertion fails.

'use strict'

const fs = require('fs')
const path = require('path')
const vm = require('vm')

const file = path.join(__dirname, '..', 'Model.js')
const source = fs.readFileSync(file, 'utf8').replace(/^\.pragma library\s*$/m, '')

// The file is a plain script of `var`s and function declarations; evaluate it
// in a fresh context and hand back the functions we want to poke at.
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(
  source +
    '\n;this.__M = { parse, summary, elapsed, sourceLabel, charCount, preview,'
    + ' deltaLabel, placeholders, escapeHtml, highlightHtml, placeholderNote,'
    + ' factTokens, droppedFacts, droppedNames, droppedNote, quotedNote,'
    + ' backendLabel, backendIsEphemeral, privacyNote, modeLabel, historyLabel, MODES, BACKENDS };',
  sandbox
)
const M = sandbox.__M

let pass = 0
let fail = 0

function eq(name, got, want) {
  if (got === want) { pass++ }
  else { fail++; console.error('FAIL ' + name + ': got [' + JSON.stringify(got) + '] want [' + JSON.stringify(want) + ']') }
}

function ok(name, cond) {
  if (cond) { pass++ }
  else { fail++; console.error('FAIL ' + name) }
}

function has(name, haystack, needle) {
  if (String(haystack).indexOf(needle) !== -1) { pass++ }
  else { fail++; console.error('FAIL ' + name + ': ' + JSON.stringify(haystack) + ' misses ' + JSON.stringify(needle)) }
}

// ------------------------------------------------------------------ parse ----
eq('parse rejects bad JSON', M.parse('nope'), null)
eq('parse rejects a JSON scalar', M.parse('42'), null)
eq('parse reads an object', M.parse('{"a":1}').a, 1)

// -------------------------------------------------------------- formatting ----
eq('charCount under 1000', M.charCount(999), '999 chars')
eq('charCount above 1000', M.charCount(1500), '1.5k chars')
eq('charCount zero is blank', M.charCount(0), '')
eq('elapsed', M.elapsed({ elapsedMs: 6100 }), '6.1s')
eq('elapsed zero is blank', M.elapsed({ elapsedMs: 0 }), '')
eq('delta shortens', M.deltaLabel({ chars: 100, resultChars: 80 }), '-20%')
eq('delta same', M.deltaLabel({ chars: 100, resultChars: 100 }), 'same length')
eq('source labels', M.sourceLabel({ source: 'selection' }), 'from your selection')
eq('summary working', M.summary({ status: 'working', modeLabel: 'Shorten' }), 'rewriting — Shorten')
eq('summary done', M.summary({ status: 'done', modeLabel: 'Soften' }), 'Soften ready')

// ------------------------------------------------------------- placeholders ----
eq('placeholders finds two', M.placeholders('by [date] please [name or team]').length, 2)
eq('placeholders finds none', M.placeholders('nothing marked here').length, 0)
eq('placeholder note singular', M.placeholderNote('[date]'), '1 placeholder to complete before sending')
eq('placeholder note plural', M.placeholderNote('[a] and [b]'), '2 placeholders to complete before sending')

eq('escapeHtml handles markup', M.escapeHtml('a"b<c>'), 'a&quot;b&lt;c&gt;')

const html = M.highlightHtml('<b>bold</b> by [date]\nsecond', '#111', '#f00')
has('highlight escapes the body', html, '&lt;b&gt;bold&lt;/b&gt;')
has('highlight does not leave raw markup', html.indexOf('<b>'), -1)
has('highlight marks placeholders', html, '<span style="color:#f00; font-weight:bold">[date]</span>')
has('highlight converts newlines', html, '<br/>')

// ----------------------------------------------------------- dropped facts ----
const missing = M.droppedFacts('Save $20K by row 42', 'Save the money by the row')
has('dropped money is caught', missing.join(','), '$20')
has('dropped number is caught', missing.join(','), '42')
eq('reformatted thousands are not a drop', M.droppedFacts('Total 1,000 units', 'Total 1000 units').length, 0)
eq('single digits are not checked', M.droppedFacts('Step 3 of 3', 'the last step').length, 0)
eq('richer token wins over its subset', M.factTokens('12% of 12').join(','), '12%')
eq('kept numbers are not reported', M.droppedFacts('Row 42 stays', 'Row 42 stays').length, 0)

// ----------------------------------------------------------- dropped names ----
const names = M.droppedNames('We asked Carol Danvers to confirm.', 'We asked the team to confirm.')
has('a vanished name is caught', names.join(','), 'Carol Danvers')
eq('a kept name is not reported', M.droppedNames('Carol Danvers replied', 'Carol replied').length, 0)

// droppedNote: names are opt-in, facts are always on.
eq('droppedNote ignores names by default', M.droppedNote('We asked Carol Danvers to confirm.', 'We asked the team to confirm.', false), '')
has('droppedNote includes names when asked', M.droppedNote('We asked Carol Danvers to confirm.', 'We asked the team to confirm.', true), 'Carol Danvers')
has('droppedNote always reports a missing figure', M.droppedNote('Invoice 88231 attached', 'The invoice is attached', false), '88231')
eq('droppedNote is blank when nothing is missing', M.droppedNote('Hello there', 'Hello there', true), '')

// --------------------------------------------------------------- backends ----
eq('backend label', M.backendLabel('codex'), 'ChatGPT')
ok('codex is ephemeral', M.backendIsEphemeral('codex'))
ok('opencode-go is not ephemeral', !M.backendIsEphemeral('opencode-go'))
has('local privacy note names the daemon', M.privacyNote('ollama-local'), 'localhost:11434')

// ------------------------------------------------------------------ quoted ----
eq('quoted note singular', M.quotedNote({ quotedLines: 1 }), '1 quoted line left untouched')
eq('quoted note plural', M.quotedNote({ quotedLines: 13 }), '13 quoted lines left untouched')

// ------------------------------------------------------------------ shapes ----
eq('four fixed modes', M.MODES.length, 4)
eq('five backends', M.BACKENDS.length, 5)

console.log('model-test: pass=' + pass + ' fail=' + fail)
process.exit(fail === 0 ? 0 : 1)
