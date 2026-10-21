import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    width: 268
    color: KappaTheme.paper

    property string currentPath: ""
    property var placesList: []
    property var devicesList: []
    property var pinnedList: []
    property bool canPin: false
    signal pinDropped()
    signal unpinRequested(string path)
    signal navigateRequested(string path)
    signal kdeDeviceClicked(var device)
    signal deviceMountRequested(var device)
    signal deviceEjectRequested(string blockOrPath)

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    PixelGlyphs { id: glyphs }

    // Só reage a arrasto que nasceu no Kappa (canPin); o que for solto vindo de fora é ignorado
    DropArea {
        id: pinDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: function(drag) { drag.accepted = root.canPin; }
        onDropped: function(drop) {
            if (root.canPin) { drop.accept(Qt.CopyAction); root.pinDropped(); }
            else drop.accepted = false;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 4

        // 1. Cabeçalho da Seção Lugares (Nó 121: 236x20)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            Text {
                textFormat: Text.PlainText
                text: "//"
                font.family: Tokens.mono
                font.pixelSize: 11
                color: KappaTheme.sun
            }

            Text {
                textFormat: Text.PlainText
                text: root.isPt ? "LUGARES_" : "PLACES_"
                font.family: Tokens.ui
                font.pixelSize: 11
                font.bold: true
                color: KappaTheme.inkDim
            }

            // Régua brutalista com Tick no final
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: KappaTheme.line

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 1
                    height: 5
                    color: KappaTheme.lineStrong
                }
            }
        }

        // 2. Lista de Lugares Padrão (Itens de 236x36)
        Repeater {
            model: root.placesList

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: root.effectiveRadius
                color: {
                    if (root.currentPath === modelData.path) {
                        return KappaTheme.tint10
                    }
                    return itemMouse.containsMouse ? KappaTheme.tint5 : "transparent"
                }

                // Borda vertical vermillion de seleção ativa
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: KappaTheme.sun
                    visible: root.currentPath === modelData.path
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            switch(modelData.icon_name) {
                                case "home": return "󰋜"
                                case "doc": return "󰈙"
                                case "down": return "󰉍"
                                case "img": return "󰋩"
                                case "music": return "󰎆"
                                case "video": return "󰕧"
                                default: return "󰉋"
                            }
                        }
                        font.family: Tokens.mono
                        font.pixelSize: 14
                        color: root.currentPath === modelData.path ? KappaTheme.sun : KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: modelData.label
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: root.currentPath === modelData.path ? KappaTheme.ink : KappaTheme.inkDim
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.navigateRequested(modelData.path);
                        if (typeof app !== "undefined" && app) app.forceActiveFocus();
                    }
                }
            }
        }

        // 2b. Atalhos fixados pelo usuário (kanji aleatório no lugar do ícone)
        Repeater {
            model: root.pinnedList

            delegate: Rectangle {
                id: pinItem
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: root.effectiveRadius
                color: root.currentPath === modelData.path ? KappaTheme.tint10 : (pinMouse.containsMouse ? KappaTheme.tint5 : "transparent")

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: KappaTheme.sun
                    visible: root.currentPath === modelData.path
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Text {
                        textFormat: Text.PlainText
                        Layout.preferredWidth: 16
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.kanji
                        font.family: Tokens.jp
                        font.pixelSize: 13
                        color: root.currentPath === modelData.path ? KappaTheme.sun : KappaTheme.inkDim
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: modelData.label
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: root.currentPath === modelData.path ? KappaTheme.ink : KappaTheme.inkDim
                        elide: Text.ElideRight
                    }
                    Text {
                        textFormat: Text.PlainText
                        visible: pinMouse.containsMouse || unpinMouse.containsMouse
                        text: "✕"
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        color: unpinMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkFaint
                        MouseArea {
                            id: unpinMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.unpinRequested(modelData.path)
                        }
                    }
                }

                MouseArea {
                    id: pinMouse
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.navigateRequested(modelData.path);
                        if (typeof app !== "undefined" && app) app.forceActiveFocus();
                    }
                }
            }
        }

        // 3. Espaçador fixo de 16px entre seções (Nó 36: 10x16)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
        }

        // 4. Cabeçalho da Seção Dispositivos (Nó 126: 236x20)
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 8

            Text {
                textFormat: Text.PlainText
                text: "//"
                font.family: Tokens.mono
                font.pixelSize: 11
                color: KappaTheme.sun
            }

            Text {
                textFormat: Text.PlainText
                text: root.isPt ? "DISPOSITIVOS_" : "DEVICES_"
                font.family: Tokens.ui
                font.pixelSize: 11
                font.bold: true
                color: KappaTheme.inkDim
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: KappaTheme.line

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: 1
                    height: 5
                    color: KappaTheme.lineStrong
                }
            }
        }

        // 5. Lista de Dispositivos (Sistema, Dados, Removíveis e KDE Connect)
        Repeater {
            model: root.devicesList

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: root.effectiveRadius
                color: {
                    if (root.currentPath === modelData.path) {
                        return KappaTheme.tint10
                    }
                    return devMouse.containsMouse ? KappaTheme.tint5 : "transparent"
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: KappaTheme.sun
                    visible: root.currentPath === modelData.path
                }

                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof app !== "undefined" && app) app.forceActiveFocus();
                        if (modelData.is_network) {
                            root.kdeDeviceClicked(modelData)
                        } else if (modelData.device_block && !modelData.is_mounted) {
                            root.deviceMountRequested(modelData)
                        } else {
                            root.navigateRequested(modelData.path)
                        }
                    }
                    onDoubleClicked: {
                        if (modelData.is_network && modelData.path) {
                            root.navigateRequested(modelData.path)
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    // Ícone correspondente (Nó 2466 para USB, Nó 2470 para celular)
                    Text {
                        textFormat: Text.PlainText
                        text: {
                            if (modelData.is_network || modelData.icon_name === "phone") {
                                return "󰄡"
                            }
                            if (modelData.is_removable || modelData.icon_name === "usb") {
                                return "󱊞"
                            }
                            return "󰋊"
                        }
                        font.family: Tokens.mono
                        font.pixelSize: 14
                        color: root.currentPath === modelData.path ? KappaTheme.sun : KappaTheme.inkDim
                    }

                    // Nome e Detalhe de armazenamento (ex: "Kingston · 64 GB", "POCO X7 Pro")
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: {
                            if (modelData.is_network) {
                                return modelData.label
                            }
                            if (modelData.detail) {
                                return modelData.label + " · " + modelData.detail
                            }
                            return modelData.label
                        }
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: root.currentPath === modelData.path ? KappaTheme.ink : KappaTheme.inkDim
                        elide: Text.ElideRight
                    }

                    // Botão Ejetar para pendrives USB removíveis (Nó 2468: 10x9)
                    Rectangle {
                        implicitWidth: 20
                        implicitHeight: 20
                        radius: root.effectiveRadius
                        color: ejectMouse.containsMouse ? KappaTheme.tint10 : "transparent"
                        visible: modelData.is_removable
                        z: 10

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "⏏"
                            font.family: Tokens.mono
                            font.pixelSize: 12
                            color: ejectMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkFaint
                        }

                        MouseArea {
                            id: ejectMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.deviceEjectRequested(modelData.device_block || modelData.path);
                            }
                        }
                    }

                    // Placa retangular KDE para dispositivos conectados (Nó 153 / 2472: 35x16)
                    Rectangle {
                        implicitWidth: 35
                        implicitHeight: 16
                        radius: root.effectiveRadius
                        color: "transparent"
                        border.width: 1
                        border.color: KappaTheme.lineStrong
                        visible: modelData.is_network

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "KDE"
                            font.family: Tokens.mono
                            font.pixelSize: 9
                            font.bold: true
                            color: KappaTheme.sun
                        }
                    }
                }
            }
        }

        // 6. Espaçador flexível inferior (Nó 131)
        Item {
            Layout.fillHeight: true
        }

        // 7. Marginalia oficial do design: PixelWave + 00 // KAPPA + ////// (Nó 132: 236x20)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                spacing: 8

                PixelGlyphs.PixelWave {
                    glyphColor: KappaTheme.sun
                }

                Rectangle {
                    implicitWidth: marginaliaText.implicitWidth + 10
                    implicitHeight: 18
                    radius: root.effectiveRadius
                    color: "transparent"
                    border.width: 1
                    border.color: KappaTheme.line

                    Text {
                        textFormat: Text.PlainText
                        id: marginaliaText
                        anchors.centerIn: parent
                        text: "00 // KAPPA"
                        font.family: Tokens.mono
                        font.pixelSize: 9
                        color: KappaTheme.inkFaint
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    text: "//////"
                    font.family: Tokens.mono
                    font.pixelSize: 10
                    color: KappaTheme.inkFaint
                }
            }
        }
    }

    // Linha divisória vertical
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: KappaTheme.line
    }
}
