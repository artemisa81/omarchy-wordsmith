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
  readonly property string model: String(setting("model", "gpt-5.6-terra"))
  readonly property string effort: String(setting("reasoningEffort", "low"))
  readonly property string source: String(setting("source", "auto"))
  readonly property bool autoCopy: setting("autoCopy", true) !== false
  readonly property bool notifyEnabled: setting("notify", true) !== false
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
    return [
      "--model", model,
      "--effort", effort,
      "--source", source,
      "--timeout", String(timeoutSec),
      "--max-chars", String(maxChars),
      autoCopy ? "--copy" : "--no-copy",
      notifyEnabled ? "--notify" : "--no-notify"
    ]
  }

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
  }

  function run(mode) {
    if (actionProcess.running) return
    actionProcess.command = [exe, "run", "--mode", String(mode || defaultMode)].concat(flags())
    actionProcess.running = true
  }

  function rerun() { run(state.mode || defaultMode) }
  function copy() { act(["copy"]) }
  function cancel() { act(["cancel"]) }
  function clear() { act(["clear"]) }

  function act(args) {
    if (actionProcess.running) return
    actionProcess.command = [exe].concat(args).concat(flags())
    actionProcess.running = true
  }

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
