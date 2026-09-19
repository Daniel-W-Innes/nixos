import QtQuick
import Quickshell.Networking
import ".."

// NetworkManager via quickshell's Networking module. Click toggles wifi.
// Note: NetworkDevice.address is the MAC — no IP display in v1.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
  readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired)
  readonly property var wifiNet: wifi && wifi.connected
    ? (wifi.networks.values.find(n => n.connected) || null)
    : null

  visible: wifi !== undefined || wired !== undefined

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    NetText {
      visible: wired !== undefined && wired.connected
      glyph: String.fromCodePoint(0xF0200) // nf-md-ethernet
      label: wired !== undefined ? wired.name : ""
      tint: Theme.fg
    }
    NetText {
      visible: wifi !== undefined && wifi.connected
      glyph: String.fromCodePoint(0xF1EB) // nf-fa-wifi
      label: wifiNet ? wifiNet.name + " " + Math.round(wifiNet.signalStrength * 100) + "%" : ""
      tint: Theme.fg
    }
    NetText {
      visible: wifi !== undefined && !wifi.connected && (wired === undefined || !wired.connected)
      glyph: String.fromCodePoint(0xF05AA) // nf-md-wifi_off
      label: ""
      tint: Networking.wifiEnabled ? Theme.fgFaint : Theme.fgDim
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (wifi !== undefined) Networking.wifiEnabled = !Networking.wifiEnabled;
    }
  }

  component NetText: Item {
    required property string glyph
    required property string label
    required property color tint

    implicitHeight: Theme.barHeight
    implicitWidth: icon.implicitWidth + (labelText.text !== "" ? 4 + labelText.implicitWidth : 0)

    Text {
      id: icon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: glyph
      color: tint
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }
    Text {
      id: labelText
      anchors.left: icon.right
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      text: label
      color: tint
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }
  }
}
