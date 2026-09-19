import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import ".."

// PipeWire default sink. Click opens pavucontrol, wheel nudges volume.
// Volume changes signal the OSD through the Ui singleton.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  PwObjectTracker {
    // volume/mute stay invalid unless the node is bound via a tracker
    objects: [Pipewire.defaultAudioSink]
  }

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  property bool primed: false

  // Don't pop the OSD for the initial values that appear at startup.
  Timer {
    id: primer
    interval: 2000
    running: true
    repeat: false
    onTriggered: root.primed = true
  }

  onVolChanged: if (primed) Ui.showVolume(vol, muted)
  onMutedChanged: if (primed) Ui.showVolume(vol, muted)

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    Text {
      text: muted
        ? String.fromCodePoint(0xF026) // nf-fa-volume-off
        : vol < 0.34
          ? String.fromCodePoint(0xF027) // nf-fa-volume-down
          : String.fromCodePoint(0xF028) // nf-fa-volume-up
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }
    Text {
      text: Math.round(vol * 100) + "%"
      color: Theme.fg
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["pavucontrol"])
    onWheel: (wheel) => {
      if (!sink || !sink.audio) return;
      const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02;
      sink.audio.volume = Math.max(0, Math.min(1, vol + step));
    }
  }
}
