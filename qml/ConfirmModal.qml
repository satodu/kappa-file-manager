import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// Confirmação genérica (ex.: abrir um arquivo que pode executar código)
Item {
    id: root
    visible: false
    focus: visible

    property string kicker: ""
    property string title: ""
    property string message: ""
    property string detail: ""
    property string confirmLabel: ""
    property string glyph: "警"

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    signal confirmed()
    signal cancelled()

    function open() {
        root.visible = true;
        root.forceActiveFocus();
    }

    function close() { root.visible = false; }

    // O padrão é cancelar: Enter NÃO confirma, é preciso clicar em confirmar
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.cancelled();
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea { anchors.fill: parent; onClicked: root.cancelled() }
    }

    MultiEffect {
        source: dialog
        anchors.fill: dialog
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.65)
        shadowVerticalOffset: 14
        shadowBlur: 0.8
    }

    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: 460
        height: col.implicitHeight + 48
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: Qt.rgba(Tokens.sun.r, Tokens.sun.g, Tokens.sun.b, 0.6)

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: "transparent"
                    border.width: 1.5
                    border.color: Tokens.sun
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.glyph
                        font.family: Tokens.jp
                        font.pixelSize: 18
                        font.bold: true
                        color: Tokens.sun
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        spacing: 8
                        Text { textFormat: Text.PlainText; text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                        Text {
                            textFormat: Text.PlainText
                            text: root.kicker
                            font.family: Tokens.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 2.2
                            color: Tokens.sun
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.title
                        wrapMode: Text.WordWrap
                        font.family: Tokens.display
                        font.pixelSize: 20
                        color: KappaTheme.ink
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.message
                font.family: Tokens.ui
                font.pixelSize: 13
                color: KappaTheme.inkDim
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.detail !== ""
                implicitHeight: 38
                radius: Math.max(0, root.effectiveRadius - 2)
                color: KappaTheme.paper
                border.width: 1
                border.color: KappaTheme.line
                Text {
                    textFormat: Text.PlainText
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: root.detail
                    elide: Text.ElideMiddle
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.ink
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: KappaTheme.line }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 100
                    implicitHeight: 32
                    radius: root.effectiveRadius
                    color: KappaTheme.tint10
                    border.width: 1
                    border.color: KappaTheme.lineStrong
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.isPt ? "Cancelar" : "Cancel"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        font.bold: true
                        color: KappaTheme.ink
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }
                }

                Rectangle {
                    implicitWidth: okLabel.implicitWidth + 36
                    implicitHeight: 32
                    radius: root.effectiveRadius
                    color: "transparent"
                    border.width: 1
                    border.color: Tokens.sun
                    Text {
                        id: okLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.confirmLabel
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: Tokens.sun
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmed()
                    }
                }
            }
        }
    }
}
