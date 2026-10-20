import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

ShellRoot {
    FloatingWindow {
        id: win
        title: "Kappa / Arquivos"
        implicitWidth: 1440
        implicitHeight: 900
        minimumSize: Qt.size(980, 640)
        color: "transparent"

        App {
            id: appView
            anchors.fill: parent
            focus: true
        }

        Component.onCompleted: {
            appView.forceActiveFocus();
        }
    }
}
