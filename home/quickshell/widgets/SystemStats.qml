import QtQuick
import Quickshell.Io
import ".."

// CPU / memory / temperature. No built-in quickshell types exist for these,
// so they are read from /proc and /sys with FileView (blocking text() reads
// keep the parsing synchronous) plus a 2s Timer backstop.
Item {
  id: root
  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  // ---- cpu (two-sample /proc/stat delta) ----
  property real cpu: 0
  property real prevIdle: 0
  property real prevTotal: 0

  FileView {
    id: cpuFile
    path: "/proc/stat"
    watchChanges: true
    onFileChanged: root.readCpu()
  }

  function readCpu() {
    const line = cpuFile.text().split("\n")[0];
    const fields = line.replace(/^\S+\s+/, "").split(/\s+/).map(Number);
    if (fields.length < 8) return;
    let total = 0;
    for (let i = 0; i < 8; i++) total += fields[i];
    const idle = fields[3] + fields[4];
    const dTotal = total - root.prevTotal;
    const dIdle = idle - root.prevIdle;
    root.prevTotal = total;
    root.prevIdle = idle;
    if (dTotal > 0) root.cpu = Math.round((1 - dIdle / dTotal) * 100);
  }

  // ---- memory ----
  property real mem: 0

  FileView {
    id: memFile
    path: "/proc/meminfo"
    watchChanges: true
    onFileChanged: root.readMem()
  }

  function readMem() {
    const text = memFile.text();
    const total = Number((text.match(/MemTotal:\s+(\d+)/) || [])[1]);
    const avail = Number((text.match(/MemAvailable:\s+(\d+)/) || [])[1]);
    if (total > 0 && !isNaN(avail)) root.mem = Math.round(((total - avail) / total) * 100);
  }

  // ---- temperature (coretemp hwmon, thermal_zone0 fallback) ----
  property string tempPath: ""
  property real temp: 0
  property bool tempOk: false

  Process {
    id: findTemp
    command: ["sh", "-c",
      "for d in /sys/class/hwmon/hwmon*; do [ \"$(cat $d/name 2>/dev/null)\" = coretemp ] && { echo $d/temp1_input; exit; }; done; echo /sys/class/thermal/thermal_zone0/temp"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.tempPath = this.text.trim()
    }
  }

  FileView {
    id: tempFile
    path: root.tempPath
    watchChanges: true
    onFileChanged: root.readTemp()
  }

  function readTemp() {
    if (root.tempPath === "") return;
    const t = Number(tempFile.text().trim());
    if (isNaN(t) || t <= 0) {
      root.tempOk = false;
      return;
    }
    root.temp = t / 1000;
    root.tempOk = true;
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.readCpu();
      root.readMem();
      root.readTemp();
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.gap

    Stat {
      glyph: String.fromCodePoint(0xF2DB) // nf-fa-microchip
      label: root.cpu + "%"
      tint: root.cpu >= 90 ? Theme.critical : root.cpu >= 80 ? Theme.warning : Theme.fg
    }
    Stat {
      glyph: String.fromCodePoint(0xF035B) // nf-md-memory
      label: root.mem + "%"
      tint: root.mem >= 90 ? Theme.critical : root.mem >= 80 ? Theme.warning : Theme.fg
    }
    Stat {
      visible: root.tempOk
      glyph: String.fromCodePoint(0xF050F) // nf-md-thermometer
      label: Math.round(root.temp) + "°C"
      tint: root.temp >= 80 ? Theme.critical : Theme.fg
    }
  }

  component Stat: Item {
    required property string glyph
    required property string label
    required property color tint

    implicitHeight: Theme.barHeight
    implicitWidth: glyphText.implicitWidth + (valueText.text !== "" ? 4 + valueText.implicitWidth : 0)

    Text {
      id: glyphText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: glyph
      color: tint
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }
    Text {
      id: valueText
      anchors.left: glyphText.right
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      text: label
      color: tint
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }
  }
}
