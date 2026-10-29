import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

// Cartão que acompanha o ponteiro durante o arrasto de arquivos (vira a imagem do QDrag via grabToImage).
// Fica fora da tela no FileList; só serve de molde para a imagem.
Rectangle {
    id: root

    property string name: ""
    property bool isDir: false
    property int count: 1
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    width: 232
    height: 44
    radius: effectiveRadius
    color: KappaTheme.paperLift
    border.width: 1
    border.color: KappaTheme.sun

    // Ticks técnicos nos cantos, como na seleção do grid
    Repeater {
        model: 4
        delegate: Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            x: atRight ? root.width - 8 : 1
            y: atBottom ? root.height - 8 : 1
            width: 7
            height: 7
            Rectangle { width: 7; height: 1; color: KappaTheme.sun; y: parent.atBottom ? 6 : 0 }
            Rectangle { width: 1; height: 7; color: KappaTheme.sun; x: parent.atRight ? 6 : 0 }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 10

        Text {
            textFormat: Text.PlainText
            text: root.count > 1 ? "󰉓" : (root.isDir ? "󰉋" : "󰈔")
            font.family: Tokens.mono
            font.pixelSize: 16
            color: KappaTheme.sun
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.name
            elide: Text.ElideMiddle
            font.family: Tokens.ui
            font.pixelSize: 13
            color: KappaTheme.ink
        }

        // Mais de um item: contagem
        Rectangle {
            visible: root.count > 1
            implicitWidth: countText.implicitWidth + 12
            implicitHeight: 20
            radius: Math.min(root.effectiveRadius, 10)
            color: KappaTheme.sun
            Text {
                id: countText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.count
                font.family: Tokens.mono
                font.pixelSize: 11
                font.bold: true
                color: KappaTheme.inkOnBone
            }
        }
    }
}
