import Quickshell
import Quickshell.Io
import QtQml

// One shell process hosts the bar, the OSD, the power menu and the app
// launcher — one instance of each per monitor. QML windows cannot nest, so
// they are siblings here and communicate through the Ui singleton.
ShellRoot {
  id: shell

  // The launcher is toggled from a hyprland keybind:
  //   quickshell ipc -c main call launcher toggle
  // Lives here (not in Launcher.qml) because there is one Launcher per
  // screen and IpcHandler targets must be unique.
  IpcHandler {
    target: "launcher"
    function toggle(): void { Ui.toggleLauncher(); }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      Bar { screen: modelData }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      Osd { screen: modelData }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PowerMenu { screen: modelData }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      Launcher { screen: modelData }
    }
  }
}
