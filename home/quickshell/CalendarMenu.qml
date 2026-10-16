import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQml

// Full-screen transparent surface with the calendar card anchored under the
// clock that was clicked. Only visible on the screen that opened it.
// The grid is Grid + Repeater (synchronous), not GridView: quickshell lazily
// builds hidden-window content and delegate views can skip delegate creation
// on the first show (the launcher saga, docs/issues/done/08).
PanelWindow {
  id: root
  // Set by the Variants delegate in shell.qml.
  property var modelData: null
  screen: modelData

  anchors { top: true; bottom: true; left: true; right: true }
  exclusiveZone: 0
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.layer: WlrLayer.Overlay

  // Set imperatively, not with a binding: a `visible` binding loops through
  // quickshell's internal window-visible tracking and can break before the
  // surface maps (verified 2026-10-15 — the window then never appears).
  visible: false

  Connections {
    target: Ui
    function onCalendarVisibleChanged() { syncVisible() }
    function onCalendarScreenChanged() { syncVisible() }

    function syncVisible() {
      root.visible = Ui.calendarVisible && Ui.calendarScreen === root.screen;
    }
  }

  property int viewYear: 0
  property int viewMonth: 0
  property var cells: []

  onVisibleChanged: if (visible) resetToToday()

  // Click anywhere outside the card to dismiss.
  MouseArea {
    anchors.fill: parent
    onClicked: Ui.closeCalendar()
  }

  Rectangle {
    // Centered under the clock, hovering padH below the bar. The anchor
    // arrives as the clock center's fraction of the bar width plus the bar's
    // geometry in bar units; unitScale converts them into this window's
    // coordinate space, so a HiDPI mismatch between the two windows (the
    // calendar can be sized in physical pixels while the bar is in DIP) can't
    // skew the position. The window itself starts below the bar's exclusive
    // zone, so its origin (screen height minus its own height — windows don't
    // expose x/y in QML) is subtracted; otherwise the bar height would count
    // twice and the card would sit a bar-height too low. Clamped so the card
    // keeps the padH gap from the screen edges, matching the power menu (the
    // clock is close to the right edge, where a centered card would
    // overflow it).
    readonly property real unitScale: Ui.calendarBarWidth > 0 ? parent.width / Ui.calendarBarWidth : 1
    readonly property real originY: root.screen ? root.screen.height - root.height : 0
    anchors { top: parent.top }
    anchors.topMargin: (Ui.calendarBarTop + Theme.padH) * unitScale - originY
    x: Math.min(Math.max(0, parent.width * Ui.calendarAnchorFrac - width / 2), parent.width - width - Theme.padH)
    width: 7 * Theme.calCell + 12
    height: column.implicitHeight + 12
    radius: Theme.radius
    color: Theme.bg
    border.width: 1
    border.color: Theme.border

    Column {
      id: column
      anchors.fill: parent
      anchors.margins: 6
      spacing: 4

      Row {
        width: parent.width
        height: Theme.calHeaderHeight

        NavButton { forward: false }
        Text {
          width: parent.width - 2 * Theme.calHeaderHeight
          height: Theme.calHeaderHeight
          text: Qt.formatDateTime(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
          color: Theme.fg
          font.family: Theme.textFont
          font.pixelSize: Theme.fontSize
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
        NavButton { forward: true }
      }

      Row {
        width: parent.width
        height: Theme.calWeekHeight

        Repeater {
          model: 7
          Text {
            width: Theme.calCell
            height: Theme.calWeekHeight
            text: Qt.locale().dayName((Qt.locale().firstDayOfWeek - 1 + index) % 7 + 1, Locale.ShortFormat)
            color: Theme.fgDim
            font.family: Theme.textFont
            font.pixelSize: Theme.fontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Grid {
        columns: 7

        Repeater {
          model: root.cells

          delegate: Item {
            required property var modelData

            width: Theme.calCell
            height: Theme.calCell

            Rectangle {
              anchors.fill: parent
              radius: Theme.chipRadius
              color: modelData && modelData.today
                ? Qt.alpha(Theme.accent, 0.25)
                : cellMouse.containsMouse ? Theme.bgHover : "transparent"
              Behavior on color {
                enabled: Theme.animations
                ColorAnimation { duration: Theme.fast }
              }
            }

            Text {
              anchors.centerIn: parent
              text: modelData ? modelData.day : ""
              color: modelData && modelData.today
                ? Theme.accent
                : modelData && modelData.inMonth ? Theme.fg : Theme.fgFaint
              font.family: Theme.textFont
              font.pixelSize: Theme.fontSize
            }

            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
            }
          }
        }
      }
    }
  }

  component NavButton: Item {
    required property bool forward

    width: Theme.calHeaderHeight
    height: Theme.calHeaderHeight

    Rectangle {
      id: chip
      anchors.centerIn: parent
      width: Theme.chipSize
      height: Theme.chipSize
      radius: Theme.chipRadius
      color: mouse.containsMouse ? Theme.bgHover : "transparent"
      Behavior on color {
        enabled: Theme.animations
        ColorAnimation { duration: Theme.fast }
      }
    }

    Text {
      anchors.centerIn: chip
      text: String.fromCodePoint(forward ? 0xF0142 : 0xF0141) // nf-md-chevron-right / -left
      color: Theme.fgDim
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: forward ? root.nextMonth() : root.prevMonth()
    }
  }

  function resetToToday() {
    const t = new Date();
    viewYear = t.getFullYear();
    viewMonth = t.getMonth();
    buildCells();
  }

  function prevMonth() {
    viewMonth--;
    if (viewMonth < 0) {
      viewMonth = 11;
      viewYear--;
    }
    buildCells();
  }

  function nextMonth() {
    viewMonth++;
    if (viewMonth > 11) {
      viewMonth = 0;
      viewYear++;
    }
    buildCells();
  }

  // 42 cells max: leading days of the previous month, the month itself,
  // trailing days to fill the last week.
  function buildCells() {
    const firstDow = (new Date(viewYear, viewMonth, 1).getDay() - (Qt.locale().firstDayOfWeek % 7) + 7) % 7;
    const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();
    const t = new Date();
    const todayKey = t.getFullYear() * 10000 + (t.getMonth() + 1) * 100 + t.getDate();
    const out = [];
    for (let i = 0; i < firstDow; i++) {
      out.push({ day: new Date(viewYear, viewMonth, 1 - (firstDow - i)).getDate(), inMonth: false, today: false });
    }
    for (let d = 1; d <= daysInMonth; d++) {
      const key = viewYear * 10000 + (viewMonth + 1) * 100 + d;
      out.push({ day: d, inMonth: true, today: key === todayKey });
    }
    for (let i = 1; out.length % 7 !== 0; i++) {
      out.push({ day: new Date(viewYear, viewMonth + 1, i).getDate(), inMonth: false, today: false });
    }
    cells = out;
  }
}
