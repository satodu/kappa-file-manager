import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

Item {
    id: root
    visible: false

    property var targetItem: null
    property var devicesList: []
    property real menuX: 0
    property real menuY: 0
    property bool showSendSubmenu: false

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property bool isAudio: root.targetItem && root.targetItem.kind === "audio"
    readonly property bool isArchive: {
        if (!targetItem || targetItem.is_dir || !targetItem.name) return false;
        var n = targetItem.name.toLowerCase();
        return n.endsWith(".zip") || n.endsWith(".tar") || n.endsWith(".tar.gz") || n.endsWith(".tgz");
    }
    readonly property bool isFolderContext: root.targetItem === null
    readonly property real menuWidth: root.isAudio ? 268 : 252
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    signal openTriggered(var item)
    signal openNewTabTriggered(var item)
    signal openTerminalTriggered(var item)
    signal playRyotunesTriggered(var item)
    signal copyPathTriggered(var item)
    signal copyTriggered(var item)
    signal cutTriggered(var item)
    signal pasteTriggered()
    signal newFolderTriggered()
    signal reloadTriggered()
    signal selectAllTriggered()
    signal renameTriggered(var item)
    signal compressTriggered(var item, string format)
    signal extractTriggered(var item)
    signal trashTriggered(var item)
    signal sendKdeTriggered(var item, string devId)
    signal propertiesTriggered(var item)

    function show(item, posX, posY, devices) {
        root.targetItem = item;
        root.devicesList = devices || [];
        root.showSendSubmenu = false;
        var estHeight = root.isAudio ? 500 : (root.isFolderContext ? 305 : 520);
        var clampX = Math.min(posX, root.width - root.menuWidth - 16);
        var clampY = Math.min(posY, root.height - estHeight - 16);
        root.menuX = Math.max(16, clampX);
        root.menuY = Math.max(16, clampY);
        root.visible = true;
    }

    function hide() {
        root.visible = false;
        root.showSendSubmenu = false;
        root.targetItem = null;
    }

    // Camada invisível para fechar ao clicar fora
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.hide()
        onWheel: root.hide()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SOMBRA SUAVE REAL (Nó 616 / 1380 do Figcraft: dropShadow y:14 blur:30 a:0.65)
    // ═══════════════════════════════════════════════════════════════════════
    MultiEffect {
        source: menuBox
        anchors.fill: menuBox
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.65)
        shadowVerticalOffset: 14
        shadowHorizontalOffset: 0
        shadowBlur: 0.8
        visible: root.visible
        z: 1
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MENU PRINCIPAL (Nó 616 / Nó 1380 do Figcraft)
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: menuBox
        x: root.menuX
        y: root.menuY
        width: root.menuWidth
        implicitHeight: menuLayout.implicitHeight + 12
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: KappaTheme.lineStrong
        z: 2

        ColumnLayout {
            id: menuLayout
            anchors.fill: parent
            anchors.margins: 6
            spacing: 0

            // ─────────────────────────────────────────────────────────────
            // MODO ÁUDIO (Nó 1380: Kappa / Menu de contexto (áudio) - 268x349)
            // ─────────────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.isAudio

                // 1. Cabeçalho RYOTUNES_ (Nó 1381: 254x20)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
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
                        text: "RYOTUNES_"
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.sun
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

                // 2. Tocar no Ryotunes (Nó 1386: destaque em ciano #80d4d9)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    color: ryoMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰎆"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.sun
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Tocar no Ryotunes" : "Play in Ryotunes"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            font.bold: true
                            color: KappaTheme.sun
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Enter"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: ryoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.playRyotunesTriggered(root.targetItem); root.hide(); }
                    }
                }

                // 3. Adicionar à fila (Nó 1390: Ctrl+Q)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    color: queueMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰐎"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Adicionar à fila" : "Add to queue"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+Q"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: queueMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.playRyotunesTriggered(root.targetItem); root.hide(); }
                    }
                }

                // 4. Tocar a seguir (Nó 1394)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    color: nextMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰒭"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Tocar a seguir" : "Play next"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.playRyotunesTriggered(root.targetItem); root.hide(); }
                    }
                }

                // Separador (Nó 1397)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 9
                    Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
                }

                // 5. Abrir com (Nó 1399)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    color: openWithMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰈔"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Abrir com" : "Open with"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "›"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }
                    }

                    MouseArea {
                        id: openWithMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.openTriggered(root.targetItem); root.hide(); }
                    }
                }
            }

            // ─────────────────────────────────────────────────────────────
            // MODO NORMAL & MODO PASTA (Nó 616: Kappa / Menu de contexto - 252x370)
            // ─────────────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: !root.isAudio

                // 0. Cabeçalho de Contexto de Pasta (quando clicado no fundo da pasta)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    spacing: 8
                    visible: root.isFolderContext

                    Text {
                        textFormat: Text.PlainText
                        text: "//"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.sun
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: (typeof app !== "undefined" && app && app.currentFolderName) ? (app.currentFolderName.toUpperCase() + "_") : "PASTA_"
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.sun
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: KappaTheme.line
                    }
                }

                // 1. Abrir (Nó 617: 238x32 - Enter)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: !root.isFolderContext
                    color: openMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰈔"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Abrir" : "Open"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Enter"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.openTriggered(root.targetItem); root.hide(); }
                    }
                }

                // 2. Abrir em nova aba (Nó 621: 238x32 - Ctrl+T)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: !root.isFolderContext
                    color: tabMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰉋"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Abrir em nova aba" : "Open in new tab"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+T"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.openNewTabTriggered(root.targetItem); root.hide(); }
                    }
                }

                // 3. Colar (Nó 639: 238x32 - Ctrl+V) - Destaque no topo em contexto de pasta
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: root.isFolderContext
                    color: pasteFolderMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰅌"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.sun
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Colar" : "Paste"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            font.bold: true
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+V"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: pasteFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.pasteTriggered(); root.hide(); }
                    }
                }

                // Nova Pasta (Contexto de Pasta)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: root.isFolderContext
                    color: newFolderMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰉋"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Nova pasta" : "New folder"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "F7"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: newFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.newFolderTriggered(); root.hide(); }
                    }
                }

                // 4. Abrir terminal aqui (Nó 625: 238x32 - Ctrl+Alt+T)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    color: termMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰞷"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Abrir terminal aqui" : "Open terminal here"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+Alt+T"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: termMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.openTerminalTriggered(root.targetItem); root.hide(); }
                    }
                }

                // Separador (Nó 629: 9px)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 9
                    visible: !root.isFolderContext
                    Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
                }

                // 5. Recortar (Nó 631: 238x32 - Ctrl+X)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: !root.isFolderContext
                    color: cutMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰆐"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Recortar" : "Cut"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+X"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: cutMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.cutTriggered(root.targetItem); root.hide(); }
                    }
                }

                // 6. Copiar (Nó 635: 238x32 - Ctrl+C)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: !root.isFolderContext
                    color: copyMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰆏"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Copiar" : "Copy"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+C"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.copyTriggered(root.targetItem); root.hide(); }
                    }
                }

                // 7. Colar em item (Nó 639: 238x32 - Ctrl+V)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: !root.isFolderContext
                    color: pasteMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰅌"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Colar" : "Paste"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+V"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: pasteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.pasteTriggered(); root.hide(); }
                    }
                }

                // Separador em contexto de pasta
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 9
                    visible: root.isFolderContext
                    Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
                }

                // Selecionar tudo (Ctrl+A)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: root.isFolderContext
                    color: selectAllMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰒅"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Selecionar tudo" : "Select all"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "Ctrl+A"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: selectAllMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.selectAllTriggered(); root.hide(); }
                    }
                }

                // Recarregar (F5)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    visible: root.isFolderContext
                    color: reloadMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "󰑐"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: root.isPt ? "Recarregar" : "Refresh"
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "F5"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkFaint
                        }
                    }

                    MouseArea {
                        id: reloadMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.reloadTriggered(); root.hide(); }
                    }
                }

                // Separador (Nó 643: 9px)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 9
                    visible: !root.isFolderContext
                    Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
                }
            }

            // ─────────────────────────────────────────────────────────────
            // SEÇÃO COMUM (Enviar para, Renomear, Lixeira, Propriedades)
            // ─────────────────────────────────────────────────────────────

            // 7. Enviar para > (Nó 645 / Nó 1403)
            Rectangle {
                id: sendToItem
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                visible: !root.isFolderContext
                color: (sendMouse.containsMouse || root.showSendSubmenu) ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        text: "󰅂"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isPt ? "Enviar para" : "Send to"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "›"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: KappaTheme.inkDim
                    }
                }

                MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.showSendSubmenu = true
                    onClicked: root.showSendSubmenu = !root.showSendSubmenu
                }
            }

            // Separador após Enviar para (Nó 649 / Nó 1407)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                visible: !root.isFolderContext
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
            }

            // Copiar exclusivo para modo áudio se aplicável (Nó 1409)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                visible: root.isAudio && !root.isFolderContext
                color: copyAudioMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        text: "󰆏"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isPt ? "Copiar" : "Copy"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "Ctrl+C"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    id: copyAudioMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.copyTriggered(root.targetItem); root.hide(); }
                }
            }

            // Compactar / Extrair (zip e tar.gz)
            component ArchiveRow: Rectangle {
                id: arow
                property string label: ""
                property string glyph: "󰗄"
                property string hint: ""
                signal activated()
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: amouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10
                    Text { textFormat: Text.PlainText; text: arow.glyph; font.family: Tokens.mono; font.pixelSize: 13; color: KappaTheme.inkDim }
                    Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: arow.label; font.family: Tokens.ui; font.pixelSize: 13; color: KappaTheme.ink }
                    Text { textFormat: Text.PlainText; visible: arow.hint !== ""; text: arow.hint; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkFaint }
                }
                MouseArea {
                    id: amouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { arow.activated(); root.hide(); }
                }
            }

            ArchiveRow {
                glyph: "󰆏"
                label: root.isPt ? "Copiar localização" : "Copy location"
                hint: "Ctrl+Shift+C"
                onActivated: root.copyPathTriggered(root.targetItem)
            }
            ArchiveRow {
                visible: !root.isFolderContext && root.isArchive
                glyph: "󰛫"
                label: root.isPt ? "Extrair aqui" : "Extract here"
                onActivated: root.extractTriggered(root.targetItem)
            }
            ArchiveRow {
                visible: !root.isFolderContext
                label: root.isPt ? "Comprimir em .zip" : "Compress to .zip"
                onActivated: root.compressTriggered(root.targetItem, "zip")
            }
            ArchiveRow {
                visible: !root.isFolderContext
                label: root.isPt ? "Comprimir em .tar.gz" : "Compress to .tar.gz"
                onActivated: root.compressTriggered(root.targetItem, "tar.gz")
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                visible: !root.isFolderContext
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
            }

            // 8. Renomear (Nó 651 / Nó 1413 - F2)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                visible: !root.isFolderContext
                color: renameMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        text: "󰑕"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isPt ? "Renomear" : "Rename"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "F2"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    id: renameMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.renameTriggered(root.targetItem); root.hide(); }
                }
            }

            // 9. Mover para a Lixeira (Nó 655 / Nó 1417 - Del)
            // No Figcraft: Texto e Ícone são SEMPRE em vermillion (#ffb4ab / KappaTheme.sun)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                visible: !root.isFolderContext
                color: trashMouse.containsMouse ? Qt.rgba(226/255, 52/255, 42/255, 0.15) : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        text: "󰩹"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: KappaTheme.sun
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isPt ? "Mover para a lixeira" : "Move to trash"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: KappaTheme.sun
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "Del"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    id: trashMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.trashTriggered(root.targetItem); root.hide(); }
                }
            }

            // Separador (Nó 659 / Nó 1421: 9px)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                visible: !root.isFolderContext
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
            }

            // 10. Propriedades / Detalhes (Nó 661 / Nó 1423 - Alt+Enter)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: propMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        textFormat: Text.PlainText
                        text: "󰋽"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.isPt ? "Propriedades" : "Properties"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        color: KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "Alt+Enter"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    id: propMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.propertiesTriggered(root.targetItem); root.hide(); }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SUBMENU ENVIAR PARA (Nó 665 do Figcraft: 260x171px)
    // ═══════════════════════════════════════════════════════════════════════
    MultiEffect {
        source: submenuBox
        anchors.fill: submenuBox
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.65)
        shadowVerticalOffset: 14
        shadowHorizontalOffset: 0
        shadowBlur: 0.8
        visible: root.showSendSubmenu
        z: 3
    }

    Rectangle {
        id: submenuBox
        x: {
            var preferredX = menuBox.x + menuBox.width + 4;
            if (preferredX + 260 > root.width - 16) {
                return menuBox.x - 264;
            }
            return preferredX;
        }
        y: Math.min(menuBox.y + 120, root.height - submenuLayout.implicitHeight - 24)
        width: 260
        implicitHeight: submenuLayout.implicitHeight + 12
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: KappaTheme.lineStrong
        visible: root.showSendSubmenu
        z: 4

        ColumnLayout {
            id: submenuLayout
            anchors.fill: parent
            anchors.margins: 6
            spacing: 0

            // Cabeçalho ENVIAR PARA_ (Nó 666: 246x20)
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 8

                Text { textFormat: Text.PlainText; text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.sun }
                Text { textFormat: Text.PlainText; text: root.isPt ? "ENVIAR PARA_" : "SEND TO_"; font.family: Tokens.ui; font.pixelSize: 11; font.bold: true; color: KappaTheme.inkDim }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: KappaTheme.line
                    Rectangle { anchors.right: parent.right; anchors.top: parent.top; width: 1; height: 5; color: KappaTheme.lineStrong }
                }
            }

            // Dispositivos KDE Connect e USBs conectados (Nós 671 e 676)
            Repeater {
                model: {
                    var out = [];
                    for (var i = 0; i < root.devicesList.length; i++) {
                        var d = root.devicesList[i];
                        if (d.is_network || d.is_removable) out.push(d);
                    }
                    return out;
                }

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: root.effectiveRadius
                    color: devSubMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.is_network ? "󰄡" : "󰋊"
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.sun
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: modelData.label
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            color: KappaTheme.ink
                            elide: Text.ElideRight
                        }

                        // Placa KDE ou USB (Nó 674 e 679: 35x16)
                        Rectangle {
                            implicitWidth: 35
                            implicitHeight: 16
                            radius: root.effectiveRadius
                            color: "transparent"
                            border.width: 1
                            border.color: KappaTheme.lineStrong

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: modelData.is_network ? "KDE" : "USB"
                                font.family: Tokens.mono
                                font.pixelSize: 9
                                font.bold: true
                                color: KappaTheme.sun
                            }
                        }
                    }

                    MouseArea {
                        id: devSubMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.is_network) {
                                root.sendKdeTriggered(root.targetItem, modelData.id);
                            }
                            root.hide();
                        }
                    }
                }
            }

            // Separador (Nó 681: 9px)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
            }

            // Pasta compactada .zip (Nó 683)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: zipMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10
                    Text { textFormat: Text.PlainText; text: "󰛫"; font.family: Tokens.mono; font.pixelSize: 13; color: KappaTheme.inkDim }
                    Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: root.isPt ? "Pasta compactada (.zip)" : "Compressed folder (.zip)"; font.family: Tokens.ui; font.pixelSize: 13; color: KappaTheme.ink }
                }

                MouseArea {
                    id: zipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.hide(); }
                }
            }

            // Área de transferência (Nó 686)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: clipSubMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10
                    Text { textFormat: Text.PlainText; text: "󰅌"; font.family: Tokens.mono; font.pixelSize: 13; color: KappaTheme.inkDim }
                    Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: root.isPt ? "Área de transferência" : "Clipboard"; font.family: Tokens.ui; font.pixelSize: 13; color: KappaTheme.ink }
                }

                MouseArea {
                    id: clipSubMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.copyPathTriggered(root.targetItem);
                        root.hide();
                    }
                }
            }
        }
    }
}
