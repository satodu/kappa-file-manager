import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

ShellRoot {
    // Recarregar ao mudar arquivo só no desenvolvimento (run.sh exporta KAPPA_DEV=1)
    Component.onCompleted: Quickshell.watchFiles = Quickshell.env("KAPPA_DEV") === "1"

    FloatingWindow {
        id: win
        title: "Kappa / Arquivos"
        implicitWidth: 1440
        implicitHeight: 900
        minimumSize: Qt.size(980, 640)
        color: "transparent"

        // Fechar a janela encerra o processo. Sem isto o Quickshell segue vivo sem janela e, quando os QML
        // mudam (atualização do pacote), recarrega e reabre cada janela já fechada.
        onClosed: Qt.quit()

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
