import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQml

// Minimal app launcher (replaces wofi). This is a SEPARATE quickshell
// process from the bar: the hyprland keybind toggles it with
//   quickshell kill -c launcher || quickshell --config launcher
// The window is visible from startup and never hidden, so nothing here
// depends on lazy first-show behavior. Esc, click-out, or launching an app
// quits the process.
ShellRoot {
  PanelWindow {
    id: root
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.layer: WlrLayer.Overlay
    focusable: true

    // Local design tokens — the launcher deliberately shares nothing with
    // the bar config so this stays self-contained.
    readonly property color bg: "#323232"
    readonly property color bgHover: "#3d3d3d"
    readonly property color border: "#454545"
    readonly property color fg: "#e8e8e8"
    readonly property color fgFaint: "#5f5f5f"
    readonly property int rowHeight: 36
    readonly property int maxRows: 12

    // Reactive on DesktopEntries.applications.values: quickshell's scan is
    // async and populates the model a moment AFTER startup, so this must be
    // a binding (a one-shot read at startup would stay empty forever).
    property var allEntries: {
      const arr = [];
      for (const e of DesktopEntries.applications.values) {
        if (!e.noDisplay && e.command.length > 0) arr.push(e);
      }
      arr.sort((a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
      return arr;
    }

    property string query: ""

    property var matches: {
      const q = root.query.trim().toLowerCase();
      return q === "" ? root.allEntries
        : root.allEntries.filter(e => e.name.toLowerCase().includes(q));
    }

    Component.onCompleted: {
      field.forceActiveFocus();
    }

    function launch(entry) {
      if (!entry) return;
      if (entry.runInTerminal) Quickshell.execDetached(["alacritty", "-e"].concat(entry.command));
      else entry.execute();
      Qt.quit();
    }

    function move(delta) {
      const n = root.matches.length;
      if (n === 0) {
        list.currentIndex = -1;
        return;
      }
      let i = list.currentIndex === -1 ? 0 : list.currentIndex + delta;
      i = Math.max(0, Math.min(n - 1, i));
      list.currentIndex = i;
      list.positionViewAtIndex(i, ListView.Contain);
    }

    // Click anywhere outside the card to dismiss.
    MouseArea {
      anchors.fill: parent
      onClicked: Qt.quit()
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * 0.18
      width: Math.min(560, parent.width - 24)
      height: field.height + list.height + 16
      radius: 10
      color: root.bg
      border.width: 1
      border.color: root.border

      // Swallow clicks on the card itself (they must not dismiss).
      MouseArea { anchors.fill: parent }

      TextField {
        id: field
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        height: 36
        placeholderText: "Search"
        color: root.fg
        placeholderTextColor: root.fgFaint
        font.pixelSize: 13
        leftPadding: 12
        rightPadding: 12
        verticalAlignment: TextInput.AlignVCenter
        background: Rectangle { radius: 6; color: root.bgHover }
        onTextChanged: {
          root.query = text;
          list.currentIndex = 0;
        }
        Keys.onPressed: (event) => {
          switch (event.key) {
            case Qt.Key_Up: root.move(-1); event.accepted = true; break;
            case Qt.Key_Down: root.move(1); event.accepted = true; break;
            case Qt.Key_Return:
            case Qt.Key_Enter: root.launch(root.matches[list.currentIndex]); event.accepted = true; break;
            case Qt.Key_Escape: Qt.quit(); event.accepted = true; break;
          }
        }
      }

      ListView {
        id: list
        anchors {
          left: parent.left
          right: parent.right
          top: field.bottom
          leftMargin: 4
          rightMargin: 4
          topMargin: 4
        }
        height: Math.min(root.matches.length, root.maxRows) * root.rowHeight
        model: root.matches
        currentIndex: -1
        clip: true

        delegate: Item {
          property var modelData: null
          height: root.rowHeight

          Rectangle {
            anchors.fill: parent
            radius: 6
            color: (mouse.containsMouse || index === list.currentIndex) ? root.bgHover : "transparent"
          }

          Text {
            anchors {
              left: parent.left
              leftMargin: 14
              right: parent.right
              rightMargin: 12
              verticalCenter: parent.verticalCenter
            }
            text: modelData ? modelData.name : ""
            color: root.fg
            font.pixelSize: 13
            elide: Text.ElideRight
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.launch(modelData)
          }
        }
      }

      Text {
        // "Loading…" covers the async scan right after launch; "No matches"
        // means the scan is done and the query really matches nothing.
        visible: root.matches.length === 0
        anchors { horizontalCenter: parent.horizontalCenter; top: field.bottom; topMargin: 12 }
        text: root.query === "" && DesktopEntries.applications.values.length === 0
          ? "Loading…" : "No matches"
        color: root.fgFaint
        font.pixelSize: 13
      }
    }
  }
}
