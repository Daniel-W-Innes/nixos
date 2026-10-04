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
  // and written through a detached sh — coreutils only, no C++.
  readonly property string stateDir: "/home/daniel/.local/state/quickshell"
  readonly property string stateFile: stateDir + "/launcher-freq.json"
  property var freq: ({})

  // --- search ---

  property string query: ""

  // Answer modes: one-shot CLI tools that compute a result inline in the
  // launcher (like the calculator). slice = where the typed argument starts.
  // Glyphs verified against the Symbols Nerd Font cmap.
  readonly property var queryModes: ({
    calc: { prefix: ">calc ", slice: 6, icon: 0xF00EC, hint: "Type an expression", args: e => ["qalc", "-t", e], chip: true },
    ipcalc: { prefix: ">ipcalc ", slice: 8, icon: 0xF0A60, hint: "Type an address", args: e => ["ipcalc", e], chip: false }, // md-ip_network
    dig: { prefix: ">dig ", slice: 5, icon: 0xF01D6, hint: "Type a domain", args: e => ["dig", "+short", e], chip: false }, // md-dns
    jq: { prefix: ">jq ", slice: 4, icon: 0xF0626, hint: "Type a jq expression", args: e => ["sh", "-c", "wl-paste | jq -r \"$1\"", "sh", e], chip: false }, // md-code_json, reads the clipboard as JSON
  })

  readonly property string mode: {
    for (const key in queryModes)
      if (query.startsWith(queryModes[key].prefix))
        return key;
    if (query.startsWith(">"))
      return "actions";
    return "apps";
  }

  readonly property var currentQueryMode: mode !== "apps" && mode !== "actions" ? queryModes[mode] : null

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

  // Glyphs verified against the Symbols Nerd Font cmap; power commands
  // mirror the power menu. behavior: "autocomplete" moves the query into an
  // answer mode instead of executing.
  readonly property var actions: [
    { name: "Calculator", glyph: String.fromCodePoint(0xF00EC), behavior: "autocomplete", target: ">calc " },
    { name: "IP calculator", glyph: String.fromCodePoint(0xF0A60), behavior: "autocomplete", target: ">ipcalc " },
    { name: "DNS lookup", glyph: String.fromCodePoint(0xF01D6), behavior: "autocomplete", target: ">dig " },
    { name: "jq", glyph: String.fromCodePoint(0xF0626), behavior: "autocomplete", target: ">jq " },
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

  // --- answer modes (calc/ipcalc/dig/jq) ---

  readonly property string expr: currentQueryMode ? query.slice(currentQueryMode.slice).trim() : ""
  readonly property string modeGlyph: currentQueryMode ? String.fromCodePoint(currentQueryMode.icon) : ""
  readonly property string modeHint: currentQueryMode ? currentQueryMode.hint : ""
  property string answer: ""
  property bool answerPending: false
  property bool answerError: false
  property string answerKey: "" // "mode|expr" captured when the last eval started

  // Multi-line results (ipcalc, dig) display as one line in the row.
  readonly property string answerLine: answer.replace(/\n/g, " · ")

  onExprChanged: {
    answerPending = false;
    answerError = false;
    answer = "";
    debounce.restart();
  }

  Timer {
    id: debounce
    interval: 150
    repeat: false
    onTriggered: root.evalQuery()
  }

  function evalQuery() {
    if (!root.expr)
      return;
    root.answerKey = root.mode + "|" + root.expr;
    root.answerPending = true;
    root.answerError = false;
    queryProc.running = true;
  }

  Process {
    id: queryProc
    command: root.currentQueryMode ? root.currentQueryMode.args(root.expr) : []
    stdout: StdioCollector {
      onStreamFinished: {
        if (root.answerKey !== root.mode + "|" + root.expr)
          return; // stale run
        root.answerPending = false;
        const out = text.trim();
        if (out) {
          root.answer = out;
          root.answerError = false;
        }
      }
    }
    onExited: (exitCode, exitStatus) => {
      if (root.answerKey !== root.mode + "|" + root.expr)
        return;
      root.answerPending = false;
      if (exitCode !== 0)
        root.answerError = true;
    }
  }

  // --- what the list shows ---

  readonly property var matches: {
    if (mode === "actions")
      return actionMatches;
    if (mode !== "apps")
      return [{ kind: mode }]; // single answer row
    return appMatches;
  }

  // Returns true if the launcher should close after this item.
  function activate(item): bool {
    if (mode !== "apps" && mode !== "actions") {
      if (answer)
        Quickshell.execDetached(["wl-copy", answer]);
      return true;
    }
    if (mode === "actions") {
      if (item.behavior === "autocomplete") {
        query = item.target;
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
    // Detached, because the launcher quits right after launching: a regular
    // Process child gets killed by its destructor during engine teardown
    // (quickshell 0.3.0 Process::~Process calls kill()), losing the write.
    // The JSON travels as a positional arg, so no shell quoting is involved.
    Quickshell.execDetached([
      "sh", "-c",
      "mkdir -p \"$2\" && printf '%s' \"$1\" > \"$2/launcher-freq.json\"",
      "sh",
      JSON.stringify(freq),
      stateDir,
    ]);
  }

  Process {
    id: loadFreq
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

  // quickshell 0.3.0 never starts Processes created during config load (no
  // started/exited/stream signals fire at all — verified). Start from a
  // Timer like the calc debounce instead.
  Timer {
    interval: 100
    running: true
    repeat: false
    onTriggered: loadFreq.running = true
  }
}
