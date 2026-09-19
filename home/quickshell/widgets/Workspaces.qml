import QtQuick
import Quickshell.Hyprland
import ".."

// Numbered workspace indicators: focused = pill highlight, occupied = dim,
// empty = faint, urgent = red. Named/scratchpad workspaces (negative ids)
// are filtered out.
Item {
  id: root
  implicitHeight: Theme.wsHeight
  implicitWidth: wsRow.implicitWidth

  Row {
    id: wsRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Repeater {
      model: Hyprland.workspaces.values

      delegate: Item {
        required property var modelData
        visible: modelData.id > 0

        width: pill.width
        height: Theme.wsHeight

        Rectangle {
          id: pill
          anchors.verticalCenter: parent.verticalCenter
          width: numberText.implicitWidth + 2 * Theme.pillPad
          height: Theme.wsHeight
          radius: height / 2
          color: modelData.focused ? Theme.bgHover : "transparent"
          Behavior on color {
            enabled: Theme.animations
            ColorAnimation { duration: Theme.fast }
          }
        }

        Text {
          id: numberText
          anchors.centerIn: pill
          text: modelData.id
          color: modelData.urgent ? Theme.urgent
            : modelData.focused ? Theme.fg
            : modelData.toplevels.values.length > 0 ? Theme.fgDim
            : Theme.fgFaint
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSize - 1
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
