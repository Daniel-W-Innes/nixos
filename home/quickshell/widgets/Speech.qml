import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// hyprwhspr-rs dictation indicator. The daemon writes an atomic waybar-style
// status file (~/.cache/hyprwhspr-rs/status.json, class: inactive|active|
// processing|error). Poll it on a timer; while the daemon isn't running (no
// file) the widget hides itself, which also keeps it off cucamelon where the
// daemon doesn't exist. Click toggles dictation.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: mic.implicitWidth

  property string statusClass: "none"
  visible: statusClass !== "none"

  // The poll runs even while hidden: the widget starts hidden and has to
  // discover the daemon (its status file) before it can show anything.
  Timer {
    id: poll
    interval: 500
    repeat: true
    running: true
    onTriggered: statusProc.running = true
  }

  Process {
    id: statusProc
    command: [
      "sh", "-c",
      "test -f \"$HOME/.cache/hyprwhspr-rs/status.json\" && cat \"$HOME/.cache/hyprwhspr-rs/status.json\"",
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const s = JSON.parse(text);
          root.statusClass = typeof s.class === "string" ? s.class : "none";
        } catch (e) {
          root.statusClass = "none"; // missing/corrupt status file
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0)
        root.statusClass = "none";
    }
  }

  function glyph() {
    return String.fromCodePoint(
      statusClass === "active" || statusClass === "processing"
        ? 0xF036C // nf-md-microphone
        : 0xF036D, // nf-md-microphone_off
    );
  }

  function tint() {
    if (statusClass === "active") return Theme.critical;
    if (statusClass === "processing") return Theme.warning;
    if (statusClass === "error") return Theme.critical;
    return Theme.fgFaint;
  }

  Text {
    id: mic
    anchors.verticalCenter: parent.verticalCenter
    text: glyph()
    color: tint()
    font.family: Theme.iconFont
    font.pixelSize: Theme.iconSize
    Behavior on color {
      enabled: Theme.animations
      ColorAnimation { duration: Theme.fast }
    }
    // Slow blink while recording (subtle, per Theme).
    SequentialAnimation on opacity {
      loops: Animation.Infinite
      running: root.statusClass === "active"
      NumberAnimation { from: 1; to: 0.5; duration: 600 }
      NumberAnimation { from: 0.5; to: 1; duration: 600 }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: Quickshell.execDetached(["hyprwhspr-rs", "record", "toggle"])
  }
}
