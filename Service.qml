import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property var state: Model.EMPTY
  property bool everParsed: false
  property string lastError: ""

  // Resolved from the plugin's own directory rather than PATH, so the widget
  // works the moment it is dropped in — no symlink step, and no chance of
  // picking up a different `wordsmith` that happens to be on PATH.
  readonly property string exe: String(Qt.resolvedUrl("bin/wordsmith")).replace(/^file:\/\//, "")

  readonly property string defaultMode: String(setting("defaultMode", "professional"))
  readonly property string model: String(setting("model", ""))
  readonly property string effort: String(setting("reasoningEffort", "low"))
  readonly property string source: String(setting("source", "auto"))
  readonly property bool autoCopy: setting("autoCopy", true) !== false
  readonly property bool notifyEnabled: setting("notify", true) !== false
  readonly property bool preserveQuoted: setting("preserveQuoted", true) !== false
  // Deliberately empty fallbacks: an unset setting must fall through to the
  // script's own default rather than a second copy of it here. shell.json does
  // not receive the manifest's defaultValue, so a non-empty fallback would
  // quietly become the effective default and drift.
  readonly property string defaultBackend: String(setting("backend", "codex"))
  readonly property string goModel: String(setting("goModel", ""))
  readonly property string ollamaModel: String(setting("ollamaModel", ""))
  readonly property string ollamaLocalModel: String(setting("ollamaLocalModel", ""))
  readonly property string claudeModel: String(setting("claudeModel", ""))
  readonly property int timeoutSec: intSetting("timeoutSec", 90, 15, 300)
  readonly property int maxChars: intSetting("maxChars", 20000, 500, 100000)

  readonly property string status: String(state.status || "idle")
  readonly property bool working: status === "working"
  readonly property bool done: status === "done"
  readonly property bool failed: status === "error"
  readonly property string original: String(state.original || "")
  readonly property string result: String(state.result || "")
  readonly property string modeLabel: String(state.modeLabel || "")
  readonly property string errorText: String(state.error || "")
  readonly property bool hasResult: result.trim().length > 0
  readonly property int quotedLines: parseInt(String(state.quotedLines || 0), 10) || 0
  readonly property int placeholderCount: parseInt(String(state.placeholders || 0), 10) || 0
  // Set when the captured text starts mid-sentence — see capture_note in bin/wordsmith.
  readonly property string captureNote: String(state.captureNote || "")
  readonly property var history: state.history || []
  // The SELECTION — the persisted toggle, resolved by the script from
  // wordsmith.json at every state read. Distinct from state.backend, which is
  // whatever the last run used: a one-off `run --backend X` from a terminal
  // must not flip the VIA row or what the next keypress runs.
  readonly property string backend: String(state.selectedBackend || defaultBackend)
  readonly property string backendLabel: String(state.selectedBackendLabel || Model.backendLabel(backend))
  readonly property var backends: Model.BACKENDS
  readonly property string activeModel: String(state.selectedModel || "")
  // What the last (or in-flight) run actually used — for the hero and history.
  readonly property string runBackendLabel: String(state.backendLabel || backendLabel)
  readonly property string storedInstruction: String(state.instruction || "")

  readonly property string summary: Model.summary(state)
  readonly property var modes: Model.MODES

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  // Every invocation carries the widget's settings, so shell.json stays
  // authoritative and wordsmith.json is only a fallback for terminal use.
  function flags() {
    // Note there is no "--model" here. That flag is the explicit override for
    // terminal use and would apply to whichever backend is active, so passing
    // the codex model through it made Claude and opencode ask their providers
    // for "gpt-5.6-terra". The widget's values are defaults, and go through the
    // --default-model-* flags below.
    return [
      // The backend the panel is *showing* is passed explicitly on every call.
      // Without it the script re-resolved the backend from wordsmith.json while
      // the panel read it from the state file, and when those two disagreed the
      // model list belonged to one backend and the label to another — the
      // "dropdown does not update" symptom. This also guarantees that what the
      // panel displays is what actually runs, and that picking a model writes it
      // under the backend you are looking at.
      "--backend", backend,
      "--effort", effort,
      "--source", source,
      "--timeout", String(timeoutSec),
      "--max-chars", String(maxChars),
      autoCopy ? "--copy" : "--no-copy",
      notifyEnabled ? "--notify" : "--no-notify",
      preserveQuoted ? "--quoted" : "--no-quoted",
      "--default-backend", defaultBackend
    ].concat(
      // Omitted when unset, so `wordsmith`'s defaults apply untouched.
      model.length        ? ["--default-model-codex",  model]        : [],
      goModel.length      ? ["--default-model-go",     goModel]      : [],
      ollamaModel.length  ? ["--default-model-ollama", ollamaModel]  : [],
      ollamaLocalModel.length ? ["--default-model-ollama-local", ollamaLocalModel] : [],
      claudeModel.length  ? ["--default-model-claude", claudeModel]  : []
    )
  }

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  function run(mode, instruction) {
    if (actionProcess.running) return
    var cmd = [exe, "run", "--mode", String(mode || defaultMode)]
    if (instruction !== undefined && String(instruction).length > 0)
      cmd = cmd.concat(["--instruction", String(instruction)])
    actionProcess.command = cmd.concat(flags())
    actionProcess.running = true
  }

  // Rerunning custom without carrying the instruction forward would silently
  // fall back to an error, so the last one is replayed from state.
  function rerun() {
    var m = state.mode || defaultMode
    run(m, m === "custom" ? storedInstruction : undefined)
  }

  function copy() { act(["copy"]) }
  function paste() { act(["paste"]) }
  function setBackend(id) { act(["backend", String(id)]) }
  function setModel(name) { act(["model", String(name)]) }

  // Saved custom instructions: persisted by the script in wordsmith.json,
  // fetched here only for rendering the panel's list.
  property var savedInstructions: []

  function refreshInstructions() {
    if (instructionsProcess.running) return
    instructionsProcess.running = true
  }
  function saveInstruction(text) { act(["instruction-add", String(text)]) }
  function removeInstruction(i) { act(["instruction-remove", String(i)]) }

  // The offered models come from the script rather than a second copy of the
  // list in QML, so there is one place to edit when a provider adds a model.
  property var modelOptions: []

  // Which backend the in-flight `models` call was launched for, and whether a
  // newer request arrived while it ran. Both are needed because the list is
  // fetched twice per switch: once right after the action (when `backend` is
  // still the old value, since the state re-read has not landed) and again when
  // `backend` actually changes. Without tracking, the first answer wins and the
  // list sits one backend behind every switch.
  property string _modelsFor: ""
  property bool _modelsPending: false

  function refreshModels() {
    if (modelsProcess.running) { _modelsPending = true; return }
    _modelsFor = backend
    modelsProcess.running = true
  }
  function copyIndex(i) { act(["copy", "--index", String(i)]) }
  function cancel() { act(["cancel"]) }
  function clear() { act(["clear"]) }

  // Holds the most recent request made while a previous one was still running.
  // Dropping it instead — the original behaviour — made a click on a VIA button
  // do nothing at all whenever an action happened to be in flight, which reads
  // as "the dropdown does not update".
  property var _queued: null

  function act(args) {
    if (actionProcess.running) { _queued = args; return }
    actionProcess.command = [exe].concat(args).concat(flags())
    actionProcess.running = true
  }

  onBackendChanged: refreshModels()

  Timer {
    // Two speeds on purpose. A rewrite lands in six to nine seconds, so while
    // one is in flight the panel needs to feel live; the rest of the time this
    // widget has nothing to poll for and should cost nothing.
    id: pollTimer
    interval: root.working ? 700 : 6000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: modelsProcess
    running: false
    command: [root.exe, "models"].concat(root.flags())  // --backend comes from flags()
    stdout: StdioCollector { id: modelsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = Model.parse(modelsStdout.text)
      // Accept only a list that belongs to the backend on screen. Showing a
      // stale list is worse than briefly showing the previous one, because
      // the dropdown would then offer models the active backend cannot serve.
      if (parsed && parsed.options && String(parsed.backend) === root.backend)
        root.modelOptions = parsed.options

      if (root._modelsPending || root._modelsFor !== root.backend) {
        root._modelsPending = false
        Qt.callLater(root.refreshModels)
      }
    }
  }

  Process {
    id: instructionsProcess
    running: false
    command: [root.exe, "instructions"].concat(root.flags())
    stdout: StdioCollector { id: instructionsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = Model.parse(instructionsStdout.text)
      if (parsed && parsed instanceof Array) root.savedInstructions = parsed
    }
  }
    }
  }

  Process {
    id: stateProcess
    running: false
    command: [root.exe, "state"]
    stdout: StdioCollector { id: stateStdout; waitForEnd: true }
    stderr: StdioCollector { id: stateStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = Model.parse(stateStdout.text)
      if (parsed) {
        root.everParsed = true
        root.lastError = ""
        root.state = parsed
      } else if (exitCode !== 0) {
        root.lastError = String(stateStderr.text || "").trim() || "wordsmith is not responding"
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      // `run` prints the freshly-started state, so adopt it immediately instead
      // of waiting for the next poll — otherwise the first click looks ignored.
      var parsed = Model.parse(actionStdout.text)
      if (parsed) {
        root.everParsed = true
        root.state = parsed
      }
      if (exitCode !== 0)
        root.lastError = String(actionStderr.text || "").trim() || "wordsmith command failed"
      root.refresh()
      root.refreshModels()
      root.refreshInstructions()
      if (root._queued) {
        var next = root._queued
        root._queued = null
        Qt.callLater(function() { root.act(next) })
      }
    }
  }

  Timer {
    id: watchdogTimer
    interval: 15000
    repeat: false
    running: true
    onTriggered: if (!root.everParsed) root.lastError = "wordsmith is not responding — run it in a terminal to see why"
  }
}
