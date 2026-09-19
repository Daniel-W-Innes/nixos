import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

// App launcher (replaces wofi). Full-screen transparent overlay, one per
// screen, only visible on the focused monitor. Toggled from the hyprland
// keybind via IPC (IpcHandler in shell.qml). Unlike the OSD this window is
// focusable — it needs keyboard input for the search field.
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
  focusable: true

  property real contentOpacity: 0
  visible: contentOpacity > 0
  Behavior on contentOpacity { NumberAnimation { duration: Theme.fast } }

  // Maximum list rows that fit under the list height cap.
  readonly property int maxRows: Math.max(1, Math.floor(
    (root.screen.height * Theme.launcherMaxListFraction
      - Theme.launcherSearchHeight - 24) / Theme.launcherRowHeight))

  // All launchable entries, sorted by name. Rebuilt when quickshell's
  // desktop-entry monitor picks up changes.
  property var allEntries: {
    const arr = [];
    for (const e of DesktopEntries.applications.values) {
      if (!e.noDisplay && e.command.length > 0) arr.push(e);
    }
    arr.sort((a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1);
    return arr;
  }

  // Subsequence fuzzy match: consecutive matches and word starts score
  // higher; a query that is not a subsequence scores -1 (excluded).
  // Spaces in the query are ignored, so "fi re" matches "Firefox".
  function fuzzyScore(query, text) {
    if (query === "") return 1;
    if (text === "") return -1;
    const t = text.toLowerCase();
    let q = 0, score = 0, run = 0;
    for (let i = 0; i < t.length && q < query.length; i++) {
      if (t[i] === query[q]) {
        score += run > 0 ? 4 : 1;
        if (i === 0 || t[i - 1] === " " || t[i - 1] === "-"
          || t[i - 1] === "." || t[i - 1] === "_") score += 3;
        run++;
        q++;
      } else {
        run = 0;
      }
    }
    return q === query.length ? score : -1;
  }

  function scoreEntry(entry, query) {
    let best = -1;
    const fields = [entry.name, entry.genericName].concat(entry.keywords || []);
    for (const f of fields) {
      if (!f) continue;
      best = Math.max(best, root.fuzzyScore(query, f));
    }
    return best;
  }

  property var matches: {
    const q = field.text.trim().toLowerCase().replace(/ /g, "");
    if (q === "") return root.allEntries.slice(0, Theme.launcherMaxResults);
    const scored = [];
    for (const e of root.allEntries) {
      const s = root.scoreEntry(e, q);
      if (s >= 0) scored.push([s, e]);
    }
    scored.sort((a, b) => b[0] !== a[0] ? b[0] - a[0]
      : (a[1].name.toLowerCase() < b[1].name.toLowerCase() ? -1 : 1));
    return scored.slice(0, Theme.launcherMaxResults).map(x => x[1]);
  }

  function launch(entry) {
    Ui.closeLauncher();
    if (!entry) return;
    // quickshell's DesktopEntry.execute() ignores Terminal=true, so run
    // those in the terminal ourselves.
    if (entry.runInTerminal) Quickshell.execDetached(["alacritty", "-e"].concat(entry.command));
    else entry.execute();
  }

  function move(delta) {
    const n = root.matches.length;
    if (n === 0) {
      list.currentIndex = -1;
      return;
    }
    let i = list.currentIndex === -1 ? 0 : list.currentIndex + delta;
    i = Math.max(0, Math.min(n - 1, i));
    list.currentIndex = i;
    list.positionViewAtIndex(i, ListView.Contain);
  }

  Connections {
    target: Ui
    function onLauncherVisibleChanged() {
      const show = Ui.launcherVisible && Hyprland.monitorFor(root.screen) === Hyprland.focusedMonitor;
      root.contentOpacity = show ? 1 : 0;
      if (show) {
        field.text = "";
        field.forceActiveFocus();
        // quickshell lazily creates a window's content on its first show,
        // and the ListView can skip building delegates for that first
        // frame, leaving the results area empty. Bumping the model forces
        // the view to rebuild now that the window is visible.
        list.model = null;
        list.model = root.matches;
      }
    }
  }

  Item {
    anchors.fill: parent
    opacity: root.contentOpacity

    // Click anywhere outside the card to dismiss.
    MouseArea {
      anchors.fill: parent
      onClicked: Ui.closeLauncher()
    }

    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * Theme.launcherTopFraction
      width: Math.min(Theme.launcherWidth, parent.width - 2 * Theme.padH)
      height: Theme.launcherSearchHeight + list.height + 24
      radius: Theme.radius
      color: Theme.bg
      border.width: 1
      border.color: Theme.border

      // Swallow clicks on the card background (they must not dismiss).
      MouseArea { anchors.fill: parent }

      TextField {
        id: field
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        height: Theme.launcherSearchHeight
        placeholderText: "Search"
        color: Theme.fg
        placeholderTextColor: Theme.fgFaint
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSize
        leftPadding: Theme.padH
        rightPadding: Theme.padH
        verticalAlignment: TextInput.AlignVCenter
        background: Rectangle {
          radius: Theme.chipRadius
          color: Theme.bgHover
        }
        onTextChanged: {
          list.currentIndex = 0;
          list.positionViewAtIndex(0, ListView.Beginning);
        }
        Keys.onPressed: (event) => {
          switch (event.key) {
            case Qt.Key_Up: root.move(-1); event.accepted = true; break;
            case Qt.Key_Down: root.move(1); event.accepted = true; break;
            case Qt.Key_Return:
            case Qt.Key_Enter: root.launch(root.matches[list.currentIndex]); event.accepted = true; break;
            case Qt.Key_Escape: Ui.closeLauncher(); event.accepted = true; break;
          }
        }
      }

      ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: field.bottom; leftMargin: 4; rightMargin: 4; topMargin: 4 }
        height: Math.min(root.matches.length, root.maxRows) * Theme.launcherRowHeight
        // Plain JS array, not ScriptModel: the array is tiny (<= 25 entries) and
        // ScriptModel's deferred diffing left the list empty for a moment after
        // the window became visible. Recreating delegates per keystroke is cheap
        // at this scale and the data is there on the first frame.
        model: root.matches
        delegate: RowComponent
        currentIndex: -1
        clip: true
        boundsBehavior: Flickable.StopAtBounds
      }

      Text {
        // Distinguish "desktop-file scan still running" (right after login)
        // from a genuinely empty search result.
        visible: root.matches.length === 0
        anchors { horizontalCenter: parent.horizontalCenter; top: field.bottom; topMargin: 12 }
        text: DesktopEntries.applications.values.length === 0 ? "Loading…" : "No matches"
        color: Theme.fgFaint
        font.family: Theme.textFont
        font.pixelSize: Theme.fontSize
      }
    }
  }

  component RowComponent: Item {
    // The model value is the DesktopEntry itself, exposed as modelData.
    property var modelData: null
    height: Theme.launcherRowHeight

    Rectangle {
      anchors.fill: parent
      radius: Theme.chipRadius
      color: (mouse.containsMouse || index === list.currentIndex) ? Theme.bgHover : "transparent"
      Behavior on color {
        enabled: Theme.animations
        ColorAnimation { duration: Theme.fast }
      }
    }

    IconImage {
      id: icon
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      implicitSize: 24
      source: Quickshell.iconPath(modelData.icon, true)
    }

    Text {
      // Fallback glyph when the entry has no resolvable icon.
      visible: icon.source === ""
      anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
      width: 24
      horizontalAlignment: Text.AlignHCenter
      text: String.fromCodePoint(0xF08C6) // nf-md-application
      color: Theme.fgDim
      font.family: Theme.iconFont
      font.pixelSize: Theme.iconSize + 6
    }

    Text {
      anchors {
        left: parent.left
        leftMargin: 48
        right: parent.right
        rightMargin: 12
        verticalCenter: parent.verticalCenter
      }
      text: modelData.name
      color: Theme.fg
      elide: Text.ElideRight
      font.family: Theme.textFont
      font.pixelSize: Theme.fontSize
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.launch(modelData)
    }
  }
}
