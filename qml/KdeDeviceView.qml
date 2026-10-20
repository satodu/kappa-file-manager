import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    property var device: null
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    signal actionRequested(string action, string devId)
    signal folderOpened(string folderPath)

    // Decorações de Fundo: Cruzes Técnicas (+) do Figcraft
    TechCrosses {
        id: bgCrosses
    }

    // Marca d'água monumental do Frame 425 (Nó 495: kanji 繋 no canto inferior direito)
    Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: -29
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -120
        text: "繋"
        font.family: Tokens.jp
        font.pixelSize: 440
        font.bold: true
        color: KappaTheme.ink
        opacity: 0.05
        z: 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 20

        // Cabeçalho do Dispositivo (Nó 690: 1107x84)
        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            // Placa do Ícone de Celular (Nó 691: 72x72)
            Rectangle {
                implicitWidth: 72
                implicitHeight: 72
                radius: root.effectiveRadius
                color: KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.lineStrong

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰄡"
                    font.family: Tokens.mono
                    font.pixelSize: 34
                    color: KappaTheme.sun
                }
            }

            // Título e Detalhes de Emparelhamento (Nó 694)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    textFormat: Text.PlainText
                    text: root.device ? root.device.label : "POCO X7 Pro"
                    font.family: Tokens.display
                    font.pixelSize: 26
                    font.bold: true
                    color: KappaTheme.ink
                }

                Text {
                    textFormat: Text.PlainText
                    text: root.isPt ? "KDE Connect · dispositivo pareado" : "KDE Connect · paired device"
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.inkDim
                }
            }

            // Badge Estado: Conectado (Nó 697: 106x28)
            Rectangle {
                implicitWidth: statusRow.implicitWidth + 16
                implicitHeight: 28
                radius: root.effectiveRadius
                color: Qt.rgba(16/255, 185/255, 129/255, 0.1)
                border.width: 1
                border.color: "#10b981"

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: "#10b981"
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "Conectado" : "Connected"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: "#10b981"
                    }
                }
            }
        }

        // Seção ESTADO (Nó 700: 1107x20)
        RowLayout {
            Layout.fillWidth: true
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
                text: root.isPt ? "ESTADO_" : "STATUS_"
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

        // Células de Status (Nó 705: Bateria, Rede, Armazenamento)
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // Célula Bateria (Nó 706)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 104
                radius: root.effectiveRadius
                color: KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.line

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "BATERIA" : "BATTERY"
                        font.family: Tokens.mono
                        font.pixelSize: 10
                        color: KappaTheme.inkFaint
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "85 %"
                        font.family: Tokens.display
                        font.pixelSize: 24
                        font.bold: true
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "Descarregando · ~8 h restantes" : "Discharging · ~8 h remaining"
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        color: KappaTheme.inkDim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: root.effectiveRadius
                        color: KappaTheme.tint10

                        Rectangle {
                            width: parent.width * 0.85
                            height: parent.height
                            radius: root.effectiveRadius
                            color: KappaTheme.sun
                        }
                    }
                }
            }

            // Célula Rede (Nó 712)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 104
                radius: root.effectiveRadius
                color: KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.line

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "REDE" : "NETWORK"
                        font.family: Tokens.mono
                        font.pixelSize: 10
                        color: KappaTheme.inkFaint
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "Wi-Fi"
                        font.family: Tokens.display
                        font.pixelSize: 24
                        font.bold: true
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "192.168.0.12 · 5 GHz"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkDim
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Célula Armazenamento (Nó 716)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 104
                radius: root.effectiveRadius
                color: KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.line

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "ARMAZENAMENTO" : "STORAGE"
                        font.family: Tokens.mono
                        font.pixelSize: 10
                        color: KappaTheme.inkFaint
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "128 / 512 GB"
                        font.family: Tokens.display
                        font.pixelSize: 24
                        font.bold: true
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: root.isPt ? "384 GB livres" : "384 GB free"
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        color: KappaTheme.inkDim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: root.effectiveRadius
                        color: KappaTheme.tint10

                        Rectangle {
                            width: parent.width * 0.25
                            height: parent.height
                            radius: root.effectiveRadius
                            color: KappaTheme.ink
                        }
                    }
                }
            }
        }

        // Seção ACESSO RÁPIDO (Nó 722: 1107x20)
        RowLayout {
            Layout.fillWidth: true
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
                text: root.isPt ? "ACESSO RÁPIDO_" : "QUICK ACCESS_"
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

        // Pastas do Dispositivo (Nó 727: DCIM, Download, Documents, Pictures)
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Repeater {
                model: [
                    { name: "DCIM", icon: "󰄄" },
                    { name: "Download", icon: "󰉍" },
                    { name: "Documents", icon: "󰈙" },
                    { name: "Pictures", icon: "󰋩" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 70
                    radius: root.effectiveRadius
                    color: folderMouse.containsMouse ? KappaTheme.tint10 : KappaTheme.paperLift
                    border.width: 1
                    border.color: folderMouse.containsMouse ? KappaTheme.sun : KappaTheme.line

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.icon
                            font.family: Tokens.mono
                            font.pixelSize: 22
                            color: KappaTheme.sun
                        }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                textFormat: Text.PlainText
                                text: modelData.name
                                font.family: Tokens.ui
                                font.pixelSize: 14
                                font.bold: true
                                color: KappaTheme.ink
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.isPt ? "Abrir pasta" : "Browse folder"
                                font.family: Tokens.mono
                                font.pixelSize: 10
                                color: KappaTheme.inkFaint
                            }
                        }
                    }

                    MouseArea {
                        id: folderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.device && root.device.path) {
                                var base = root.device.path.toString();
                                if (!base.endsWith("/")) base += "/";
                                root.folderOpened(base + modelData.name);
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Barra de Ações do Dispositivo (Nó 749: 1107x32)
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Botão Explorar Arquivos (Acesso via KIO-Fuse do Dolphin)
            Rectangle {
                implicitWidth: browseText.implicitWidth + 24
                implicitHeight: 34
                radius: root.effectiveRadius
                color: browseMouse.containsMouse ? KappaTheme.sun : KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.sun

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        textFormat: Text.PlainText
                        text: "󰉋"
                        font.family: Tokens.mono
                        font.pixelSize: 12
                        color: browseMouse.containsMouse ? KappaTheme.paper : KappaTheme.sun
                    }
                    Text {
                        textFormat: Text.PlainText
                        id: browseText
                        text: root.isPt ? "Explorar Arquivos" : "Browse Files"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: browseMouse.containsMouse ? KappaTheme.paper : KappaTheme.ink
                    }
                }

                MouseArea {
                    id: browseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.device && root.device.path) {
                            root.folderOpened(root.device.path);
                        }
                    }
                }
            }

            // Botão Ping
            Rectangle {
                implicitWidth: pingText.implicitWidth + 24
                implicitHeight: 34
                radius: root.effectiveRadius
                color: pingMouse.containsMouse ? KappaTheme.tint16 : KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.lineStrong

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { textFormat: Text.PlainText; text: "󰄡"; font.family: Tokens.mono; font.pixelSize: 12; color: KappaTheme.sun }
                    Text {
                        textFormat: Text.PlainText
                        id: pingText
                        text: "Ping"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.ink
                    }
                }

                MouseArea {
                    id: pingMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.device) root.actionRequested("ping", root.device.id);
                    }
                }
            }

            // Botão Tocar Telefone (Ring)
            Rectangle {
                implicitWidth: ringText.implicitWidth + 24
                implicitHeight: 34
                radius: root.effectiveRadius
                color: ringMouse.containsMouse ? KappaTheme.tint16 : KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.lineStrong

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { textFormat: Text.PlainText; text: "󰂚"; font.family: Tokens.mono; font.pixelSize: 12; color: KappaTheme.sun }
                    Text {
                        textFormat: Text.PlainText
                        id: ringText
                        text: root.isPt ? "Fazer Tocar" : "Ring Device"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.ink
                    }
                }

                MouseArea {
                    id: ringMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.device) root.actionRequested("ring", root.device.id);
                    }
                }
            }

            // Botão Enviar Área de Transferência
            Rectangle {
                implicitWidth: clipText.implicitWidth + 24
                implicitHeight: 34
                radius: root.effectiveRadius
                color: clipMouse.containsMouse ? KappaTheme.tint16 : KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.lineStrong

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { textFormat: Text.PlainText; text: "󰅌"; font.family: Tokens.mono; font.pixelSize: 12; color: KappaTheme.sun }
                    Text {
                        textFormat: Text.PlainText
                        id: clipText
                        text: root.isPt ? "Enviar Clipboard" : "Send Clipboard"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.ink
                    }
                }

                MouseArea {
                    id: clipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.device) root.actionRequested("clipboard", root.device.id);
                    }
                }
            }

            // Botão Montar Dispositivo
            Rectangle {
                implicitWidth: mountText.implicitWidth + 24
                implicitHeight: 34
                radius: root.effectiveRadius
                color: mountMouse.containsMouse ? KappaTheme.tint16 : KappaTheme.paperLift
                border.width: 1
                border.color: KappaTheme.lineStrong

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { textFormat: Text.PlainText; text: "󰋊"; font.family: Tokens.mono; font.pixelSize: 12; color: KappaTheme.sun }
                    Text {
                        textFormat: Text.PlainText
                        id: mountText
                        text: root.isPt ? "Montar / Atualizar" : "Mount / Refresh"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.ink
                    }
                }

                MouseArea {
                    id: mountMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.device) root.actionRequested("mount", root.device.id);
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
