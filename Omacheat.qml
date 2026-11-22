import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Omacheat.js" as Omacheat

// Friendlier keybindings help: shortcuts grouped by purpose, drawn as keycaps,
// searchable, and individually switchable off.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property var rows: []
  property var disabledList: []
  property var customList: []
  property string printedText: ""

  // Add-shortcut form
  property bool formOpen: false
  property string formDesc: ""
  property string formCmd: ""
  property string formKey: ""
  property var formMods: ["SUPER"]
  property string formCategory: "apps"
  property string formMessage: ""
  property var columns: []
  property bool closeOnUse: true
  property int disabledCount: 0
  property int totalCount: 0

  readonly property string applyScript: Qt.resolvedUrl("bin/omacheat-apply").toString().replace(/^file:\/\//, "")

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color accent: Color.menu.selectedText
  property color rowHover: Color.menu.selectedBackground
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.space(12))

  property int cardWidth: Math.min(Style.space(1600), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(780), panel.height - Style.gapsOut * 2)
  property int columnCount: cardWidth >= 1300 ? 3 : (cardWidth >= 640 ? 2 : 1)
  property int columnGap: Style.space(28)
  property int columnWidth: Math.floor((cardWidth - contentMargin * 2 - columnGap * (columnCount - 1)) / columnCount)

  onColumnCountChanged: rebuild()

  // Tell the Hyprland-side key listener (see bin/omacheat-apply) whether we are open.
  onOpenedChanged: {
    applyQueue.push([root.applyScript, "watch", root.opened ? "on" : "off"])
    root.runNextApply()
  }

  function open(payloadJson) {
    root.opened = true
    root.formOpen = false
    flick.contentY = 0
    root.filterText = ""
    settingsProc.running = false
    settingsProc.running = true
    listProc.running = false
    listProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "heelgueta.omacheat")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function rebuild() {
    var cats = Omacheat.categories(root.rows, root.filterText)
    root.columns = Omacheat.toColumns(cats, root.columnCount)
    var off = 0, total = 0
    for (var i = 0; i < root.rows.length; i++) {
      total++
      if (root.rows[i].disabled) off++
    }
    root.totalCount = total
    root.disabledCount = off
  }

  function setFilter(text) {
    root.filterText = text
    flick.contentY = 0
    root.rebuild()
  }

  // Switch a row's binding(s) off or on. Reflected immediately; the script then
  // rewrites ~/.config/hypr/omacheat-disabled.lua and reloads Hyprland.
  function setRowDisabled(row, off) {
    if (row.custom) return
    var ids = {}
    for (var i = 0; i < row.items.length; i++) ids[Omacheat.itemId(row.items[i].mods, row.items[i].desc)] = true
    var kept = root.disabledList.filter(function(e) { return !ids[Omacheat.itemId(e.mods, e.desc)] })
    root.disabledList = off ? kept.concat(row.items) : kept
    for (var j = 0; j < root.rows.length; j++) {
      var r = root.rows[j]
      if (r.items.some(function(it) { return ids[Omacheat.itemId(it.mods, it.desc)] })) r.disabled = off
    }
    root.rebuild()
    applyQueue.push([root.applyScript, "set", off ? "off" : "on", JSON.stringify(row.items)])
    root.runNextApply()
  }

  function openForm() {
    root.formDesc = ""
    root.formCmd = ""
    root.formKey = ""
    root.formMods = ["SUPER"]
    root.formCategory = "apps"
    root.formMessage = ""
    root.formOpen = true
    Qt.callLater(function() { nameInput.forceActiveFocus() })
  }

  function closeForm() {
    root.formOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function toggleFormMod(mod) {
    var has = root.formMods.indexOf(mod) >= 0
    root.formMods = has ? root.formMods.filter(function(m) { return m !== mod }) : root.formMods.concat([mod])
  }

  function formClash() {
    return root.formKey ? Omacheat.conflict(root.rows, root.formMods, root.formKey) : null
  }

  function saveForm() {
    var form = { desc: root.formDesc, cmd: root.formCmd, key: root.formKey, mods: root.formMods }
    var problem = Omacheat.validate(form)
    if (problem) { root.formMessage = problem; return }
    var order = ["SUPER", "CTRL", "ALT", "SHIFT"]
    var entry = {
      mods: order.filter(function(m) { return root.formMods.indexOf(m) >= 0 }),
      key: root.formKey, desc: root.formDesc.trim(), cmd: root.formCmd.trim(), category: root.formCategory
    }
    root.customList = root.customList.filter(function(c) { return Omacheat.conflict([{ items: [c] }], entry.mods, entry.key) === null }).concat([entry])
    root.rows = Omacheat.parse(root.printedText, root.disabledList, root.customList)
    root.rebuild()
    applyQueue.push([root.applyScript, "add", JSON.stringify(entry)])
    root.runNextApply()
    root.closeForm()
  }

  function removeCustom(row) {
    var item = row.items[0]
    root.customList = root.customList.filter(function(c) { return Omacheat.conflict([{ items: [c] }], item.mods, item.key) === null })
    root.printedText = Omacheat.dropBinding(root.printedText, item.mods, item.key)
    root.rows = Omacheat.parse(root.printedText, root.disabledList, root.customList)
    root.rebuild()
    applyQueue.push([root.applyScript, "remove", JSON.stringify(item)])
    root.runNextApply()
  }

  property var applyQueue: []
  function runNextApply() {
    if (applyProc.running || root.applyQueue.length === 0) return
    applyProc.command = root.applyQueue.shift()
    applyProc.running = true
  }

  Process {
    id: applyProc
    onRunningChanged: {
      if (running) return
      var cmd = command || []
      if (cmd[1] === "watch" && cmd[2] === "on") {
        // The key report file exists now; (re)attach the watcher to it.
        keysFile.path = ""
        keysFile.path = root.keysPath
      }
      root.runNextApply()
    }
  }

  // ---- "close after using a shortcut" -------------------------------------------------
  // Hyprland swallows the key that completes a bound shortcut, so we never see it. Its
  // listener reports the scancode of such keys to a file; if we did not receive that key
  // ourselves a moment later, it was a shortcut that fired (an unbound combo reaches us).
  readonly property string keysPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omacheat-keys"
  property var seenScans: ({})
  property string lastReport: ""
  property int pendingCode: -1

  function noteKey(event) { root.seenScans[event.nativeScanCode] = Date.now() }

  function onKeyReport(text) {
    var t = String(text || "").trim()
    if (t === "" || t === root.lastReport) return
    root.lastReport = t
    var parts = t.split(/\s+/)
    root.pendingCode = parseInt(parts[2])
    reportTimer.restart()
  }

  Timer {
    id: reportTimer
    interval: 150
    onTriggered: {
      var seen = root.seenScans[root.pendingCode]
      var received = seen !== undefined && Date.now() - seen < 700
      if (!received && root.opened && root.closeOnUse && !root.formOpen) root.dismiss()
    }
  }

  FileView {
    id: keysFile
    watchChanges: root.opened
    onFileChanged: reload()
    onLoaded: root.onKeyReport(text())
  }

  Process {
    id: settingsProc
    command: [root.applyScript, "settings"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.closeOnUse = JSON.parse(text).closeOnUse !== false } catch (e) { root.closeOnUse = true }
      }
    }
  }

  function setCloseOnUse(value) {
    root.closeOnUse = value
    applyQueue.push([root.applyScript, "setting", "closeOnUse", value ? "true" : "false"])
    root.runNextApply()
  }

  Process {
    id: listProc
    command: [root.applyScript, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.disabledList = JSON.parse(text) } catch (e) { root.disabledList = [] }
        customProc.running = false
        customProc.running = true
      }
    }
  }

  Process {
    id: customProc
    command: [root.applyScript, "custom"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.customList = JSON.parse(text) } catch (e) { root.customList = [] }
        printProc.running = false
        printProc.running = true
      }
    }
  }

  Process {
    id: printProc
    command: ["omarchy-menu-keybindings", "--print"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.printedText = text
        root.rows = Omacheat.parse(text, root.disabledList, root.customList)
        root.rebuild()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-omacheat"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var step = root.rowHeight * 3
          root.noteKey(event)
          if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N) {
            root.openForm()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + step)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            flick.contentY = Math.max(0, flick.contentY - step)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + flick.height * 0.9)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            flick.contentY = Math.max(0, flick.contentY - flick.height * 0.9)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: addButton.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search shortcuts — try “window”, “screenshot”, “workspace”…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Rectangle {
            id: addButton
            anchors.right: counter.left
            anchors.rightMargin: root.contentSpacing * 2
            anchors.verticalCenter: parent.verticalCenter
            width: addLabel.implicitWidth + Style.space(20)
            height: Style.font.body + Style.space(12)
            radius: Style.space(5)
            color: addMouse.containsMouse ? root.rowHover : "transparent"
            border.width: 1
            border.color: Util.alpha(root.accent, 0.6)
            Text {
              id: addLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "+ Add shortcut"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: addMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openForm()
            }
          }

          Text {
            id: counter
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.totalCount + " shortcuts" + (root.disabledCount ? " · " + root.disabledCount + " switched off" : "")
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle { width: parent.width; height: 1; color: Util.alpha(root.foreground, 0.12) }

        Flickable {
          id: flick
          width: parent.width
          height: parent.height - root.headerHeight - footer.height - root.contentSpacing * 2 - 1
          clip: true
          contentWidth: width
          contentHeight: columnsRow.height
          boundsBehavior: Flickable.StopAtBounds

          Row {
            id: columnsRow
            spacing: root.columnGap

            Repeater {
              model: root.columns

              Column {
                id: colItem
                required property var modelData
                width: root.columnWidth
                spacing: Style.space(18)

                Repeater {
                  model: colItem.modelData

                  Column {
                    id: catItem
                    required property var modelData
                    width: colItem.width
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      text: catItem.modelData.title
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                    }
                    Text {
                      visible: catItem.modelData.blurb !== "" && root.filterText === ""
                                      textFormat: Text.PlainText
                      text: catItem.modelData.blurb
                      color: root.foreground
                      opacity: 0.55
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      bottomPadding: Style.space(4)
                    }

                    Repeater {
                      model: catItem.modelData.rows

                      Rectangle {
                        id: rowItem
                        required property var modelData
                        width: catItem.width
                        height: root.rowHeight
                        radius: Style.space(5)
                        color: rowMouse.containsMouse && !modelData.locked ? root.rowHover : "transparent"

                        MouseArea {
                          id: rowMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          enabled: !rowItem.modelData.locked && !rowItem.modelData.custom
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.setRowDisabled(rowItem.modelData, !rowItem.modelData.disabled)
                        }

                        // Added shortcuts can be removed (there is nothing to "switch off" – they are yours).
                        Rectangle {
                          visible: rowItem.modelData.custom === true
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(4)
                          anchors.verticalCenter: parent.verticalCenter
                          width: Style.space(26)
                          height: Style.space(20)
                          radius: Style.space(4)
                          color: delMouse.containsMouse ? Util.alpha(root.foreground, 0.15) : "transparent"
                          Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "✕"
                            color: root.foreground
                            opacity: 0.7
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                          }
                          MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeCustom(rowItem.modelData)
                          }
                        }

                        // Off/on switch; locked rows (the ones that get you back here) have none.
                        Rectangle {
                          id: sw
                          visible: !rowItem.modelData.locked && !rowItem.modelData.custom
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          width: Style.space(26)
                          height: Style.space(14)
                          radius: height / 2
                          color: rowItem.modelData.disabled ? Util.alpha(root.foreground, 0.18) : root.accent
                          Rectangle {
                            width: parent.height - Style.space(4)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: rowItem.modelData.disabled ? Style.space(2) : parent.width - width - Style.space(2)
                            color: root.background
                          }
                        }

                        Row {
                          id: caps
                          anchors.right: parent.right
                          anchors.rightMargin: Style.space(40)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(3)
                          opacity: rowItem.modelData.disabled ? 0.35 : 1

                          Repeater {
                            model: rowItem.modelData.tokens
                            Rectangle {
                              required property string modelData
                              height: Style.font.body + Style.space(8)
                              width: capText.implicitWidth + Style.space(12)
                              radius: Style.space(4)
                              color: Util.alpha(root.foreground, 0.09)
                              border.width: 1
                              border.color: Util.alpha(root.foreground, 0.22)
                              Text {
                                id: capText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: parent.modelData
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                              }
                            }
                          }
                        }

                        Text {
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(6)
                          anchors.right: caps.left
                          anchors.rightMargin: Style.space(10)
                          anchors.verticalCenter: parent.verticalCenter
                          textFormat: Text.PlainText
                          text: rowItem.modelData.desc
                          color: root.foreground
                          opacity: rowItem.modelData.disabled ? 0.4 : 1
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          font.strikeout: rowItem.modelData.disabled
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.columns.length > 0 && root.columns.every(function(c) { return c.length === 0 })
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "No shortcuts match “" + root.filterText + "”"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Rectangle { width: parent.width; height: 1; color: Util.alpha(root.foreground, 0.12) }

        Item {
          id: footer
          width: parent.width
          height: Style.font.bodySmall + Style.space(12)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "Type to search  ·  click a row to switch it off/on  ·  Ctrl+N adds a shortcut  ·  Esc to close"
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Close after using a shortcut"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: Style.space(14)
              radius: height / 2
              color: root.closeOnUse ? root.accent : Util.alpha(root.foreground, 0.18)
              Rectangle {
                width: parent.height - Style.space(4)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: root.closeOnUse ? parent.width - width - Style.space(2) : Style.space(2)
                color: root.background
              }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setCloseOnUse(!root.closeOnUse)
              }
            }
          }
        }
      }

      // ---- Add shortcut ----------------------------------------------------------------
      Item {
        id: formLayer
        anchors.fill: parent
        visible: root.formOpen
        z: 10

        Rectangle { anchors.fill: parent; color: Util.alpha(root.background, 0.82); radius: root.cornerRadius }
        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
          id: formBox
          anchors.centerIn: parent
          width: Math.min(Style.space(560), parent.width - Style.space(40))
          height: formColumn.implicitHeight + Style.space(36)
          radius: root.cornerRadius
          color: root.background
          border.width: 1
          border.color: Util.alpha(root.foreground, 0.25)

          Column {
            id: formColumn
            anchors.fill: parent
            anchors.margins: Style.space(18)
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: "New shortcut"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            // Name
            Rectangle {
              width: parent.width
              height: Style.font.body + Style.space(16)
              radius: Style.space(5)
              color: Util.alpha(root.foreground, 0.07)
              border.width: 1
              border.color: nameInput.activeFocus ? root.accent : Util.alpha(root.foreground, 0.2)
              TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.margins: Style.space(8)
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                clip: true
                selectByMouse: true
                text: root.formDesc
                onTextEdited: { root.formDesc = text; root.formMessage = "" }
                Keys.onPressed: function(event) { root.noteKey(event) }
                Keys.onEscapePressed: root.closeForm()
                Keys.onReturnPressed: function(event) { if (event.modifiers & Qt.ControlModifier) root.saveForm(); else cmdInput.forceActiveFocus() }
                Keys.onTabPressed: cmdInput.forceActiveFocus()
              }
              Text {
                visible: nameInput.text === ""
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Name — what it does, e.g. Files"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            // Command
            Rectangle {
              width: parent.width
              height: Style.font.body + Style.space(16)
              radius: Style.space(5)
              color: Util.alpha(root.foreground, 0.07)
              border.width: 1
              border.color: cmdInput.activeFocus ? root.accent : Util.alpha(root.foreground, 0.2)
              TextInput {
                id: cmdInput
                anchors.fill: parent
                anchors.margins: Style.space(8)
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                clip: true
                selectByMouse: true
                text: root.formCmd
                onTextEdited: { root.formCmd = text; root.formMessage = "" }
                Keys.onPressed: function(event) { root.noteKey(event) }
                Keys.onEscapePressed: root.closeForm()
                Keys.onReturnPressed: function(event) { if (event.modifiers & Qt.ControlModifier) root.saveForm(); else keyBox.forceActiveFocus() }
                Keys.onTabPressed: keyBox.forceActiveFocus()
              }
              Text {
                visible: cmdInput.text === ""
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Command — e.g. nautilus, or omarchy-launch-webapp https://…"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            // Keys: modifier chips + press-a-key box
            Row {
              spacing: Style.space(6)

              Repeater {
                model: [["SUPER", "Super"], ["CTRL", "Ctrl"], ["ALT", "Alt"], ["SHIFT", "Shift"]]

                Rectangle {
                  required property var modelData
                  readonly property bool on: root.formMods.indexOf(modelData[0]) >= 0
                  height: Style.font.body + Style.space(14)
                  width: modLabel.implicitWidth + Style.space(20)
                  radius: Style.space(5)
                  color: on ? root.accent : Util.alpha(root.foreground, 0.07)
                  border.width: 1
                  border.color: on ? root.accent : Util.alpha(root.foreground, 0.22)
                  Text {
                    id: modLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData[1]
                    color: parent.on ? root.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.toggleFormMod(parent.modelData[0]); root.formMessage = "" }
                  }
                }
              }

              Text {
                anchors.verticalCenter: undefined
                height: Style.font.body + Style.space(14)
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: "+"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Rectangle {
                id: keyBox
                height: Style.font.body + Style.space(14)
                width: Math.max(Style.space(150), keyLabel.implicitWidth + Style.space(24))
                radius: Style.space(5)
                color: Util.alpha(root.foreground, 0.07)
                border.width: 1
                border.color: activeFocus ? root.accent : Util.alpha(root.foreground, 0.22)
                focus: false
                activeFocusOnTab: false

                Text {
                  id: keyLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.formKey ? Omacheat.prettyKey(root.formKey) : (keyBox.activeFocus ? "press a key…" : "click, then press a key")
                  color: root.foreground
                  opacity: root.formKey ? 1 : 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: keyBox.forceActiveFocus() }

                Keys.onPressed: function(event) {
                  root.noteKey(event)
                  if (event.key === Qt.Key_Escape) { root.closeForm(); event.accepted = true; return }
                  if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { root.saveForm(); event.accepted = true; return }
                  var name = Omacheat.keyFromQt(event.key)
                  if (name) { root.formKey = name; root.formMessage = "" }
                  event.accepted = true
                }
              }
            }

            // Category
            Flow {
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: Omacheat.CATEGORIES.filter(function(c) { return c.id !== "media" })

                Rectangle {
                  required property var modelData
                  readonly property bool on: root.formCategory === modelData.id
                  height: Style.font.bodySmall + Style.space(10)
                  width: catLabel.implicitWidth + Style.space(16)
                  radius: height / 2
                  color: on ? Util.alpha(root.accent, 0.22) : "transparent"
                  border.width: 1
                  border.color: on ? root.accent : Util.alpha(root.foreground, 0.2)
                  Text {
                    id: catLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData.title
                    color: root.foreground
                    opacity: parent.on ? 1 : 0.65
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall - 1
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.formCategory = parent.modelData.id }
                }
              }
            }

            // Feedback: problem, or a heads-up when the combination is taken
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              readonly property var clash: root.formClash()
              text: root.formMessage !== "" ? root.formMessage
                    : (clash ? "Already used by “" + clash.desc + "” — saving will replace it." : "Runs as typed. Pick the group it should be listed under. Ctrl+Enter saves.")
              color: root.formMessage !== "" ? "#e06c75" : root.foreground
              opacity: root.formMessage !== "" || clash ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(8)

              Rectangle {
                height: Style.font.body + Style.space(14)
                width: cancelLabel.implicitWidth + Style.space(24)
                radius: Style.space(5)
                color: cancelMouse.containsMouse ? root.rowHover : "transparent"
                border.width: 1
                border.color: Util.alpha(root.foreground, 0.25)
                Text { id: cancelLabel; anchors.centerIn: parent; textFormat: Text.PlainText; text: "Cancel"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                MouseArea { id: cancelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeForm() }
              }

              Rectangle {
                height: Style.font.body + Style.space(14)
                width: saveLabel.implicitWidth + Style.space(24)
                radius: Style.space(5)
                color: root.accent
                Text { id: saveLabel; anchors.centerIn: parent; textFormat: Text.PlainText; text: "Save shortcut"; color: root.background; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.saveForm() }
              }
            }
          }
        }
      }
    }
  }
}
