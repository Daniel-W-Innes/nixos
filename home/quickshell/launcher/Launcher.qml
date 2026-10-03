import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQml
import "scripts/fzf.js" as Fzf

// Full-screen transparent surface with the launcher card anchored top-center
// below the bar (same pattern as PowerMenu.qml). Visible from the moment the
// process starts — never a hidden window that gets shown later
// (docs/issues/08). The process quits on launch/Escape/click-outside, so each
// keybind press is a fresh "first open".
PanelWindow {
  id: win
  // Set by the Variants delegate in shell.qml.
  property var modelData: null
  screen: modelData

  anchors { top: true; bottom: true; left: true; right: true }
  exclusiveZone: 0
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.layer: WlrLayer.Overlay
  focusable: true

  readonly property int searchH: 40
  readonly property int rowH: 44
  readonly property int maxRows: 8
  readonly property int pad: 10

  // DesktopEntries scans XDG dirs asynchronously (~2s) — these bindings must
  // stay reactive so the list repopulates when the scan completes. A one-shot
  // read is permanently empty (docs/issues/08).
  readonly property var allApps: DesktopEntries.applications.values
  readonly property var finder: new Fzf.Finder(allApps, { selector: e => e.name })
  readonly property var matches: {
    const q = search.text.trim();
    if (!q)
      return [...allApps];
    return finder.find(q).sort((a, b) => {
      if (a.score === b.score)
        return a.item.name.trim().length - b.item.name.trim().length;
      return b.score - a.score;
    }).map(r => r.item);
  }
  readonly property int listH: matches.length === 0
    ? win.rowH
    : Math.min(matches.length, win.maxRows) * win.rowH

  onMatchesChanged: list.currentIndex = 0

  function launch() {
    const entry = matches[list.currentIndex];
    if (!entry)
      return;
    if (entry.runInTerminal)
      // execute() ignores Terminal=true, so wrap terminal apps ourselves.
      Quickshell.execDetached(["alacritty", "-e", ...entry.command]);
    else
      entry.execute();
    Qt.quit();
  }

  // Click anywhere outside the card to dismiss.
  MouseArea {
    anchors.fill: parent
    onClicked: Qt.quit()
  }

  Rectangle {
    id: card
    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
    anchors.topMargin: Theme.barHeight + 12
    width: 560
    height: win.pad * 2 + win.searchH + win.pad + win.listH
    radius: Theme.radius
    color: Theme.bg
    border.width: 1
    border.color: Theme.border

    Column {
      anchors.fill: parent
      anchors.margins: win.pad
      spacing: win.pad

      TextField {
        id: search
        anchors.left: parent.left
        anchors.right: parent.right
        height: win.searchH
        placeholderText: "Type to search..."
        placeholderTextColor: Theme.fgFaint
        color: Theme.fg
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSize + 2
        leftPadding: 14
        rightPadding: 14

        background: Rectangle {
          radius: Theme.chipRadius
          color: Theme.bgHover
          border.width: 1
          border.color: search.activeFocus ? Theme.accent : Theme.border
        }

        Keys.onDownPressed: move(1)
        Keys.onUpPressed: move(-1)
        Keys.onEscapePressed: Qt.quit()
        onAccepted: win.launch()

        function move(delta) {
          const i = list.currentIndex + delta;
          if (i >= 0 && i < list.count)
            list.currentIndex = i;
        }
      }

      Item {
        id: resultsArea
        anchors.left: parent.left
        anchors.right: parent.right
        height: win.listH
        clip: true

        // Plain JS array model — ScriptModel caused empty-first-frame bugs
        // in the abandoned attempt (docs/issues/08).
        ListView {
          id: list
          anchors.fill: parent
          model: win.matches
          clip: true
          interactive: false
          preferredHighlightBegin: 0
          preferredHighlightEnd: height
          highlightRangeMode: ListView.ApplyRange

          highlight: Rectangle {
            radius: Theme.chipRadius
            color: Theme.bgHover
          }

          delegate: Item {
            width: ListView.view.width
            height: win.rowH
            readonly property var entry: modelData

            Row {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 10

              IconImage {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                source: Quickshell.iconPath(entry.icon, true)
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: entry.name
                color: Theme.fg
                font.family: Theme.textFont
                font.pixelSize: Theme.fontSize + 1
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                list.currentIndex = index;
                win.launch();
              }
            }
          }
        }

        // Distinguish the async-scan state from a genuinely empty result
        // (docs/issues/08).
        Text {
          anchors.centerIn: parent
          visible: win.matches.length === 0
          text: DesktopEntries.applications.values.length === 0
            ? "Loading apps..."
            : "No matches"
          color: Theme.fgDim
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSize
        }
      }
    }
  }

  Component.onCompleted: search.forceActiveFocus()
}
