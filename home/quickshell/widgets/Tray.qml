import QtQuick
import Quickshell.Services.SystemTray
import ".."

// StatusNotifier host. Menus are deliberately not handled:
// SystemTrayItem.display() renders a platform menu which requires
// `//@ pragma UseQApplication` in the shell root, so left-clicking an
// item that only exposes a menu (onlyMenu: true) does nothing for now.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  visible: SystemTray.items.values.length > 0

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6

    Repeater {
      model: SystemTray.items.values

      delegate: Item {
        required property var modelData
        width: 18
        height: 18

        Image {
          anchors.centerIn: parent
          source: modelData.icon
          sourceSize: Qt.size(16, 16)
          smooth: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          onClicked: (mouse) => mouse.button === Qt.LeftButton
            ? modelData.activate()
            : modelData.secondaryActivate()
          onWheel: (wheel) => modelData.scroll(wheel.angleDelta.y > 0 ? 120 : -120, false)
        }
      }
    }
  }
}
