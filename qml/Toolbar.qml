import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    height: 52
    color: KappaTheme.paper

    property string currentPath: ""
    property string viewMode: "list" // "list" | "grid"
    property bool isSplit: false
    property bool showDetails: false
    property string sortField: "name"
    property string sortDirection: "asc"
    property bool groupByType: false
    property bool isCompact: false
    property bool isActivePane: true
    property bool showCloseSplit: false
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    readonly property string sortLabel: {
        var fieldName = "Nome";
        if (root.sortField === "type") fieldName = root.isPt ? "Tipo" : "Type";
        else if (root.sortField === "modified") fieldName = root.isPt ? "Data" : "Date";
        else if (root.sortField === "size") fieldName = root.isPt ? "Tamanho" : "Size";
        else fieldName = root.isPt ? "Nome" : "Name";
        var arrow = root.sortDirection === "asc" ? "↑" : "↓";
        return fieldName + " " + arrow;
    }

    signal navigateRequested(string path)
    signal toggleSplitRequested()
    signal toggleDetailsRequested()
    signal sortMenuRequested(real posX, real posY)
    signal toggleGroupRequested()
    signal closeSplitRequested()

    property bool isEditingPath: false
    property var suggestions: []
    property int suggestIndex: -1
    property string pathError: ""
    property string nearestParent: ""
    z: 5

    readonly property string backendBin: (typeof app !== "undefined" && app) ? app.backendBin : ""

    function startEdit() {
        pathInput.text = root.currentPath === "/" ? "/" : root.currentPath + "/";
        root.pathError = "";
        root.suggestions = [];
        root.suggestIndex = -1;
        root.isEditingPath = true;
        pathInput.forceActiveFocus();
        pathInput.selectAll();
        suggestTimer.restart();
    }

    // Texto relativo ("docs", "../x") é interpretado a partir da pasta atual
    function expand(txt) {
        if (txt.charAt(0) === "/" || txt.charAt(0) === "~") return txt;
        return (root.currentPath === "/" ? "" : root.currentPath) + "/" + txt;
    }

    function cancelEdit() {
        root.isEditingPath = false;
        root.suggestions = [];
        root.pathError = "";
        if (typeof app !== "undefined" && app) app.forceActiveFocus();
    }

    function applySuggestion(sug, commit) {
        pathInput.text = sug.full_path + (sug.is_dir ? "/" : "");
        pathInput.cursorPosition = pathInput.text.length;
        root.suggestIndex = -1;
        if (commit) root.commitEdit();
        else suggestTimer.restart();
    }

    // Enter: resolve ("~", relativo, etc.) e navega; se não existir, mostra o erro com o pai mais próximo
    function commitEdit() {
        var txt = pathInput.text.trim();
        if (txt.length === 0) { root.cancelEdit(); return; }
        resolveProc.command = [root.backendBin, "--resolve-json", root.expand(txt)];
        resolveProc.running = true;
    }

    Timer {
        id: suggestTimer
        interval: 120
        onTriggered: {
            if (!root.isEditingPath || root.backendBin === "") return;
            autoProc.command = [root.backendBin, "--autocomplete-json", root.expand(pathInput.text)];
            if (autoProc.running) autoProc.running = false;
            autoProc.running = true;
        }
    }

    // Perder o foco fecha a edição (com folga para o clique numa sugestão)
    Timer {
        id: blurTimer
        interval: 160
        onTriggered: if (root.isEditingPath && !pathInput.activeFocus) root.cancelEdit()
    }

    Process {
        id: autoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok && root.isEditingPath) root.suggestions = (data.suggestions || []).slice(0, 8);
                } catch (e) {}
            }
        }
    }

    Process {
        id: resolveProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok) {
                        root.isEditingPath = false;
                        root.suggestions = [];
                        root.navigateRequested(data.path);
                        if (typeof app !== "undefined" && app) app.forceActiveFocus();
                    } else {
                        var payload = data.error && data.error.payload ? data.error.payload : null;
                        root.nearestParent = payload && payload.nearest_existing_parent ? payload.nearest_existing_parent : "";
                        root.pathError = (data.error && data.error.type) ? data.error.type : "error";
                        root.suggestions = [];
                    }
                } catch (e) {}
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 12

        // Botões de navegação Voltar / Subir pasta
        Rectangle {
            implicitWidth: 28
            implicitHeight: 28
            radius: root.effectiveRadius
            color: upMouse.containsMouse ? KappaTheme.tint10 : "transparent"
            border.width: 1
            border.color: KappaTheme.line

            Text {
                anchors.centerIn: parent
                text: "󰁝"
                font.family: Tokens.mono
                font.pixelSize: 14
                color: KappaTheme.inkDim
            }

            MouseArea {
                id: upMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var parts = root.currentPath.split("/").filter(function(p) { return p.length > 0 });
                    if (parts.length > 0) {
                        parts.pop();
                        var newPath = "/" + parts.join("/");
                        root.navigateRequested(newPath === "" ? "/" : newPath);
                    }
                    if (typeof app !== "undefined" && app) app.forceActiveFocus();
                }
            }
        }

        // Barra de caminho: clique num nível navega; clique no espaço vazio (ou Ctrl+L) edita o caminho
        Item {
            id: pathBar
            Layout.fillWidth: true
            Layout.minimumWidth: 120
            height: 32
            clip: !root.isEditingPath

            // Clicar em qualquer ponto livre da barra entra no modo de edição
            MouseArea {
                anchors.fill: parent
                visible: !root.isEditingPath
                cursorShape: Qt.IBeamCursor
                onClicked: root.startEdit()
            }

            // Modo Breadcrumb (Normal): em espaço curto, os primeiros níveis saem pela esquerda e o final fica visível
            RowLayout {
                id: crumbRow
                height: parent.height
                x: Math.min(0, parent.width - implicitWidth)
                visible: !root.isEditingPath
                spacing: 6

                Repeater {
                    id: crumbRepeater
                    model: {
                        var p = root.currentPath;
                        if (!p || p === "/") return [{ label: "/", path: "/" }];
                        var parts = p.split("/").filter(function(s) { return s.length > 0; });
                        var res = [];
                        var accum = "";
                        var start = 0;
                        if (parts[0] === "home" && parts.length >= 2) {
                            // /home/<usuário> vira o primeiro nível "Home"
                            accum = "/home/" + parts[1];
                            res.push({ label: "Home", path: accum });
                            start = 2;
                        } else {
                            res.push({ label: "/", path: "/" });
                        }
                        for (var i = start; i < parts.length; i++) {
                            accum += "/" + parts[i];
                            res.push({ label: parts[i], path: accum });
                        }
                        return res;
                    }

                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        readonly property bool isLast: index === crumbRepeater.count - 1
                        spacing: 6

                        Text {
                            text: modelData.label
                            font.family: Tokens.ui
                            font.pixelSize: 13
                            font.bold: parent.isLast
                            color: crumbMouse.containsMouse ? KappaTheme.sun : KappaTheme.ink

                            MouseArea {
                                id: crumbMouse
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.navigateRequested(modelData.path);
                                    if (typeof app !== "undefined" && app) app.forceActiveFocus();
                                }
                            }
                        }

                        Text {
                            visible: modelData.label !== "/"
                            text: "/"
                            font.family: Tokens.mono
                            font.pixelSize: 12
                            color: KappaTheme.inkFaint
                        }
                    }
                }
            }

            // Modo Edição Direta de Caminho (Kappa / Caminho editável)
            Rectangle {
                id: editBox
                anchors.fill: parent
                visible: root.isEditingPath
                radius: root.effectiveRadius
                color: KappaTheme.paperLift
                border.width: 1
                border.color: root.pathError !== "" ? Tokens.sun : KappaTheme.sun

                TextInput {
                    id: pathInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    color: KappaTheme.ink
                    selectionColor: KappaTheme.sun
                    selectedTextColor: KappaTheme.inkOnBone
                    selectByMouse: true
                    clip: true
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    verticalAlignment: TextInput.AlignVCenter

                    onTextEdited: {
                        root.pathError = "";
                        root.suggestIndex = -1;
                        suggestTimer.restart();
                    }

                    onActiveFocusChanged: {
                        if (!activeFocus && root.isEditingPath) blurTimer.restart();
                    }

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.cancelEdit();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && root.suggestions.length > 0) {
                            root.suggestIndex = Math.min(root.suggestions.length - 1, root.suggestIndex + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && root.suggestions.length > 0) {
                            root.suggestIndex = Math.max(-1, root.suggestIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            // Tab completa com a sugestão destacada (ou a primeira)
                            if (root.suggestions.length > 0) {
                                var pick = root.suggestions[Math.max(0, root.suggestIndex)];
                                root.applySuggestion(pick, false);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.suggestIndex >= 0 && root.suggestIndex < root.suggestions.length) {
                                root.applySuggestion(root.suggestions[root.suggestIndex], true);
                            } else {
                                root.commitEdit();
                            }
                            event.accepted = true;
                        }
                    }
                }

                // Lista de sugestões / erro de caminho inexistente
                Rectangle {
                    id: popup
                    visible: root.isEditingPath && (root.suggestions.length > 0 || root.pathError !== "")
                    y: parent.height + 4
                    width: parent.width
                    height: popupCol.implicitHeight + 8
                    radius: root.effectiveRadius
                    color: KappaTheme.paperLift
                    border.width: 1
                    border.color: root.pathError !== "" ? Tokens.sun : KappaTheme.lineStrong
                    z: 20

                    Column {
                        id: popupCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4

                        // Erro: caminho inexistente + atalho para o pai existente mais próximo
                        Item {
                            visible: root.pathError !== ""
                            width: parent.width
                            height: visible ? 52 : 0

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                spacing: 3
                                Row {
                                    spacing: 8
                                    Text { text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                                    Text {
                                        text: root.isPt ? "CAMINHO NÃO ENCONTRADO_" : "PATH NOT FOUND_"
                                        font.family: Tokens.ui
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        font.letterSpacing: 2.2
                                        color: Tokens.sun
                                    }
                                }
                                Text {
                                    visible: root.nearestParent !== ""
                                    text: (root.isPt ? "Ir para " : "Go to ") + root.nearestParent
                                    font.family: Tokens.mono
                                    font.pixelSize: 12
                                    font.underline: true
                                    color: KappaTheme.sun
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.isEditingPath = false;
                                            root.navigateRequested(root.nearestParent);
                                            if (typeof app !== "undefined" && app) app.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.suggestions
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: popupCol.width
                                height: 30
                                radius: Math.max(0, root.effectiveRadius - 2)
                                color: (index === root.suggestIndex || sugMouse.containsMouse) ? KappaTheme.tint10 : "transparent"

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    spacing: 8
                                    Text {
                                        text: modelData.is_dir ? "󰉋" : "󰈔"
                                        font.family: Tokens.mono
                                        font.pixelSize: 13
                                        color: modelData.is_dir ? KappaTheme.sun : KappaTheme.inkDim
                                    }
                                    Text {
                                        text: modelData.full_path
                                        font.family: Tokens.mono
                                        font.pixelSize: 12
                                        color: KappaTheme.ink
                                    }
                                }

                                MouseArea {
                                    id: sugMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.applySuggestion(modelData, true)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Botão Ordenar (Nó 51: 139x30)
        Rectangle {
            id: sortBtn
            implicitWidth: sortRow.implicitWidth + 24
            implicitHeight: 30
            radius: root.effectiveRadius
            color: sortBtnMouse.containsMouse ? KappaTheme.tint10 : "transparent"
            border.width: 1
            border.color: KappaTheme.lineStrong
            visible: !root.isCompact

            RowLayout {
                id: sortRow
                anchors.centerIn: parent
                spacing: 12

                Text {
                    text: root.isPt ? "Ordenar" : "Sort"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    color: KappaTheme.inkDim
                }

                Text {
                    text: root.sortLabel
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    font.bold: true
                    color: KappaTheme.sun
                }
            }

            MouseArea {
                id: sortBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var map = sortBtn.mapToItem(null, 0, sortBtn.height + 4);
                    root.sortMenuRequested(map.x, map.y);
                }
            }
        }

        // Botão Agrupar (Nó 2707: 145x30)
        Rectangle {
            implicitWidth: groupRow.implicitWidth + 24
            implicitHeight: 30
            radius: root.effectiveRadius
            color: root.groupByType ? KappaTheme.tint16 : (groupBtnMouse.containsMouse ? KappaTheme.tint10 : "transparent")
            border.width: 1
            border.color: root.groupByType ? KappaTheme.sun : KappaTheme.lineStrong
            visible: !root.isCompact

            RowLayout {
                id: groupRow
                anchors.centerIn: parent
                spacing: 12

                Text {
                    text: root.isPt ? "Agrupar" : "Group"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    color: KappaTheme.inkDim
                }

                Text {
                    text: root.groupByType ? (root.isPt ? "Tipo" : "Type") : (root.isPt ? "Nenhum" : "None")
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    font.bold: true
                    color: KappaTheme.sun
                }
            }

            MouseArea {
                id: groupBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleGroupRequested()
            }
        }

        // Seletor de Modo: Lista | Grade (Nó 2704: 110x30)
        Rectangle {
            implicitWidth: 110
            implicitHeight: 30
            radius: root.effectiveRadius
            color: "transparent"
            border.width: 1
            border.color: KappaTheme.lineStrong

            RowLayout {
                anchors.fill: parent
                spacing: 8
                anchors.leftMargin: 10
                anchors.rightMargin: 10

                Text {
                    Layout.fillWidth: true
                    text: root.isPt ? "Lista" : "List"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    font.bold: root.viewMode === "list"
                    color: root.viewMode === "list" ? KappaTheme.sun : KappaTheme.inkDim
                    horizontalAlignment: Text.AlignHCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMode = "list"
                    }
                }

                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    color: KappaTheme.line
                }

                Text {
                    Layout.fillWidth: true
                    text: root.isPt ? "Grade" : "Grid"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    font.bold: root.viewMode === "grid"
                    color: root.viewMode === "grid" ? KappaTheme.sun : KappaTheme.inkDim
                    horizontalAlignment: Text.AlignHCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMode = "grid"
                    }
                }
            }
        }

        // Botão Dividir Visualização (Split View - F3)
        Rectangle {
            implicitWidth: 32
            implicitHeight: 30
            radius: root.effectiveRadius
            color: root.isSplit ? KappaTheme.sun : (splitMouse.containsMouse ? KappaTheme.tint10 : "transparent")
            border.width: 1
            border.color: root.isSplit ? KappaTheme.sun : KappaTheme.line
            visible: !root.isCompact

            Text {
                anchors.centerIn: parent
                text: "󰤼"
                font.family: Tokens.mono
                font.pixelSize: 14
                color: root.isSplit ? KappaTheme.paper : (splitMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkDim)
            }

            MouseArea {
                id: splitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSplitRequested()
            }
        }

        // Botão Painel de Detalhes (Nó 155 - Ctrl+I / Alt+Enter)
        Rectangle {
            implicitWidth: 32
            implicitHeight: 30
            radius: root.effectiveRadius
            color: root.showDetails ? KappaTheme.sun : (detailsMouse.containsMouse ? KappaTheme.tint10 : "transparent")
            border.width: 1
            border.color: root.showDetails ? KappaTheme.sun : KappaTheme.line
            visible: !root.isCompact

            Text {
                anchors.centerIn: parent
                text: "󰋽"
                font.family: Tokens.mono
                font.pixelSize: 14
                color: root.showDetails ? KappaTheme.paper : (detailsMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkDim)
            }

            MouseArea {
                id: detailsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleDetailsRequested()
            }
        }

        // Botão Fechar Painel Dividido (✕)
        Rectangle {
            implicitWidth: 30
            implicitHeight: 30
            radius: root.effectiveRadius
            color: closeSplitMouse.containsMouse ? KappaTheme.tint10 : "transparent"
            border.width: 1
            border.color: KappaTheme.line
            visible: root.showCloseSplit

            Text {
                anchors.centerIn: parent
                text: "󰅖"
                font.family: Tokens.mono
                font.pixelSize: 12
                color: closeSplitMouse.containsMouse ? KappaTheme.sun : KappaTheme.inkDim
            }

            MouseArea {
                id: closeSplitMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeSplitRequested()
            }
        }
    }

    // Linha técnica inferior / Linha ativa do Split (Nó 2651 e 2652)
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.isCompact ? 2 : 1
        color: root.isCompact ? KappaTheme.sun : KappaTheme.line
        opacity: root.isCompact ? (root.isActivePane ? 1.0 : 0.35) : 1.0
    }
}
