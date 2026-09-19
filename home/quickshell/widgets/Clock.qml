import QtQuick
import Quickshell
import ".."

Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: timeText.implicitWidth

  SystemClock {
    id: clock
    enabled: true
    precision: SystemClock.Seconds
  }

  Text {
    id: timeText
    anchors.verticalCenter: parent.verticalCenter
    text: Qt.formatDateTime(clock.date, "HH:mm")
    color: Theme.fg
    font.family: Theme.textFont
    font.pixelSize: Theme.fontSize
  }
}
