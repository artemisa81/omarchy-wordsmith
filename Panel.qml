import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "artemisa81.wordsmith"
  ipcTarget: "artemisa81.wordsmith"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // No explicit fallback list here on purpose: JetBrainsMono Nerd Font has no
  // Thai block, but Qt substitutes per character at render time, so Thai and CJK
  // come out readable while Latin keeps the mono face. Verified with Thai text
  // in both the original and rewrite panes.

  // Instruction for Custom mode. Lives on the panel so it survives closing and
  // reopening, and is seeded from state so it survives a shell restart.
  property string customInstruction: ""
  property bool _instructionSeeded: false

  // Which result is on screen: 0 is the newest, higher indexes walk back through
  // history so tones can be compared without paying for another rewrite.
  property int viewIndex: 0

  readonly property var viewedEntry: viewIndex > 0 && viewIndex < wordsmith.history.length
    ? wordsmith.history[viewIndex] : null
  readonly property string viewedResult: viewedEntry ? String(viewedEntry.result || "") : wordsmith.result
  readonly property string viewedLabel: viewedEntry ? String(viewedEntry.modeLabel || "") : wordsmith.modeLabel

  readonly property int viewedPlaceholders: Model.placeholders(viewedResult).length
  // Only checked against the live original: an older history entry may have come
  // from a different selection, and a fact check on the wrong baseline is worse
  // than none.
  readonly property string droppedNote: viewIndex === 0
    ? Model.droppedNote(wordsmith.original, wordsmith.result) : ""

  function cssColor(c) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                   + Math.round(c.b * 255) + "," + c.a + ")"
  }

  readonly property color barIconColor: {
    if (wordsmith.failed || wordsmith.lastError !== "") return urgent
    if (wordsmith.working) return accent
    if (wordsmith.done) return wordsmith.placeholderCount > 0 ? urgent : barForeground
    return Qt.darker(barForeground, 1.9)
  }

  readonly property string barGlyph: {
    if (wordsmith.failed || wordsmith.lastError !== "") return "󰀦"
    if (wordsmith.working) return "󰑐"
    if (wordsmith.done) return wordsmith.placeholderCount > 0 ? "󰀦" : "󰄬"
    return "󰙏"
  }

  readonly property string tooltip: {
    if (wordsmith.lastError !== "") return "Wordsmith — " + wordsmith.lastError
    if (wordsmith.working) return "Wordsmith — " + wordsmith.summary + "…"
    if (wordsmith.failed) return "Wordsmith — " + wordsmith.errorText
    if (wordsmith.done) {
      var t = "Wordsmith — " + wordsmith.modeLabel + " ready"
      if (wordsmith.autoCopy) t += ", on the clipboard"
      if (wordsmith.placeholderCount > 0)
        t += "\n" + Model.placeholderNote(wordsmith.result)
      return t + "\nClick to review · " + Model.elapsed(wordsmith.state)
    }
    return "Wordsmith — select text, then SUPER+ALT+E"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: wordsmith
    settings: root.settings
  }

  // A finished rewrite always shows itself, rather than leaving you looking at
  // whichever history entry you were reading when it landed.
  Connections {
    target: wordsmith
    function onResultChanged() { root.viewIndex = 0 }
    function onStoredInstructionChanged() {
      if (!root._instructionSeeded && wordsmith.storedInstruction.length > 0) {
        root.customInstruction = wordsmith.storedInstruction
        root._instructionSeeded = true
      }
    }
  }

  onOpenedChanged: if (opened) {
    wordsmith.refresh()
    wordsmith.refreshModels()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget

    // `go` is what the keybinding calls: no argument, so the Hyprland side
    // needs no quoting, and the mode comes from the widget's own settings.
    function go(): void { wordsmith.run(wordsmith.defaultMode); root.open() }

    function rewrite(mode: string): void {
      wordsmith.run(mode && mode.length > 0 ? mode : wordsmith.defaultMode)
      root.open()
    }
    function polish(): void { wordsmith.run("professional"); root.open() }
    function shorten(): void { wordsmith.run("shorten"); root.open() }
    function soften(): void { wordsmith.run("soften"); root.open() }
    function firm(): void { wordsmith.run("firm"); root.open() }
    function custom(instruction: string): void {
      if (instruction && instruction.length > 0) root.customInstruction = instruction
      wordsmith.run("custom", root.customInstruction)
      root.open()
    }

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function copy(): void { wordsmith.copy() }
    function cancel(): void { wordsmith.cancel() }
    function refresh(): string { wordsmith.refresh(); return "ok" }
    function status(): string { return wordsmith.summary }
    function result(): string { return wordsmith.result }
    function placeholders(): string { return String(wordsmith.placeholderCount) }

    // Same call the VIA buttons make, exposed so the backend switch can be
    // driven and inspected from a terminal.
    function via(name: string): void { wordsmith.setBackend(name) }
    function pickModel(name: string): void { wordsmith.setModel(name) }
    function view(): string {
      return "backend=" + wordsmith.backend
        + " activeModel=" + wordsmith.activeModel
        + " options=" + JSON.stringify(wordsmith.modelOptions)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    foreground: root.barIconColor
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      // Right-click reruns the last mode — the "not quite, try again" gesture.
      if (buttonCode === Qt.RightButton) wordsmith.rerun()
      else if (buttonCode === Qt.MiddleButton) wordsmith.copy()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = String(t).toLowerCase()
        if (k === "1") wordsmith.run("professional")
        else if (k === "2") wordsmith.run("shorten")
        else if (k === "3") wordsmith.run("soften")
        else if (k === "4") wordsmith.run("firm")
        else if (k === "5") instructionField.forceActiveFocus()
        else if (k === "c") wordsmith.copyIndex(root.viewIndex)
        else if (k === "r") wordsmith.rerun()
        else if (k === "x") wordsmith.working ? wordsmith.cancel() : wordsmith.clear()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "Wordsmith"
          meta: wordsmith.working ? wordsmith.summary + "…" : wordsmith.summary
          detail: {
            if (wordsmith.working) return "on " + wordsmith.runBackendLabel
            if (wordsmith.done) return Model.elapsed(wordsmith.state) + " · " + Model.deltaLabel(wordsmith.state)
            if (wordsmith.failed) return "failed"
            return "select text, then SUPER+ALT+E"
          }
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: wordsmith.status === "idle" ? 0.5 : 1.0
          iconComponent: Component {
            Text {
              text: root.barGlyph
              color: wordsmith.status === "idle" ? root.dim : root.barIconColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: wordsmith.working ? "󰅙" : "󰆏"
              enabled: wordsmith.working || root.viewedResult.length > 0
              foreground: hero.foreground
              fontFamily: hero.fontFamily
              tooltipText: wordsmith.working ? "Cancel" : "Copy the rewrite"
              onClicked: wordsmith.working ? wordsmith.cancel() : wordsmith.copyIndex(root.viewIndex)
            }
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: {
            if (wordsmith.lastError !== "") return wordsmith.lastError
            if (wordsmith.failed) return wordsmith.errorText
            if (wordsmith.status === "idle")
              return "Select a paragraph anywhere — an Outlook draft, a reply, a chat box — then press SUPER+ALT+E. The rewrite lands here for you to read before you paste it."
            return ""
          }
          color: (wordsmith.lastError !== "" || wordsmith.failed) ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        // Which subscription answers. Switching writes the choice to
        // wordsmith.json through the script, so it outlives the panel and the
        // shell, and the script reports back what actually resolved.
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "VIA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: wordsmith.backends
              Button {
                required property var modelData
                bordered: true
                selected: wordsmith.backend === modelData.id
                text: modelData.label
                tooltipText: modelData.hint
                enabled: !wordsmith.working
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: wordsmith.setBackend(modelData.id)
              }
            }
          }

          // Model choice for whichever backend is active. Switching persists
          // through the script, so it survives the panel and the shell.
          Dropdown {
            width: parent.width
            showLabel: false
            options: wordsmith.modelOptions
            value: wordsmith.activeModel
            enabled: !wordsmith.working && wordsmith.modelOptions.length > 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            // Guarded because a Dropdown emits changed() while it settles on an
            // initial value, and an unguarded handler wrote a model into
            // wordsmith.json on every panel open without anyone choosing one.
            onChanged: function(v) {
              if (!root.opened) return
              if (!v || wordsmith.activeModel === "") return
              if (v === wordsmith.activeModel) return
              if (wordsmith.modelOptions.indexOf(v) === -1) return
              wordsmith.setModel(v)
            }
          }

          // Worth stating at the point of switching, not buried in a README:
          // codex and claude keep the text off the disk; the opencode ones do not.
          Text {
            visible: !Model.backendIsEphemeral(wordsmith.backend)
            width: parent.width
            text: "opencode records prompts in its own database — Wordsmith deletes the session after each rewrite, with retries."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "REWRITE AS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Runs against whatever is selected right now. Picking a different
          // mode after a result is back is the intended way to compare tones:
          // each click re-reads the selection, which is still sitting there.
          Repeater {
            model: wordsmith.modes
            Button {
              required property var modelData
              required property int index
              width: column.width
              leftAlign: true
              bordered: true
              text: (index + 1) + "  " + modelData.label
              tooltipText: modelData.hint
              selected: wordsmith.state.mode === modelData.id
              enabled: !wordsmith.working
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: {
                if (modelData.id === "custom") {
                  if (root.customInstruction.trim().length === 0) instructionField.forceActiveFocus()
                  else wordsmith.run("custom", root.customInstruction)
                } else {
                  wordsmith.run(modelData.id)
                }
              }
            }
          }

          // The four fixed modes cannot express "keep the bullets but make it
          // formal", which is most of what you actually want on a given day.
          TextField {
            id: instructionField
            width: parent.width
            placeholderText: "5  Your own instruction, then Enter"
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            enabled: !wordsmith.working
            Component.onCompleted: text = root.customInstruction
            onTextChanged: root.customInstruction = text
            onAccepted: if (text.trim().length > 0) wordsmith.run("custom", text)
          }
        }

        PanelSeparator {
          visible: wordsmith.original !== ""
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: wordsmith.original !== ""

          PanelSectionHeader {
            text: "ORIGINAL · " + Model.charCount(wordsmith.state.chars) + " " + Model.sourceLabel(wordsmith.state)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: Model.preview(wordsmith.original, 220)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          // Reassurance that a colleague's quoted mail was not reworded — the
          // model never saw it, and it is reattached byte for byte.
          Text {
            visible: wordsmith.quotedLines > 0
            width: parent.width
            text: "󰅌  " + Model.quotedNote(wordsmith.state) + " — the quoted thread was not sent to the model"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator {
          visible: root.viewedResult.length > 0
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.viewedResult.length > 0

          PanelSectionHeader {
            text: (root.viewIndex === 0
                    ? "REWRITE"
                    : "EARLIER · " + root.viewedLabel.toUpperCase()
                      + (root.viewedEntry && root.viewedEntry.backendLabel ? " · " + root.viewedEntry.backendLabel : ""))
              + " · " + Model.charCount(root.viewedResult.length)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // The thing the user asked for: anything they still have to fill in is
          // bracketed by the model and painted in the urgent colour here, so it
          // cannot be skimmed past on the way to Ctrl+V.
          Text {
            visible: root.viewedPlaceholders > 0
            width: parent.width
            text: "󰀦  " + Model.placeholderNote(root.viewedResult)
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.droppedNote !== ""
            width: parent.width
            text: "󰀦  " + root.droppedNote
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Selectable and scrollable rather than a flat label: sometimes you
          // only want one fixed sentence out of it, not the whole thing.
          Flickable {
            width: parent.width
            height: Math.min(resultText.implicitHeight, Style.space(230))
            contentWidth: width
            contentHeight: resultText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
              id: resultText
              width: parent.width
              textFormat: TextEdit.RichText
              text: Model.highlightHtml(root.viewedResult, root.cssColor(root.foreground), root.cssColor(root.urgent))
              readOnly: true
              selectByMouse: true
              wrapMode: TextEdit.WordWrap
              selectionColor: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "󰆏  Copy"
              tooltipText: root.viewedPlaceholders > 0
                ? "Copies with the [placeholders] still in — complete them in your draft"
                : "Put the rewrite on the clipboard, then Ctrl+V into your draft"
              bordered: true
              foreground: root.viewedPlaceholders > 0 ? root.urgent : root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: wordsmith.copyIndex(root.viewIndex)
            }

            Button {
              text: "󰑐  Again"
              tooltipText: "Rerun the same mode on the current selection"
              bordered: true
              enabled: !wordsmith.working
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: wordsmith.rerun()
            }

            Button {
              text: "󰅙  Clear"
              tooltipText: "Forget this text — it is held in tmpfs until then"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: { root.viewIndex = 0; wordsmith.clear() }
            }
          }
        }

        // Comparing tones used to mean losing the previous answer. These recall
        // earlier results from tmpfs — no second model call.
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: wordsmith.history.length > 1

          PanelSectionHeader {
            text: "EARLIER RESULTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: wordsmith.history
              Button {
                required property var modelData
                required property int index
                bordered: true
                selected: root.viewIndex === index
                text: index === 0 ? "current" : Model.backendLabel(modelData.backend)
                tooltipText: String(modelData.modeLabel || "") + " · "
                  + Model.charCount(modelData.resultChars)
                  + (modelData.placeholders > 0 ? " · " + modelData.placeholders + " placeholder(s)" : "")
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.viewIndex = index
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // The keybindings, on the panel itself rather than only in SUPER+K.
        // Two rows: the global hotkeys that work anywhere, then the keys that
        // only exist while this panel is open.
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: "󰌌  SUPER+ALT+E rewrite selection · SUPER+ALT+W this panel"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "in panel: 1–5 mode · c copy · r again · x clear · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          width: parent.width
          text: Model.privacyNote(wordsmith.backend)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
