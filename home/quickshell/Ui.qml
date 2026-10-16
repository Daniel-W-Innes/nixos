pragma Singleton

import Quickshell
import QtQuick

// Cross-window state: the bar, the OSD and the power menu are separate
// windows, so widgets signal through this singleton instead of holding
// references to each other.
Singleton {
  property bool osdVisible: false
  property string osdKind: "volume" // "volume" | "brightness"
  property real osdValue: 0 // 0..1
  property bool osdMuted: false
  property bool menuVisible: false
  property var menuScreen: null
  property bool calendarVisible: false
  property var calendarScreen: null
  // Anchor of the calendar card under the clock, all expressed in the bar
  // window's own units on click: the clock's horizontal center as a fraction
  // of the bar width, plus the bar's size and its bottom edge on screen. The
  // calendar window resolves these against its own geometry, so HiDPI
  // windows that end up in different pixel spaces (physical vs DIP) still
  // anchor correctly.
  property real calendarAnchorFrac: 0
  property real calendarBarWidth: 0
  property real calendarBarHeight: 0
  // Screen y of the bar's bottom edge, in bar units (the bar is top-anchored
  // at y=0, so this equals its height). The calendar derives the overlay
  // window's own origin from its screen geometry.
  property real calendarBarTop: 0

  function showVolume(value, muted) {
    osdKind = "volume";
    osdValue = value;
    osdMuted = muted;
    osdVisible = true;
    hold.restart();
  }

  function showBrightness(value) {
    osdKind = "brightness";
    osdValue = value;
    osdMuted = false;
    osdVisible = true;
    hold.restart();
  }

  function toggleMenu(screen) {
    calendarVisible = false;
    menuScreen = screen;
    menuVisible = !menuVisible;
  }

  function closeMenu() {
    menuVisible = false;
  }

  function toggleCalendar(screen, anchorFrac, barWidth, barHeight, barTop) {
    menuVisible = false;
    calendarScreen = screen;
    calendarAnchorFrac = anchorFrac;
    calendarBarWidth = barWidth;
    calendarBarHeight = barHeight;
    calendarBarTop = barTop;
    calendarVisible = !calendarVisible;
  }

  function closeCalendar() {
    calendarVisible = false;
  }

  Timer {
    id: hold
    interval: Theme.osdHold
    repeat: false
    onTriggered: osdVisible = false
  }
}
