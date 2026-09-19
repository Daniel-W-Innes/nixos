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
  margins { top: 6; left: 8; right: 8 }
  implicitHeight: Theme.barHeight
  // Explicit zone: ExclusionMode.Auto would only reserve the surface height,
  // leaving the 6px top margin uncovered by windows.
  exclusiveZone: Theme.barHeight + 8

  color: "transparent"
  surfaceFormat.opaque: false

  // The rounded panel
  Rectangle {
    anchors.fill: parent
    radius: Theme.radius
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

  component PowerButton: Rectangle {
    required property var barScreen

    width: 22
    height: 22
    radius: Theme.chipRadius
    color: mouse.containsMouse ? Theme.bgHover : "transparent"
    Behavior on color {
      enabled: Theme.animations
      ColorAnimation { duration: Theme.fast }
    }

    Text {
      anchors.centerIn: parent
      text: String.fromCodePoint(0xF0425) // nf-md-power
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: Ui.toggleMenu(barScreen)
    }
  }
}
