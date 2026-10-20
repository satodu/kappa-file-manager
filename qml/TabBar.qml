import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    implicitHeight: 38
    color: KappaTheme.paper

    property var tabs: []
    property int activeIndex: 0
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    signal tabSelected(int index, string path)
    signal tabClosed(int index)
    signal newTabRequested()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        // Repeater de Abas
        Repeater {
            model: root.tabs

            delegate: Rectangle {
                required property var modelData
                required property int index

                implicitWidth: Math.min(200, Math.max(120, tabText.implicitWidth + 56))
                Layout.fillHeight: true
                radius: root.effectiveRadius
                color: root.activeIndex === index ? KappaTheme.paperLift : (tabMouse.containsMouse ? KappaTheme.tint5 : "transparent")
                border.width: 1
                border.color: root.activeIndex === index ? KappaTheme.lineStrong : KappaTheme.lineSoft

                // Linha superior vermillion ativa
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 2
                    color: KappaTheme.sun
                    visible: root.activeIndex === index
                }

                // Área de clique da aba (fica atrás do botão fechar)
                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        if (typeof app !== "undefined" && app) app.forceActiveFocus();
                        if (mouse.button === Qt.MiddleButton && root.tabs.length > 1) {
                            root.tabClosed(index);
                        } else {
                            root.tabSelected(index, modelData.path);
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        textFormat: Text.PlainText
                        text: "󰉋"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.activeIndex === index ? KappaTheme.sun : KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        id: tabText
                        Layout.fillWidth: true
                        text: modelData.title || "Pasta"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        font.bold: root.activeIndex === index
                        color: root.activeIndex === index ? KappaTheme.ink : KappaTheme.inkDim
                        elide: Text.ElideRight
                    }

                    // Botão Fechar Aba (✕) com prioridade z: 5
                    Rectangle {
                        z: 5
                        implicitWidth: 20
                        implicitHeight: 20
                        radius: root.effectiveRadius
                        color: closeMouse.containsMouse ? KappaTheme.tint16 : "transparent"
                        visible: root.tabs.length > 1

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: Tokens.mono
                            font.pixelSize: 10
                            color: closeMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkFaint
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                mouse.accepted = true;
                                root.tabClosed(index);
                            }
                        }
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Easing.OutExpo }
                }
            }
        }

        // Botão Nova Aba (+)
        Rectangle {
            implicitWidth: 28
            implicitHeight: 28
            radius: root.effectiveRadius
            color: newTabMouse.containsMouse ? KappaTheme.tint10 : "transparent"
            border.width: 1
            border.color: KappaTheme.lineSoft

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "+"
                font.family: Tokens.mono
                font.pixelSize: 14
                color: newTabMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkDim
            }

            MouseArea {
                id: newTabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.newTabRequested()
            }

            Behavior on color {
                ColorAnimation { duration: 120; easing.type: Easing.OutExpo }
            }
        }

        Item { Layout.fillWidth: true }

        // Contador de abas (ex: "2 abas")
        Text {
            textFormat: Text.PlainText
            text: root.tabs.length + " abas"
            font.family: Tokens.mono
            font.pixelSize: 11
            color: KappaTheme.inkFaint
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: KappaTheme.line
    }
}
