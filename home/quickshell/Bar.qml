import Quickshell
import Quickshell.Hyprland
import QtQuick
import "widgets"

// Note: all glyphs are written as String.fromCodePoint(...) so the files stay
// plain ASCII and can't be corrupted by encoding issues. Names in comments
// refer to the Nerd Fonts icon database.
PanelWindow {
  id: bar
  // Set by the Variants delegate in shell.qml.
  property var modelData: null
  screen: modelData

  anchors { top: true; left: true; right: true }
  implicitHeight: Theme.barHeight
  exclusiveZone: Theme.barHeight

  color: "transparent"
  surfaceFormat.opaque: false

  // The panel (flush with the screen edges, so no rounding)
  Rectangle {
    anchors.fill: parent
    radius: 0
    color: Theme.bg
    border.width: 1
    border.color: Theme.border
  }

  // Left: workspaces
  Row {
    anchors.left: parent.left
    anchors.leftMargin: Theme.padH
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.gap

    Workspaces {}
  }

  // Center: focused window title
  Item {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(title.implicitWidth, parent.width * 0.35)
    height: parent.height
    clip: true

    Text {
      id: title
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
      color: Theme.fgDim
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
      elide: Text.ElideRight
    }
  }

  // Right: modules + power button
  Row {
    anchors.right: parent.right
    anchors.rightMargin: Theme.padH
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.gap

    SystemStats {}
    Network {}
    Audio {}
    Brightness {}
    Battery {}
    Clock {}
    Tray {}
    PowerButton { barScreen: bar.screen }
  }

  // The chip is centered in a bar-height cell so it aligns with the widgets
  // (the widgets center their content in the same height).
  component PowerButton: Item {
    required property var barScreen

    implicitHeight: Theme.barHeight
    implicitWidth: 22

    Rectangle {
      id: chip
      anchors.verticalCenter: parent.verticalCenter
      width: 22
      height: 22
      radius: Theme.chipRadius
      color: mouse.containsMouse ? Theme.bgHover : "transparent"
      Behavior on color {
        enabled: Theme.animations
        ColorAnimation { duration: Theme.fast }
      }
    }

    Text {
      anchors.centerIn: chip
      text: String.fromCodePoint(0xF0425) // nf-md-power
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }

    MouseArea {
      id: mouse
      anchors.fill: chip
      hoverEnabled: true
      onClicked: Ui.toggleMenu(barScreen)
    }
  }
}
