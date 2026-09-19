import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Screen backlight via sysfs. Wheel uses the same brightnessctl flags as the
// XF86MonBrightness binds in hyprland.conf, so OSD and keys agree.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  property string dev: ""
  property real pct: 0
  property real lastPct: -1
  property bool primed: false

  Process {
    id: findDev
    command: ["sh", "-c", "ls -1 /sys/class/backlight 2>/dev/null | head -n1"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dev = this.text.trim()
    }
  }

  FileView {
    id: briFile
    path: root.dev !== "" ? "/sys/class/backlight/" + root.dev + "/brightness" : ""
    watchChanges: true
    onFileChanged: root.read()
  }
  FileView {
    id: maxFile
    path: root.dev !== "" ? "/sys/class/backlight/" + root.dev + "/max_brightness" : ""
  }

  function read() {
    if (root.dev === "") return;
    const b = Number(briFile.text().trim());
    const m = Number(maxFile.text().trim());
    if (isNaN(b) || isNaN(m) || m <= 0) return;
    root.pct = Math.max(0, Math.min(1, b / m));
    // The 1s poll would otherwise re-trigger the OSD forever; only show it
    // when the value actually changed.
    if (root.primed && Math.abs(root.pct - root.lastPct) > 0.001) Ui.showBrightness(root.pct);
    root.lastPct = root.pct;
  }

  // Backstop poll — sysfs inotify is historically flaky.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.read()
  }

  Timer {
    id: primer
    interval: 2000
    running: true
    repeat: false
    onTriggered: root.primed = true
  }

  visible: root.dev !== ""

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    Text {
      text: String.fromCodePoint(0xF00DE) // nf-md-brightness_6
      color: Theme.fg
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }
    Text {
      text: Math.round(root.pct * 100) + "%"
      color: Theme.fg
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }
  }

  MouseArea {
    anchors.fill: parent
    onWheel: (wheel) => {
      Quickshell.execDetached([
        "brightnessctl", "-e4", "-n2", "set", wheel.angleDelta.y > 0 ? "5%+" : "5%-"
      ]);
    }
  }
}
