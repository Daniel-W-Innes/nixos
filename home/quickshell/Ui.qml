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
  property bool launcherVisible: false

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
    menuScreen = screen;
    menuVisible = !menuVisible;
  }

  function closeMenu() {
    menuVisible = false;
  }

  function toggleLauncher() {
    launcherVisible = !launcherVisible;
  }

  function closeLauncher() {
    launcherVisible = false;
  }

  Timer {
    id: hold
    interval: Theme.osdHold
    repeat: false
    onTriggered: osdVisible = false
  }
}
