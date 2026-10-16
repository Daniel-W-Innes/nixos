import QtQuick
import Quickshell
import ".."

// Time readout; click toggles the calendar menu, centered under the clock.
// The anchor is passed as a fraction of the bar's width because the bar and
// calendar windows can live in different pixel spaces on HiDPI.
Item {
  id: root
  // Set by the bar.
  required property var barScreen
  required property var barWindow

  implicitHeight: Theme.barHeight
  implicitWidth: timeText.implicitWidth

  SystemClock {
    id: clock
    enabled: true
    precision: SystemClock.Seconds
  }

  Rectangle {
    id: chip
    anchors.fill: parent
    radius: Theme.chipRadius
    color: mouse.containsMouse ? Theme.bgHover : "transparent"
    Behavior on color {
      enabled: Theme.animations
      ColorAnimation { duration: Theme.fast }
    }
  }

  Text {
    id: timeText
    anchors.verticalCenter: parent.verticalCenter
    text: Qt.formatDateTime(clock.date, "HH:mm")
    color: Theme.fg
    font.family: Theme.textFont
    font.pixelSize: Theme.fontSize
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: {
      const content = barWindow.contentItem;
      const centerX = timeText.mapToItem(content, 0, 0).x + timeText.width / 2;
      // The bar is top-anchored (y=0), so its bottom edge on screen is just
      // its height. Windows don't expose x/y in QML, hence the derivation.
      Ui.toggleCalendar(barScreen,
        content.width > 0 ? centerX / content.width : 0,
        content.width, content.height,
        barWindow.height);
    }
  }
}
