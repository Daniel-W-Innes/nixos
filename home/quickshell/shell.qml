import Quickshell
import QtQml

// One shell process hosts the bar, the OSD and the power menu — one instance
// of each per monitor. QML windows cannot nest, so they are siblings here
// and communicate through the Ui singleton.
ShellRoot {
  id: shell

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
}
