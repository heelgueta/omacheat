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

  function open(payloadJson) {
    root.opened = true
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

  property var applyQueue: []
  function runNextApply() {
    if (applyProc.running || root.applyQueue.length === 0) return
    applyProc.command = root.applyQueue.shift()
    applyProc.running = true
  }

  Process {
    id: applyProc
    onRunningChanged: if (!running) root.runNextApply()
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
        root.rows = Omacheat.parse(text, root.disabledList)
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
          // The compositor swallows keys that complete a keybinding, so the first thing
          // we see of one is its modifier going down. Super/Ctrl/Alt do nothing in here.
          if (root.closeOnUse && (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
              || event.key === Qt.Key_Control || event.key === Qt.Key_Alt)) {
            root.dismiss()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
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
            anchors.right: counter.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search shortcuts — try “window”, “screenshot”, “workspace”…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
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
                          enabled: !rowItem.modelData.locked
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.setRowDisabled(rowItem.modelData, !rowItem.modelData.disabled)
                        }

                        // Off/on switch; locked rows (the ones that get you back here) have none.
                        Rectangle {
                          id: sw
                          visible: !rowItem.modelData.locked
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
            text: "Type to search  ·  click a row to switch that shortcut off/on  ·  Esc to close"
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
    }
  }
}
