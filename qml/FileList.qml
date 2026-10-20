import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Ryoku.Ui.Singletons

Item {
    id: root

    property var entries: []
    property string viewMode: "list"
    property var selectedItem: null
    property var selectedPaths: []
    readonly property var selectedSet: {
        var m = ({});
        for (var i = 0; i < selectedPaths.length; i++) m[selectedPaths[i]] = true;
        return m;
    }
    readonly property int selectedIndex: {
        if (!selectedItem || !entries || entries.length === 0) return -1;
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].path === selectedItem.path) return i;
        }
        return -1;
    }
    property string sortField: "name"
    property string sortDirection: "asc"
    property bool groupByType: false
    property bool showWatermark: true
    // Em painéis estreitos (split view) a coluna TIPO some para o nome não ser cortado
    readonly property bool showTypeColumn: root.width >= 760
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    function formatFileType(item) {
        if (!item) return "—";
        if (item.is_dir) return root.isPt ? "Pasta" : "Folder";
        var k = item.kind;
        var ext = "";
        if (item.name && item.name.lastIndexOf(".") !== -1) {
            ext = item.name.substring(item.name.lastIndexOf(".") + 1).toUpperCase();
        }
        if (k === "image") {
            return ext ? (ext + (root.isPt ? " (Imagem)" : " (Image)")) : (root.isPt ? "Imagem" : "Image");
        }
        if (k === "document") {
            if (ext === "PDF") return "PDF";
            if (ext === "MD") return "Markdown";
            if (ext === "TXT") return root.isPt ? "Texto" : "Text";
            return ext ? (ext + (root.isPt ? " (Doc)" : " (Doc)")) : (root.isPt ? "Documento" : "Document");
        }
        if (k === "code") {
            if (ext === "RS") return "Rust";
            if (ext === "QML") return "QML";
            if (ext === "JSON") return "JSON";
            if (ext === "TOML") return "TOML";
            if (ext === "TS" || ext === "JS") return ext;
            if (ext === "SH") return "Shell";
            return ext ? (ext + (root.isPt ? " (Código)" : " (Code)")) : (root.isPt ? "Código" : "Code");
        }
        if (k === "audio") {
            return ext ? (ext + (root.isPt ? " (Áudio)" : " (Audio)")) : (root.isPt ? "Áudio" : "Audio");
        }
        if (k === "video") {
            return ext ? (ext + (root.isPt ? " (Vídeo)" : " (Video)")) : (root.isPt ? "Vídeo" : "Video");
        }
        if (k === "archive") {
            return ext ? (ext + (root.isPt ? " (Arquivo)" : " (Archive)")) : (root.isPt ? "Compactado" : "Archive");
        }
        if (ext) return ext;
        return root.isPt ? "Arquivo" : "File";
    }
    // Arrastar para outra janela (terminal, chat, editor...): envia a localização dos itens.
    // O que sai é só o caminho dos itens que você arrastou; o Kappa NÃO aceita soltar nada aqui.
    function dragPaths(item) {
        if (selectedSet[item.path] !== true) return [item.path];
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            if (selectedSet[entries[i].path] === true) out.push(entries[i].path);
        }
        return out.length > 0 ? out : [item.path];
    }

    // Só `text/uri-list` (URIs file:// com cada trecho codificado): é o que gerenciadores de arquivos comuns enviam.
    // Terminais colam o caminho, chats e navegadores anexam o arquivo. Não se envia `text/plain` ao mesmo tempo:
    // alguns programas aceitam os dois e colariam o caminho duas vezes; além disso, um nome com quebra de linha
    // em texto puro viraria comando ao soltar num terminal, e a URI codificada não tem esse problema.
    function dragMime(item) {
        var uris = [];
        var paths = dragPaths(item);
        for (var i = 0; i < paths.length; i++) {
            var u = KappaSafe.fileUrl(paths[i]);
            if (u !== "") uris.push(u);
        }
        return ({ "text/uri-list": uris.join("\r\n") + "\r\n" });
    }

    signal itemActivated(var item)
    signal itemClicked(var item, int modifiers)
    signal backgroundClicked()
    signal contextMenuRequested(var item, real posX, real posY)
    signal sortHeaderClicked(string field)

    onSelectedIndexChanged: {
        if (selectedIndex < 0) return;
        if (viewMode === "list") listView.positionViewAtIndex(selectedIndex, ListView.Contain);
        else if (viewMode === "grid") gridView.positionViewAtIndex(selectedIndex, GridView.Contain);
    }

    // Foco e encaminhamento de teclas para App
    Keys.forwardTo: (typeof app !== "undefined" && app) ? [app] : []
    Keys.onPressed: function(event) {
        if (typeof app !== "undefined" && app && app.handleKeyPress) {
            app.handleKeyPress(event);
        }
    }

    // Clique no fundo limpa seleção e abre menu de contexto da pasta fora de qualquer item
    MouseArea {
        id: rootBgMouse
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (typeof app !== "undefined" && app) {
                app.forceActiveFocus();
            }
            if (mouse.button === Qt.RightButton) {
                var map = rootBgMouse.mapToItem(null, mouse.x, mouse.y);
                root.contextMenuRequested(null, map.x, map.y);
            } else {
                root.backgroundClicked();
            }
        }
    }

    // Decorações de Fundo: Cruzes Técnicas (+) do Figcraft (Reg marcas)
    TechCrosses {
        id: bgCrosses
    }

    // Linha técnica pontilhada na base
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.right: parent.right
        anchors.rightMargin: 20
        height: 1
        color: KappaTheme.lineSoft
    }

    // Marca d'água monumental do Figcraft (Nó 143: 440x637 no canto inferior direito)
    Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: -29
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -120
        text: "河"
        font.family: Tokens.jp
        font.pixelSize: 440
        font.bold: true
        color: KappaTheme.ink
        opacity: 0.05
        visible: root.showWatermark
        z: 0
    }

    // Cabeçalho de colunas (Apenas visível em modo lista)
    Rectangle {
        id: colHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.viewMode === "list" ? 32 : 0
        color: KappaTheme.paper
        visible: root.viewMode === "list"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 0

            // Coluna NOME (Nó 55)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            if (root.sortField === "name") {
                                return (root.isPt ? "NOME " : "NAME ") + (root.sortDirection === "asc" ? "↑" : "↓");
                            }
                            return root.isPt ? "NOME" : "NAME";
                        }
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: root.sortField === "name"
                        color: root.sortField === "name" ? KappaTheme.sun : KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortHeaderClicked("name")
                }
            }

            // Coluna TIPO (Nó 580 / Nó 3270)
            Item {
                visible: root.showTypeColumn
                Layout.preferredWidth: 150
                Layout.fillHeight: true

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            if (root.sortField === "type") {
                                return (root.isPt ? "TIPO " : "TYPE ") + (root.sortDirection === "asc" ? "↑" : "↓");
                            }
                            return root.isPt ? "TIPO" : "TYPE";
                        }
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: root.sortField === "type"
                        color: root.sortField === "type" ? KappaTheme.sun : KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortHeaderClicked("type")
                }
            }

            // Coluna MODIFICADO (Nó 56 / Nó 2989)
            Item {
                Layout.preferredWidth: 160
                Layout.fillHeight: true

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            if (root.sortField === "modified") {
                                return (root.isPt ? "MODIFICADO " : "MODIFIED ") + (root.sortDirection === "asc" ? "↑" : "↓");
                            }
                            return root.isPt ? "MODIFICADO" : "MODIFIED";
                        }
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: root.sortField === "modified"
                        color: root.sortField === "modified" ? KappaTheme.sun : KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortHeaderClicked("modified")
                }
            }

            // Coluna TAMANHO (Nó 57 / Nó 3131)
            Item {
                Layout.preferredWidth: 100
                Layout.fillHeight: true

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            if (root.sortField === "size") {
                                return (root.isPt ? "TAMANHO " : "SIZE ") + (root.sortDirection === "asc" ? "↑" : "↓");
                            }
                            return root.isPt ? "TAMANHO" : "SIZE";
                        }
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: root.sortField === "size"
                        color: root.sortField === "size" ? KappaTheme.sun : KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortHeaderClicked("size")
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: KappaTheme.line
        }

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutExpo }
        }
    }

    // Modo LISTA
    ListView {
        id: listView
        z: 1
        anchors.top: colHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.viewMode === "list"
        opacity: root.viewMode === "list" ? 1.0 : 0.0
        clip: true
        model: root.entries

        // Espaço vazio abaixo dos itens captura cliques para menu de contexto da pasta e foco
        footer: Item {
            id: listFooter
            width: listView.width
            height: Math.max(listView.height - (listView.count * 48), 100)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (typeof app !== "undefined" && app) {
                        app.forceActiveFocus();
                    }
                    if (mouse.button === Qt.RightButton) {
                        var map = mapToItem(null, mouse.x, mouse.y);
                        root.contextMenuRequested(null, map.x, map.y);
                    } else {
                        root.backgroundClicked();
                    }
                }
            }
        }

        // Agrupamento por Tipo (Frame 2710: Secao PASTAS, Secao IMAGENS, Secao DOCUMENTOS)
        section.property: root.groupByType ? "section_label" : ""
        section.criteria: ViewSection.FullString
        section.delegate: Rectangle {
            width: listView.width
            height: 32
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10

                Text {
                    textFormat: Text.PlainText
                    text: "//"
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.sun
                }

                Text {
                    textFormat: Text.PlainText
                    text: section
                    font.family: Tokens.ui
                    font.pixelSize: 11
                    font.bold: true
                    color: KappaTheme.ink
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
        }

        delegate: Rectangle {
            required property var modelData
            required property int index

            width: listView.width
            height: 48
            radius: Math.min(root.effectiveRadius, 4)
            readonly property bool isSelected: root.selectedSet[modelData.path] === true
            color: {
                if (isSelected) return KappaTheme.tint10;
                return rowMouse.containsMouse ? KappaTheme.tint5 : "transparent";
            }

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.proposedAction: Qt.CopyAction
            Drag.mimeData: root.dragMime(modelData)
            Drag.active: rowDrag.active
            DragHandler {
                id: rowDrag
                target: null
                acceptedButtons: Qt.LeftButton
                dragThreshold: 10
                onActiveChanged: if (active && root.selectedSet[modelData.path] !== true) root.itemClicked(modelData, 0)
            }

            // Marcador de seleção: barra de 2px na lateral (seleções contíguas se fundem)
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: parent.height - 16
                radius: 1
                color: KappaTheme.sun
                visible: isSelected
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 0

                // Coluna Nome + Ícone
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            if (modelData.is_dir) return "󰉋";
                            switch(modelData.icon_name) {
                                case "doc": return "󰈙";
                                case "img": return "󰋩";
                                case "music": return "󰎆";
                                case "video": return "󰕧";
                                case "code": return "󰅩";
                                case "archive": return "󰛫";
                                default: return "󰈔";
                            }
                        }
                        font.family: Tokens.mono
                        font.pixelSize: 16
                        color: modelData.is_dir ? KappaTheme.sun : KappaTheme.inkDim
                    }

                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: modelData.name
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: modelData.is_dir
                        color: isSelected ? KappaTheme.ink : (modelData.is_dir ? KappaTheme.ink : KappaTheme.inkDim)
                        elide: Text.ElideRight
                    }
                }

                // Coluna Tipo
                Text {
                    textFormat: Text.PlainText
                    visible: root.showTypeColumn
                    Layout.preferredWidth: 150
                    text: root.formatFileType(modelData)
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    color: isSelected ? KappaTheme.ink : KappaTheme.inkDim
                    elide: Text.ElideRight
                }

                // Coluna Modificado
                Text {
                    textFormat: Text.PlainText
                    Layout.preferredWidth: 160
                    text: modelData.modified_formatted
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    color: KappaTheme.inkFaint
                }

                // Coluna Tamanho
                Text {
                    textFormat: Text.PlainText
                    Layout.preferredWidth: 100
                    text: modelData.size_formatted
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.inkFaint
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton && root.selectedSet[modelData.path] === true) {
                        // botão direito sobre item já selecionado preserva a seleção múltipla
                    } else {
                        root.itemClicked(modelData, mouse.modifiers);
                    }
                    if (typeof app !== "undefined" && app) {
                        app.forceActiveFocus();
                    }
                    if (mouse.button === Qt.RightButton) {
                        var map = rowMouse.mapToItem(null, mouse.x, mouse.y);
                        root.contextMenuRequested(modelData, map.x, map.y);
                    }
                }
                onDoubleClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        root.itemActivated(modelData);
                    }
                }
            }

            Behavior on color {
                ColorAnimation { duration: 120; easing.type: Easing.OutExpo }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutExpo }
        }
    }

    // Modo GRADE (Grid oficial - Nós 908 a 966 do Figcraft)
    GridView {
        id: gridView
        z: 1
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        visible: root.viewMode === "grid"
        opacity: root.viewMode === "grid" ? 1.0 : 0.0
        clip: true
        cellWidth: 184
        cellHeight: 196
        model: root.entries

        // Espaço vazio abaixo dos cards captura cliques para menu de contexto da pasta e foco
        footer: Item {
            id: gridFooter
            width: gridView.width
            height: {
                var cols = Math.max(1, Math.floor(gridView.width / gridView.cellWidth));
                var rows = Math.ceil(gridView.count / cols);
                var totalGridHeight = rows * gridView.cellHeight;
                return Math.max(gridView.height - totalGridHeight, 100);
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (typeof app !== "undefined" && app) {
                        app.forceActiveFocus();
                    }
                    if (mouse.button === Qt.RightButton) {
                        var map = mapToItem(null, mouse.x, mouse.y);
                        root.contextMenuRequested(null, map.x, map.y);
                    } else {
                        root.backgroundClicked();
                    }
                }
            }
        }

        delegate: Rectangle {
            id: tileBox
            required property var modelData
            required property int index

            width: 168
            height: 176
            x: 8
            y: 8
            radius: root.effectiveRadius
            readonly property bool isSelected: root.selectedSet[modelData.path] === true
            color: {
                if (isSelected) return KappaTheme.tint10;
                return gridMouse.containsMouse ? KappaTheme.tint10 : KappaTheme.tint5;
            }

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.proposedAction: Qt.CopyAction
            Drag.mimeData: root.dragMime(modelData)
            Drag.active: gridDrag.active
            DragHandler {
                id: gridDrag
                target: null
                acceptedButtons: Qt.LeftButton
                dragThreshold: 10
                onActiveChanged: if (active && root.selectedSet[modelData.path] !== true) root.itemClicked(modelData, 0)
            }
            border.width: 1
            border.color: {
                if (isSelected) return KappaTheme.sun;
                return gridMouse.containsMouse ? KappaTheme.lineStrong : KappaTheme.line;
            }

            // Ticks técnicos de calibração nos 4 cantos quando selecionado (Nó 919 do Figcraft)
            Item {
                anchors.fill: parent
                visible: tileBox.isSelected

                // Canto Superior Esquerdo
                Rectangle { x: 0; y: 0; width: 7; height: 1; color: KappaTheme.sun }
                Rectangle { x: 0; y: 0; width: 1; height: 7; color: KappaTheme.sun }

                // Canto Superior Direito
                Rectangle { x: parent.width - 7; y: 0; width: 7; height: 1; color: KappaTheme.sun }
                Rectangle { x: parent.width - 1; y: 0; width: 1; height: 7; color: KappaTheme.sun }

                // Canto Inferior Esquerdo
                Rectangle { x: 0; y: parent.height - 1; width: 7; height: 1; color: KappaTheme.sun }
                Rectangle { x: 0; y: parent.height - 7; width: 1; height: 7; color: KappaTheme.sun }

                // Canto Inferior Direito
                Rectangle { x: parent.width - 7; y: parent.height - 1; width: 7; height: 1; color: KappaTheme.sun }
                Rectangle { x: parent.width - 1; y: parent.height - 7; width: 1; height: 7; color: KappaTheme.sun }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Miniatura do Arquivo / Pasta (Nó 910: 152x100)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    radius: root.effectiveRadius
                    color: KappaTheme.paperLift
                    border.width: 1
                    border.color: KappaTheme.lineSoft
                    clip: true

                    // Preview de Imagem real se for kind === "image" (exceto .svg que causa erro de decodificação)
                    Image {
                        anchors.fill: parent
                        source: KappaSafe.previewUrl(modelData)
                        sourceSize: Qt.size(304, 200)
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: modelData.kind === "image" && status === Image.Ready
                    }

                    // Se for Pasta (Nó 911: Pasta grande 44x44)
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: modelData.is_dir
                        text: "󰉋"
                        font.family: Tokens.mono
                        font.pixelSize: 44
                        color: KappaTheme.sun
                    }

                    // Se for Código ou Documento: Linhas de blueprint técnicas (Nó 927 do Figcraft)
                    Column {
                        anchors.centerIn: parent
                        spacing: 7
                        visible: !modelData.is_dir && (modelData.kind === "code" || modelData.kind === "document")

                        Rectangle { width: 60; height: 3; color: KappaTheme.lineStrong }
                        Rectangle { width: 100; height: 3; color: KappaTheme.line }
                        Rectangle { width: 84; height: 3; color: KappaTheme.line }
                        Rectangle { width: 40; height: 3; color: KappaTheme.line }
                        Rectangle { width: 92; height: 3; color: KappaTheme.lineSoft }
                    }

                    // Se for Áudio (Nó 967)
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !modelData.is_dir && modelData.kind === "audio"
                        text: "󰎆"
                        font.family: Tokens.mono
                        font.pixelSize: 38
                        color: KappaTheme.sun
                    }

                    // Se for Vídeo
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !modelData.is_dir && modelData.kind === "video"
                        text: "󰕧"
                        font.family: Tokens.mono
                        font.pixelSize: 38
                        color: KappaTheme.sun
                    }

                    // Se for Arquivo Comprimido
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !modelData.is_dir && modelData.kind === "archive"
                        text: "󰛫"
                        font.family: Tokens.mono
                        font.pixelSize: 38
                        color: KappaTheme.inkDim
                    }

                    // Se for Outro Arquivo genérico
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !modelData.is_dir && modelData.kind !== "image" && modelData.kind !== "code" && modelData.kind !== "document" && modelData.kind !== "audio" && modelData.kind !== "video" && modelData.kind !== "archive"
                        text: "󰈔"
                        font.family: Tokens.mono
                        font.pixelSize: 38
                        color: KappaTheme.inkDim
                    }

                    // Fallback para imagem que ainda não carregou
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: modelData.kind === "image" && (!parent.children[0].visible || parent.children[0].status !== Image.Ready)
                        text: "󰋩"
                        font.family: Tokens.mono
                        font.pixelSize: 38
                        color: KappaTheme.sun
                    }
                }

                // Nome do Arquivo / Pasta (Nó 912: 14px Space Grotesk)
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: modelData.name
                    font.family: Tokens.ui
                    font.pixelSize: 13
                    font.bold: modelData.is_dir
                    color: KappaTheme.ink
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Metadados (Nó 913: 11px SpaceMono Nerd Font)
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: {
                        var sz = modelData.is_dir ? "—" : modelData.size_formatted;
                        return modelData.modified_formatted + " · " + sz;
                    }
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.inkFaint
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: gridMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton && root.selectedSet[modelData.path] === true) {
                        // botão direito sobre item já selecionado preserva a seleção múltipla
                    } else {
                        root.itemClicked(modelData, mouse.modifiers);
                    }
                    if (typeof app !== "undefined" && app) {
                        app.forceActiveFocus();
                    }
                    if (mouse.button === Qt.RightButton) {
                        var map = gridMouse.mapToItem(null, mouse.x, mouse.y);
                        root.contextMenuRequested(modelData, map.x, map.y);
                    }
                }
                onDoubleClicked: function(mouse) {
                    if (mouse.button === Qt.LeftButton) {
                        root.itemActivated(modelData);
                    }
                }
            }

            Behavior on color {
                ColorAnimation { duration: 120; easing.type: Easing.OutExpo }
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutExpo }
        }
    }
}
