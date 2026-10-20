import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: seal

    property string title: "KAPPA"
    property string glyph: "河"
    property string date: "2026"
    property real size: 84
    property color ink: KappaTheme.sun
    property real inkOpacity: 0.85

    width: size
    height: size

    readonly property string _ringText: {
        var t = (seal.title || "KAPPA").toUpperCase().trim();
        return t + " · 力 · " + t + " · 力 · ";
    }

    rotation: -4
    opacity: seal.inkOpacity

    // Anéis estampados
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, seal.size * 0.032)
        border.color: seal.ink
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: seal.size * 0.16
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(seal.ink.r, seal.ink.g, seal.ink.b, 0.6)
    }

    // Texto ao redor do anel
    Repeater {
        model: seal._ringText.length
        delegate: Item {
            required property int index
            anchors.fill: parent
            rotation: (360 / seal._ringText.length) * index
            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                y: seal.size * 0.035
                text: seal._ringText.charAt(index)
                color: seal.ink
                font.family: Tokens.ui
                font.pixelSize: Math.max(7, seal.size * 0.09)
                font.bold: true
                font.letterSpacing: 1
            }
        }
    }

    // Kanji central + micro data
    Column {
        anchors.centerIn: parent
        spacing: 0
        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: seal.glyph
            color: seal.ink
            font.family: Tokens.jp
            font.pixelSize: seal.size * 0.36
            font.bold: true
        }
        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: seal.date.length > 0
            text: seal.date
            color: seal.ink
            font.family: Tokens.mono
            font.pixelSize: Math.max(6, seal.size * 0.08)
            font.letterSpacing: 0.5
        }
    }
}
