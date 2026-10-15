import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import ".."

// StatusNotifier host. Menu-only items (ItemIsMenu=true, e.g. the ProtonVPN
// indicator) never answer Activate, so their DBusMenu is rendered on click
// via QsMenuAnchor. Platform menus require `//@ pragma UseQApplication` in
// shell.qml (quickshell starts in QApplication mode).
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  visible: SystemTray.items.values.length > 0

  QsMenuAnchor {
    id: menuAnchor
    // Drop the menu below the tray icon (bar is top-anchored); Slide keeps it
    // on-screen for the rightmost icons.
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Top | Edges.Left
  }

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
          id: icon
          anchors.centerIn: parent
          source: modelData.icon
          sourceSize: Qt.size(16, 16)
          smooth: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

          onClicked: (mouse) => {
            switch (mouse.button) {
            case Qt.LeftButton:
              if (modelData.onlyMenu) openMenu()
              else modelData.activate()
              break
            case Qt.MiddleButton:
              modelData.secondaryActivate()
              break
            case Qt.RightButton:
              openMenu()
              break
            }
          }
          onWheel: (wheel) => modelData.scroll(wheel.angleDelta.y > 0 ? 120 : -120, false)

          function openMenu() {
            if (!modelData.menu) return
            menuAnchor.menu = modelData.menu
            menuAnchor.anchor.item = icon
            if (menuAnchor.visible) menuAnchor.close()
            menuAnchor.open()
          }
        }
      }
    }
  }
}
