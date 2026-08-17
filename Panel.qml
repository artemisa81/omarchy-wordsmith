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

  // Idle is the common case for this widget — it spends most of the day with
  // nothing to say — so it recedes rather than sitting there at full strength.
  readonly property color barIconColor: {
    if (wordsmith.failed || wordsmith.lastError !== "") return urgent
    if (wordsmith.working) return accent
    if (wordsmith.done) return barForeground
    return Qt.darker(barForeground, 1.9)
  }

  readonly property string barGlyph: {
    if (wordsmith.failed || wordsmith.lastError !== "") return "󰀦"
    if (wordsmith.working) return "󰑐"
    if (wordsmith.done) return "󰄬"
    return "󰙏"
  }

  readonly property string tooltip: {
    if (wordsmith.lastError !== "") return "Wordsmith — " + wordsmith.lastError
    if (wordsmith.working) return "Wordsmith — " + wordsmith.summary + "…"
    if (wordsmith.failed) return "Wordsmith — " + wordsmith.errorText
    if (wordsmith.done)
      return "Wordsmith — " + wordsmith.modeLabel + " ready"
        + (wordsmith.autoCopy ? ", on the clipboard" : "")
        + "\nClick to review · " + Model.elapsed(wordsmith.state)
    return "Wordsmith — select text, then SUPER+ALT+E"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: wordsmith
    settings: root.settings
  }

  onOpenedChanged: if (opened) {
    wordsmith.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget

    // What the Hyprland keybindings call. `rewrite` deliberately opens the
    // panel too: the whole point of the review flow is that you see the result
    // before it goes anywhere near your draft.
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
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    foreground: root.barIconColor
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      // Right-click reruns the last mode — the "that wasn't quite it, try
      // again" gesture, without opening anything.
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
        else if (k === "c") wordsmith.copy()
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
            if (wordsmith.working) return "on your ChatGPT plan"
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
              color: root.barIconColor === Qt.darker(root.barForeground, 1.9) ? root.dim : root.barIconColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: wordsmith.working ? "󰅙" : "󰆏"
              enabled: wordsmith.working || wordsmith.hasResult
              foreground: hero.foreground
              fontFamily: hero.fontFamily
              tooltipText: wordsmith.working ? "Cancel" : "Copy the rewrite"
              onClicked: wordsmith.working ? wordsmith.cancel() : wordsmith.copy()
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
              onClicked: wordsmith.run(modelData.id)
            }
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
        }

        PanelSeparator {
          visible: wordsmith.hasResult
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: wordsmith.hasResult

          PanelSectionHeader {
            text: "REWRITE · " + Model.charCount(wordsmith.state.resultChars)
            foreground: root.foreground
            fontFamily: root.fontFamily
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
              text: wordsmith.result
              readOnly: true
              selectByMouse: true
              wrapMode: TextEdit.WordWrap
              color: root.foreground
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
              tooltipText: "Put the rewrite on the clipboard, then Ctrl+V into your draft"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: wordsmith.copy()
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
              onClicked: wordsmith.clear()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Text {
          width: parent.width
          text: "1–4 pick a mode · c copy · r again · x clear. "
            + "Text is held in tmpfs and Codex runs with --ephemeral, so nothing is written to disk — but the words do go to OpenAI under your ChatGPT plan."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
