import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

// Volume / brightness overlay. Never takes keyboard focus (focusable defaults
// to false) and floats over fullscreen content.
PanelWindow {
  id: root
  // Set by the Variants delegate in shell.qml.
  property var modelData: null
  screen: modelData

  anchors { bottom: true }
  margins { bottom: 64 }
  implicitWidth: Theme.osdWidth
  implicitHeight: Theme.osdHeight
  exclusiveZone: 0
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.layer: WlrLayer.Overlay

  property real contentOpacity: 0
  visible: contentOpacity > 0
  Behavior on contentOpacity { NumberAnimation { duration: Theme.osdFade } }

  Connections {
    target: Ui
    function onOsdVisibleChanged() {
      // Show only on the focused monitor.
      const show = Ui.osdVisible && Hyprland.monitorFor(root.screen) === Hyprland.focusedMonitor;
      root.contentOpacity = show ? 1 : 0;
    }
  }

  Item {
    anchors.fill: parent
    opacity: root.contentOpacity

    Rectangle {
      anchors.centerIn: parent
      width: Theme.osdWidth
      height: Theme.osdHeight
      radius: Theme.radius
      color: Theme.bg
      border.width: 1
      border.color: Theme.border

      Row {
        anchors.centerIn: parent
        spacing: 10

        Text {
          text: Ui.osdKind === "volume"
            ? (Ui.osdMuted
              ? String.fromCodePoint(0xF026) // nf-fa-volume-off
              : (Ui.osdValue < 0.34
                ? String.fromCodePoint(0xF027) // nf-fa-volume-down
                : String.fromCodePoint(0xF028))) // nf-fa-volume-up
            : String.fromCodePoint(0xF00DE) // nf-md-brightness_6
          color: Theme.fg
          font.family: Theme.iconFont
          font.pixelSize: Theme.iconSize
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 120
          height: 6
          radius: 3
          color: Theme.bgHover

          Rectangle {
            width: parent.width * Ui.osdValue
            height: parent.height
            radius: 3
            color: (Ui.osdKind === "volume" && Ui.osdMuted) ? Theme.fgFaint : Theme.accent
            Behavior on width {
              enabled: Theme.animations
              NumberAnimation { duration: Theme.fast }
            }
          }
        }

        Text {
          text: Math.round(Ui.osdValue * 100) + "%"
          color: Theme.fg
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSize
        }
      }
    }
  }
}
