import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// Modal de renomeação (F2 e "Nova pasta"), no mesmo desenho dos modais de exclusão e aparência
Item {
    id: root
    visible: active

    property bool active: false
    property var target: null
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    signal submitted(string newName)
    signal cancelled()

    function open(item) {
        root.target = item;
        nameInput.text = item ? item.name : "";
        nameInput.forceActiveFocus();
        // Seleciona só o nome, sem a extensão (como em gerenciadores de arquivos comuns)
        var dot = (item && !item.is_dir) ? nameInput.text.lastIndexOf(".") : -1;
        nameInput.select(0, dot > 0 ? dot : nameInput.text.length);
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
        width: 440
        height: col.implicitHeight + 48
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: KappaTheme.lineStrong

        MouseArea { anchors.fill: parent }

        Repeater {
            model: 4
            delegate: Item {
                required property int index
                readonly property bool atRight: index % 2 === 1
                readonly property bool atBottom: index >= 2
                x: atRight ? dialog.width - 13 : 6
                y: atBottom ? dialog.height - 13 : 6
                width: 7
                height: 7
                Rectangle { width: 7; height: 1; color: KappaTheme.sun; y: parent.atBottom ? 6 : 0 }
                Rectangle { width: 1; height: 7; color: KappaTheme.sun; x: parent.atRight ? 6 : 0 }
            }
        }

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
                    border.color: KappaTheme.sun
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "名"
                        font.family: Tokens.jp
                        font.pixelSize: 18
                        font.bold: true
                        color: KappaTheme.sun
                    }
                }

                ColumnLayout {
                    spacing: 3
                    RowLayout {
                        spacing: 8
                        Text { textFormat: Text.PlainText; text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                        Text {
                            textFormat: Text.PlainText
                            text: root.isPt ? "RENOMEAR_" : "RENAME_"
                            font.family: Tokens.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 2.2
                            color: KappaTheme.sun
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "Novo nome" : "New name"
                        font.family: Tokens.display
                        font.pixelSize: 20
                        color: KappaTheme.ink
                    }
                }

                Item { Layout.fillWidth: true }
                Text { textFormat: Text.PlainText; text: "esc"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim; Layout.alignment: Qt.AlignTop }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: Math.max(0, root.effectiveRadius - 2)
                color: KappaTheme.paper
                border.width: 1
                border.color: nameInput.activeFocus ? KappaTheme.sun : KappaTheme.line

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: KappaTheme.ink
                    selectionColor: KappaTheme.sun
                    selectedTextColor: KappaTheme.inkOnBone
                    selectByMouse: true
                    font.family: Tokens.ui
                    font.pixelSize: 14
                    clip: true

                    Keys.onReturnPressed: root.submitted(text)
                    Keys.onEnterPressed: root.submitted(text)
                    Keys.onEscapePressed: root.cancelled()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: KappaTheme.line }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    textFormat: Text.PlainText
                    text: "Enter"
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.inkDim
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 88
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: cancelArea.containsMouse ? KappaTheme.tint10 : "transparent"
                    border.width: 1
                    border.color: KappaTheme.line
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.isPt ? "Cancelar" : "Cancel"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: KappaTheme.inkDim
                    }
                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }
                }

                Rectangle {
                    implicitWidth: okLabel.implicitWidth + 36
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: KappaTheme.sun
                    Text {
                        textFormat: Text.PlainText
                        id: okLabel
                        anchors.centerIn: parent
                        text: root.isPt ? "Renomear" : "Rename"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        font.bold: true
                        color: KappaTheme.inkOnBone
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submitted(nameInput.text)
                    }
                }
            }
        }
    }
}
