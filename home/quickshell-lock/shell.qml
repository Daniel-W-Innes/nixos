import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQml

// Lockscreen. Its own quickshell config, spawned on demand as
// `quickshell --config lock` by the hyprland keybind and the power menu.
// A separate process rather than a hidden window in the bar config: on-demand
// UI must not live in the bar process (lazy content build, docs/issues/08),
// and the session lock must outlive bar restarts — if this process dies while
// locked, the session stays locked.
//
// Password auth goes through the setuid pam_unix helper
// (/run/wrappers/bin/unix_chkpwd daniel nonull; exit 0 = correct, 7 = wrong),
// the same PAM check swaylock used. Wrong passwords take ~2s (pam_unix
// failure delay); Enter is ignored while a check is running.
//
// Recovery hatch: if the UI ever refuses to unlock, the lock can be released
// from a shell with
//   quickshell ipc -c lock call lock unlock
// This trades a bit of security (any process running as this user can unlock)
// for the ability to recover a stuck lock screen without a hard shutdown —
// for a single-user laptop that is a worthwhile trade.
//
// Design tokens mirror home/quickshell/Theme.qml, duplicated because
// home-manager installs each named config as its own ~/.config/quickshell/<name>
// directory, so the lock cannot import the bar's Theme.qml at runtime. Keep in
// sync when changing the theme.

ShellRoot {
  id: root

  // tokens (mirror Theme.qml)
  readonly property color bg: "#323232"
  readonly property color bgHover: "#3d3d3d"
  readonly property color border: "#454545"
  readonly property color fg: "#e8e8e8"
  readonly property color fgDim: "#9a9a9a"
  readonly property color accent: "#7aa2c8"
  readonly property color critical: "#e05252"
  readonly property string textFont: "Liberation Sans"
  readonly property string iconFont: "Symbols Nerd Font"

  // Must be a sibling of WlSessionLock, not a child: WlSessionLock's default
  // property is `surface` (a Component), and a child IpcHandler would become
  // the component root and break lock acquisition.
  IpcHandler {
    target: "lock"
    function unlock(): void { lock.locked = false }
  }

  WlSessionLock {
    id: lock
    locked: true

    // Fires on unlock and on failed acquisition (e.g. a compositor without
    // ext-session-lock): either way there is nothing left to render.
    onLockStateChanged: if (!lock.locked) Qt.quit()

    WlSessionLockSurface {
      color: root.bg

      Rectangle {
        anchors.fill: parent
        color: root.bg

        // Click anywhere to make sure the field has focus (fallback if the
        // surface did not get keyboard focus on show).
        MouseArea {
          anchors.fill: parent
          onClicked: input.forceActiveFocus()
        }

        Column {
          anchors.centerIn: parent
          spacing: 12

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(0xF033E) // lock glyph (same as the power menu)
            color: root.accent
            font.family: root.iconFont
            font.pixelSize: 44
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Locked"
            color: root.fg
            font.family: root.textFont
            font.pixelSize: 16
          }

          TextField {
            id: input
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220
            padding: 8
            focus: true
            placeholderText: "password"
            echoMode: TextInput.Password
            color: root.fg
            placeholderTextColor: root.fgDim
            font.family: root.textFont
            font.pixelSize: 14
            background: Rectangle {
              radius: 6
              color: root.bgHover
              border.width: 1
              border.color: root.border
            }
            onAccepted: submit()

            function submit() {
              // Ignore Enter while a check is running (wrong passwords take a
              // few seconds — pam_unix failure delay).
              if (check.running) return;
              if (text.length === 0) {
                showError("Enter your password");
                return;
              }
              console.log("lock: checking password");
              error.visible = false;
              check.password = text;
              check.command = ["/run/wrappers/bin/unix_chkpwd", "daniel", "nonull"];
              check.running = true;
            }

            function showError(msg) {
              error.text = msg;
              error.visible = true;
            }
          }

          Text {
            id: error
            anchors.horizontalCenter: parent.horizontalCenter
            visible: false
            text: "Wrong password"
            color: root.critical
            font.family: root.textFont
            font.pixelSize: 12
          }
        }
      }

      Process {
        id: check
        property string password: ""
        stdinEnabled: true
        // write() is a no-op until the process object exists, so wait for the
        // start signal instead of writing right after starting it.
        // The password must be NUL-terminated: pam_read_passwords reads until
        // a '\0', not a newline, and blocks forever if none arrives.
        onStarted: write(password + String.fromCharCode(0))
        onExited: (exitCode, exitStatus) => {
          // exitStatus 0 = NormalExit, 1 = CrashExit (includes failed-to-start).
          console.log("lock: unix_chkpwd exit", exitCode, "status", exitStatus);
          if (exitStatus === 0 && exitCode === 0) {
            lock.locked = false;
          } else {
            input.showError("Wrong password");
            input.text = "";
            input.forceActiveFocus();
          }
        }
      }
    }
  }
}
