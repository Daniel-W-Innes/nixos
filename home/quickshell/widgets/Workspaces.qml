import QtQuick
import Quickshell.Hyprland
import ".."

// Workspace dots: occupied = dim, focused = pill (widens), urgent = red.
// Named/scratchpad workspaces have negative ids and are filtered out.
Item {
  id: root
  implicitHeight: Theme.dotSize
  implicitWidth: wsRow.implicitWidth

  Row {
    id: wsRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6

    Repeater {
      model: Hyprland.workspaces.values

      delegate: Item {
        required property var modelData
        visible: modelData.id > 0

        width: modelData.focused ? Theme.pillWidth : Theme.dotSize
        height: Theme.dotSize
        Behavior on width {
          enabled: Theme.animations
          NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: modelData.urgent ? Theme.urgent
            : modelData.focused ? Theme.fg
            : modelData.toplevels.values.length > 0 ? Theme.fgDim
            : Theme.fgFaint
          Behavior on color {
            enabled: Theme.animations
            ColorAnimation { duration: Theme.fast }
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: modelData.activate()
        }
      }
    }
  }

  WheelHandler {
    onWheel: (wheel) => Hyprland.dispatch(wheel.angleDelta.y > 0 ? "workspace e+1" : "workspace e-1")
  }
}
