import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQml

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

  readonly property int listH: Data.matches.length === 0
    ? win.rowH
    : Math.min(Data.matches.length, win.maxRows) * win.rowH

  function activate(index) {
    list.currentIndex = index;
    if (Data.activate(Data.matches[index]))
      Qt.quit();
  }

  // Row components. Component { id: ... } objects (not inline `component`
  // types) so the delegate binding can reference them — type names don't
  // resolve inside JS bindings.

  Component {
    id: appDelegate
    Item {
    width: ListView.view.width
    height: win.rowH
    readonly property var entry: modelData

    IconImage {
      anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
      width: 22
      height: 22
      // entry is briefly undefined when the model array swaps mid-typing.
      // iconPath(icon, fallback) renders the fallback when the icon name
      // doesn't resolve — Steam installs game icons lazily, so their
      // steam_icon_* names are often unresolvable and would render blank.
      source: entry ? Quickshell.iconPath(entry.icon, "image-missing") : ""
    }

    Column {
      anchors {
        left: parent.left
        leftMargin: 42
        right: parent.right
        rightMargin: 10
        verticalCenter: parent.verticalCenter
      }

      Text {
        width: parent.width
        text: entry && entry.name ? entry.name : ""
        color: Theme.fg
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSize + 1
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text.length > 0
        text: entry && entry.genericName ? entry.genericName : ""
        color: Theme.fgDim
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSize - 2
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: win.activate(index)
    }
    }
  }

  Component {
    id: actionDelegate
    Item {
    width: ListView.view.width
    height: win.rowH

    Text {
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      text: modelData && modelData.glyph ? modelData.glyph : ""
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }

    Text {
      anchors { left: parent.left; leftMargin: 40; verticalCenter: parent.verticalCenter }
      text: modelData && modelData.name ? modelData.name : ""
      color: Theme.fg
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize + 1
    }

    MouseArea {
      anchors.fill: parent
      onClicked: win.activate(index)
    }
    }
  }

  Component {
    id: calcDelegate
    Item {
    width: ListView.view.width
    height: win.rowH

    Text {
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      text: String.fromCodePoint(0xF00EC) // md-calculator, verified in font cmap
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }

    Text {
      anchors {
        left: parent.left
        leftMargin: 40
        right: chip.left
        rightMargin: 10
        verticalCenter: parent.verticalCenter
      }
      text: Data.calcError
        ? "Invalid expression"
        : Data.calcPending
          ? "Calculating..."
          : Data.calcResult
            ? Data.calcResult
            : "Type an expression"
      color: Data.calcError
        ? Theme.critical
        : Data.calcResult ? Theme.fg : Theme.fgDim
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize + 1
      elide: Text.ElideLeft
    }

    // Row click copies the result (see win.activate); the chip opens qalc.
    MouseArea {
      anchors.fill: parent
      onClicked: win.activate(index)
    }

    Rectangle {
      id: chip
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      width: label.implicitWidth + 16
      height: label.implicitHeight + 8
      radius: Theme.chipRadius
      color: Theme.bgHover

      Text {
        id: label
        anchors.centerIn: parent
        text: "qalc"
        color: Theme.fgDim
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSize - 1
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (Data.openInQalc())
            Qt.quit();
        }
      }
    }
    }
  }

  Connections {
    target: Data
    function onMatchesChanged() {
      list.currentIndex = 0;
    }
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
        text: Data.query
        onTextChanged: {
          if (text !== Data.query)
            Data.query = text;
        }
        placeholderText: Data.mode === "actions"
          ? "Type an action..."
          : Data.mode === "calc"
            ? "Type an expression..."
            : "Type to search..."
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
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Tab) {
            if (list.count > 0)
              list.currentIndex = (list.currentIndex + 1) % list.count;
            event.accepted = true;
          } else if (event.key === Qt.Key_Backtab
              || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            if (list.count > 0)
              list.currentIndex = (list.currentIndex - 1 + list.count) % list.count;
            event.accepted = true;
          } else if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
              move(1);
              event.accepted = true;
            } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
              move(-1);
              event.accepted = true;
            }
          }
        }
        onAccepted: win.activate(list.currentIndex)

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
          model: Data.matches
          delegate: Data.mode === "apps"
            ? appDelegate
            : Data.mode === "actions"
              ? actionDelegate
              : calcDelegate
          clip: true
          interactive: false
          preferredHighlightBegin: 0
          preferredHighlightEnd: height
          highlightRangeMode: ListView.ApplyRange

          highlight: Rectangle {
            radius: Theme.chipRadius
            color: Theme.bgHover
          }
        }

        // Distinguish the async-scan state from a genuinely empty result
        // (docs/issues/08).
        Text {
          anchors.centerIn: parent
          visible: Data.matches.length === 0
          text: Data.mode === "actions"
            ? "No matching actions"
            : DesktopEntries.applications.values.length === 0
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
