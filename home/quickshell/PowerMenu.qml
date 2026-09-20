import Quickshell
import Quickshell.Wayland
import QtQuick

// Full-screen transparent surface with the menu card anchored top-right.
// Only visible on the screen whose power button was clicked.
PanelWindow {
  id: root
  // Set by the Variants delegate in shell.qml.
  property var modelData: null
  screen: modelData

  anchors { top: true; bottom: true; left: true; right: true }
  exclusiveZone: 0
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.layer: WlrLayer.Overlay

  visible: Ui.menuVisible && Ui.menuScreen === root.screen

  // Click anywhere outside the card to dismiss.
  MouseArea {
    anchors.fill: parent
    onClicked: Ui.closeMenu()
  }

  Rectangle {
    // Right edge flush with the power button (which sits inset by padH),
    // hovering just below the bar.
    anchors { top: parent.top; right: parent.right; topMargin: Theme.barHeight + 6; rightMargin: Theme.padH }
    width: 200
    height: column.implicitHeight + 12
    radius: Theme.radius
    color: Theme.bg
    border.width: 1
    border.color: Theme.border

    Column {
      id: column
      anchors.fill: parent
      anchors.margins: 6
      spacing: 2

      MenuRow { glyph: String.fromCodePoint(0xF033E); label: "Lock"; cmd: ["quickshell", "--config", "lock"] }
      MenuRow { glyph: String.fromCodePoint(0xF0904); label: "Suspend"; cmd: ["systemctl", "suspend"] }
      MenuRow { glyph: String.fromCodePoint(0xF0709); label: "Reboot"; cmd: ["systemctl", "reboot"] }
      MenuRow { glyph: String.fromCodePoint(0xF0425); label: "Shut down"; cmd: ["systemctl", "poweroff"] }
      MenuRow { glyph: String.fromCodePoint(0xF0343); label: "Log out"; cmd: ["hyprctl", "dispatch", "exit"] }
    }
  }

  component MenuRow: Item {
    required property string glyph
    required property string label
    required property var cmd

    width: parent.width
    implicitHeight: 36

    Rectangle {
      anchors.fill: parent
      radius: Theme.chipRadius
      color: mouse.containsMouse ? Theme.bgHover : "transparent"
      Behavior on color {
        enabled: Theme.animations
        ColorAnimation { duration: Theme.fast }
      }
    }

    Text {
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      text: glyph
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }
    Text {
      anchors { left: parent.left; leftMargin: 40; verticalCenter: parent.verticalCenter }
      text: label
      color: Theme.fg
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {
        Ui.closeMenu();
        Quickshell.execDetached(cmd);
      }
    }
  }
}
