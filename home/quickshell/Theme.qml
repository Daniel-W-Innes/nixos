pragma Singleton

import Quickshell
import QtQuick

// Design tokens for the bar. Constants only, no logic.
Singleton {
  // palette
  readonly property color bg: "#323232"
  readonly property color bgHover: "#3d3d3d"
  readonly property color border: "#454545"
  readonly property color fg: "#e8e8e8"
  readonly property color fgDim: "#9a9a9a"
  readonly property color fgFaint: "#5f5f5f"
  readonly property color accent: "#7aa2c8"
  readonly property color warning: "#d9a05b"
  readonly property color critical: "#e05252"
  readonly property color urgent: "#c9545d"

  // metrics
  readonly property int barHeight: 34
  readonly property int radius: 10
  readonly property int padH: 12
  readonly property int gap: 14
  readonly property int fontSize: 13
  readonly property int iconSize: 14
  readonly property int dotSize: 8
  readonly property int pillWidth: 22
  readonly property int chipRadius: 6
  readonly property int osdWidth: 210
  readonly property int osdHeight: 40

  // fonts
  readonly property string textFont: "Liberation Sans"
  readonly property string iconFont: "Symbols Nerd Font"

  // motion (subtle only — Hyprland animations are disabled, keep it quiet)
  readonly property bool animations: true
  readonly property int fast: 120
  readonly property int osdFade: 150
  readonly property int osdHold: 1500
}
