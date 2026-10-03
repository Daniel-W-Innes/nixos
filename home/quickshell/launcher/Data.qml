pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "scripts/fzf.js" as Fzf

// All launcher state and logic, UI-free. One instance per launcher process
// (the process quits on every close, so state is rebuilt each open).
Singleton {
  id: root

  // Launch-frequency state, plain JSON in the user state dir. Read via cat
  // and written through a one-line sh pipeline — coreutils only, no C++.
  readonly property string stateDir: "/home/daniel/.local/state/quickshell"
  readonly property string stateFile: stateDir + "/launcher-freq.json"
  property var freq: ({})

  // --- search ---

  property string query: ""

  readonly property string mode: {
    if (query.startsWith(">calc "))
      return "calc";
    if (query.startsWith(">"))
      return "actions";
    return "apps";
  }

  // "@k " / "@g " scope the search to keywords / genericName; otherwise all
  // three fields are searched together (the selector order weights name
  // matches first, fzf-style).
  readonly property string appQuery: mode === "apps"
    ? (query.startsWith("@k ") || query.startsWith("@g ") ? query.slice(3) : query)
    : ""

  readonly property var allApps: DesktopEntries.applications.values

  readonly property var finder: new Fzf.Finder(allApps, {
    selector: e => {
      if (query.startsWith("@k "))
        return e.keywords.join(" ") + " " + e.name;
      if (query.startsWith("@g "))
        return e.genericName + " " + e.name;
      return e.name + " " + e.genericName + " " + e.keywords.join(" ");
    }
  })

  // fzf score first; on ties, most-launched first, then shorter names.
  readonly property var appMatches: {
    const q = appQuery.trim();
    const hits = q
      ? finder.find(q)
      : [...allApps].map(item => ({ item, score: 0 }));
    return hits.sort((a, b) => {
      if (b.score !== a.score)
        return b.score - a.score;
      const fa = freq[a.item.id] || 0;
      const fb = freq[b.item.id] || 0;
      if (fa !== fb)
        return fb - fa;
      return a.item.name.trim().length - b.item.name.trim().length;
    }).map(r => r.item);
  }

  // --- actions (> prefix) ---

  // Glyphs verified against the Symbols Nerd Font cmap; commands mirror the
  // power menu.
  readonly property var actions: [
    { name: "Calculator", glyph: String.fromCodePoint(0xF00EC), behavior: "autocomplete" },
    { name: "Lock", glyph: String.fromCodePoint(0xF033E), cmd: ["quickshell", "--config", "lock"] },
    { name: "Suspend", glyph: String.fromCodePoint(0xF0904), cmd: ["systemctl", "suspend"] },
    { name: "Reboot", glyph: String.fromCodePoint(0xF0709), cmd: ["systemctl", "reboot"] },
    { name: "Shut down", glyph: String.fromCodePoint(0xF0425), cmd: ["systemctl", "poweroff"] },
    { name: "Log out", glyph: String.fromCodePoint(0xF0343), cmd: ["hyprctl", "dispatch", "exit"] },
  ]

  readonly property var actionFinder: new Fzf.Finder(actions, { selector: a => a.name })

  readonly property var actionMatches: {
    const q = query.slice(1).trim();
    return q ? actionFinder.find(q).map(r => r.item) : [...actions];
  }

  // --- calc (>calc prefix) ---

  readonly property string expr: mode === "calc" ? query.slice(6).trim() : ""
  property string calcResult: ""
  property bool calcPending: false
  property bool calcError: false
  property string calcExpr: "" // expr captured when the last eval started

  onExprChanged: {
    calcPending = false;
    calcError = false;
    calcResult = "";
    debounce.restart();
  }

  Timer {
    id: debounce
    interval: 150
    repeat: false
    onTriggered: root.evalCalc()
  }

  function evalCalc() {
    if (!root.expr)
      return;
    root.calcExpr = root.expr;
    root.calcPending = true;
    root.calcError = false;
    calcProc.running = true;
  }

  Process {
    id: calcProc
    command: ["qalc", "-t", root.calcExpr]
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.calcExpr !== root.expr)
          return; // stale run
        root.calcPending = false;
        const out = text.trim();
        if (out) {
          root.calcResult = out;
          root.calcError = false;
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.calcExpr !== root.expr)
        return;
      root.calcPending = false;
      if (exitCode !== 0)
        root.calcError = true;
    }
  }

  // --- what the list shows ---

  readonly property var matches: {
    switch (mode) {
    case "actions": return actionMatches;
    case "calc": return [{ kind: "calc" }]; // single pseudo row
    default: return appMatches;
    }
  }

  // Returns true if the launcher should close after this item.
  function activate(item): bool {
    if (mode === "calc") {
      if (calcResult)
        Quickshell.execDetached(["wl-copy", calcResult]);
      return true;
    }
    if (mode === "actions") {
      if (item.behavior === "autocomplete") {
        query = ">calc ";
        return false;
      }
      Quickshell.execDetached(item.cmd);
      return true;
    }
    if (item.runInTerminal)
      // execute() ignores Terminal=true, so wrap terminal apps ourselves.
      Quickshell.execDetached(["alacritty", "-e", ...item.command]);
    else
      item.execute();
    recordLaunch(item.id);
    return true;
  }

  function openInQalc(): bool {
    if (expr)
      Quickshell.execDetached(["alacritty", "-e", "qalc", "-i", expr]);
    return true;
  }

  // --- frequency persistence ---

  function recordLaunch(id) {
    freq[id] = (freq[id] || 0) + 1;
    saveFreq.running = true;
  }

  Process {
    id: loadFreq
    running: true
    command: ["sh", "-c", "test -f \"$1\" && cat \"$1\"", "sh", root.stateFile]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const parsed = JSON.parse(text);
          if (parsed && typeof parsed === "object")
            root.freq = parsed;
        } catch (e) {
          // Missing/corrupt state file → start fresh.
        }
      }
    }
  }

  // sh reads one line from stdin (this avoids shell-quoting the JSON) and
  // writes it to the state file.
  Process {
    id: saveFreq
    command: ["sh", "-c", "mkdir -p \"$1\" && read -r line && printf '%s' \"$line\" > \"$1/launcher-freq.json\"", "sh", root.stateDir]
    stdinEnabled: true
    // write() is a no-op until the process object exists, so wait for the
    // started signal (same pattern as the lock config).
    onStarted: write(JSON.stringify(root.freq) + "\n")
  }
}
