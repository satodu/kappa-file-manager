import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// Soltar arquivos numa pasta: pergunta se é para copiar ou mover. Cancelar é o padrão (Enter não faz nada).
Item {
    id: root
    visible: active
    focus: visible

    property bool active: false
    property var paths: []
    property string destDir: ""

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    readonly property string firstName: root.paths.length > 0 ? root.paths[0].split("/").pop() : ""
    readonly property string destName: root.destDir === "/" ? "/" : root.destDir.split("/").pop()

    signal chosen(string mode)
    signal cancelled()

    function open() { root.forceActiveFocus(); }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.cancelled();
        else if (event.key === Qt.Key_C && event.modifiers === Qt.NoModifier) root.chosen("copy");
        else if (event.key === Qt.Key_M && event.modifiers === Qt.NoModifier) root.chosen("move");
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
                        text: "移"
                        font.family: Tokens.jp
                        font.pixelSize: 18
                        font.bold: true
                        color: KappaTheme.sun
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
                            text: root.isPt ? "SOLTAR AQUI_" : "DROP HERE_"
                            font.family: Tokens.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 2.2
                            color: KappaTheme.sun
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isPt ? "Copiar ou mover?" : "Copy or move?"
                        font.family: Tokens.display
                        font.pixelSize: 20
                        color: KappaTheme.ink
                    }
                }

                Text { textFormat: Text.PlainText; text: "esc"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim; Layout.alignment: Qt.AlignTop }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.paths.length === 1
                    ? (root.isPt ? "“" + root.firstName + "” vai para a pasta “" + root.destName + "”." : "“" + root.firstName + "” goes to the folder “" + root.destName + "”.")
                    : (root.isPt ? root.paths.length + " itens vão para a pasta “" + root.destName + "”." : root.paths.length + " items go to the folder “" + root.destName + "”.")
                font.family: Tokens.ui
                font.pixelSize: 13
                color: KappaTheme.inkDim
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.destDir
                elide: Text.ElideMiddle
                font.family: Tokens.mono
                font.pixelSize: 11
                color: KappaTheme.inkFaint
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: KappaTheme.line }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { textFormat: Text.PlainText; text: "C  M"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
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
                    implicitWidth: copyLabel.implicitWidth + 36
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: copyArea.containsMouse ? KappaTheme.tint10 : "transparent"
                    border.width: 1
                    border.color: KappaTheme.lineStrong
                    Text {
                        id: copyLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.isPt ? "Copiar" : "Copy"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        font.bold: true
                        color: KappaTheme.ink
                    }
                    MouseArea {
                        id: copyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chosen("copy")
                    }
                }

                Rectangle {
                    implicitWidth: moveLabel.implicitWidth + 36
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: KappaTheme.sun
                    Text {
                        id: moveLabel
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.isPt ? "Mover" : "Move"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        font.bold: true
                        color: KappaTheme.inkOnBone
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chosen("move")
                    }
                }
            }
        }
    }
}
