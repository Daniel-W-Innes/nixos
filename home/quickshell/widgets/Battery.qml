import QtQuick
import Quickshell.Services.UPower
import ".."

// UPower display device (the aggregate). Hidden until upowerd answers.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  readonly property var dev: UPower.displayDevice
  readonly property int pct: dev && dev.ready ? Math.round(dev.percentage * 100) : 0
  readonly property bool charging: dev && dev.ready
    && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.PendingCharge)

  visible: dev && dev.ready && dev.isPresent

  function glyph() {
    if (charging) return String.fromCodePoint(0xF0084); // nf-md-battery_charging
    if (pct <= 10) return String.fromCodePoint(0xF008E); // nf-md-battery_outline
    // nf-md-battery_10 .. battery_90 are contiguous: 0xF007A .. 0xF0082
    return String.fromCodePoint(0xF0079 + Math.min(9, Math.max(1, Math.round(pct / 10))));
  }

  function tint() {
    if (pct < 15) return Theme.critical;
    if (pct < 30) return Theme.warning;
    return Theme.fg;
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    Text {
      text: glyph()
      color: tint()
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }
    Text {
      text: pct + "%"
      color: tint()
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }
  }
}
