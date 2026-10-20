import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    height: 36
    color: KappaTheme.paper

    property int totalItems: 0
    property var selectedItem: null
    property int selectedCount: 0
    property string transferState: "idle"
    property real transferFraction: 0
    property string transferMode: "copy"
    readonly property bool transferring: root.transferState === "running" || root.transferState === "paused"
    readonly property bool isPt: I18n.lang.startsWith("pt")

    signal themeClicked()

    // Linha superior hairline
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: KappaTheme.line

        Rectangle {
            visible: root.transferring
            anchors.top: parent.top
            anchors.left: parent.left
            height: 2
            width: parent.width * root.transferFraction
            color: KappaTheme.sun
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 16

        // Contador de itens (ou progresso da transferência)
        Text {
            textFormat: Text.PlainText
            text: root.transferring
                  ? ((root.transferMode === "move" ? (root.isPt ? "Movendo · " : "Moving · ")
                     : root.transferMode === "compress" ? (root.isPt ? "Comprimindo · " : "Compressing · ")
                     : root.transferMode === "extract" ? (root.isPt ? "Extraindo · " : "Extracting · ")
                     : (root.isPt ? "Copiando · " : "Copying · ")) + Math.round(root.transferFraction * 100) + "%")
                  : root.totalItems + (root.isPt ? " itens" : " items")
            font.family: Tokens.ui
            font.pixelSize: 12
            color: root.transferring ? KappaTheme.sun : KappaTheme.inkDim
        }

        // Detalhe do item selecionado (estilo: "1 selecionado · wallpaper.png · 4,2 MB")
        Text {
            textFormat: Text.PlainText
            text: {
                if (!root.selectedItem) return "";
                if (root.selectedCount > 1) {
                    return root.selectedCount + (root.isPt ? " selecionados" : " selected");
                }
                var sizePart = root.selectedItem.is_dir ? "" : (" · " + root.selectedItem.size_formatted);
                var prefix = root.isPt ? "1 selecionado · " : "1 selected · ";
                return prefix + root.selectedItem.name + sizePart;
            }
            font.family: Tokens.ui
            font.pixelSize: 12
            color: KappaTheme.ink
            visible: root.selectedItem !== null
        }

        Item { Layout.fillWidth: true }

        // Indicador de Tema: abre o diálogo de Aparência
        RowLayout {
            id: themeIndicator
            spacing: 6

            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: KappaTheme.sun
            }

            Text {
                textFormat: Text.PlainText
                text: KappaTheme.fixed
                      ? (root.isPt ? "Tema: fixo · " : "Theme: fixed · ") + KappaTheme.summary
                      : (root.isPt ? "Tema: segue o wallpaper" : "Theme: follows wallpaper")
                font.family: Tokens.ui
                font.pixelSize: 12
                color: themeArea.containsMouse ? KappaTheme.ink : KappaTheme.inkDim
            }

            MouseArea {
                id: themeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.themeClicked()
            }
        }
    }
}
