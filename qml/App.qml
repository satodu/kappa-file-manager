import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

Rectangle {
    id: app
    color: KappaTheme.paper
    radius: app.systemRadius
    clip: true
    border.width: 1
    border.color: KappaTheme.lineStrong
    focus: true
    Keys.onPressed: function(event) {
        app.handleKeyPress(event);
    }

    property string currentPath: Quickshell.env("KAPPA_START") || "/home/panda"
    property var currentEntries: []
    property var folderEntries: []
    property var rawEntries: []
    property var placesList: []
    property var devicesList: []
    property var selectedItem: null
    property string errorMessage: ""
    property string viewMode: Quickshell.env("KAPPA_VIEW") || "list" // "list" | "grid" | "kde"
    property var activeKdeDevice: null

    // Painel de Detalhes (Frame 155 - Kappa / Detalhes)
    property bool showDetails: false

    // Split View (Divisão em dois painéis lado a lado - F3)
    property bool isSplit: false
    property string rightPath: "/home/panda"
    property var rightEntries: []
    property var folderRightEntries: []
    property var rightSelectedItem: null
    property real splitRatio: 0.5
    property string activePane: "left" // "left" | "right"

    // Seleção múltipla (Ctrl+clique alterna, Shift+clique seleciona intervalo)
    property var selectedPaths: []
    property var rightSelectedPaths: []
    property string selectionAnchor: ""
    property var pendingSelectPaths: []
    property string pendingRenamePath: ""

    // Área de transferência / Clipboard (Ctrl+C, Ctrl+X, Ctrl+V)
    property var clipboardPaths: []
    property string clipboardAction: "" // "copy" | "cut"

    // Transferência em andamento (cartão de progresso)
    property string transferState: "idle" // "idle" | "running" | "paused" | "done" | "error"
    property string transferMode: "copy"
    property string transferName: ""
    property string transferDest: ""
    property string transferDestDir: ""
    property int transferIndex: 0
    property int transferItems: 0
    property real transferDone: 0
    property real transferTotal: 0
    property real transferSpeed: 0
    property real transferSeconds: 0
    property bool transferCancelled: false
    readonly property real transferFraction: app.transferTotal > 0 ? Math.min(1, app.transferDone / app.transferTotal) : (app.transferState === "done" ? 1 : 0)

    readonly property var activeSelectedItem: (app.isSplit && app.activePane === "right") ? app.rightSelectedItem : app.selectedItem
    readonly property int activeSelectedCount: app.activePaths().length

    // Modal de confirmação de exclusão (Delete / Shift+Delete)
    property bool showDeleteModal: false

    // Diálogo de Aparência (tema próprio do Kappa)
    property bool showAppearance: false

    function openAppearance() {
        app.showAppearance = true;
        appearanceDialog.open();
    }

    // Atalhos de edição ficam desligados enquanto um campo de texto ou modal tem o foco
    readonly property bool shortcutsEnabled: !(titlebar && titlebar.isSearchFocused) && !app.showRenameModal && !app.showDeleteModal && !app.showAppearance

    // Exibição de Arquivos Ocultos (Ctrl+H)
    property bool showHidden: false

    // Modal de Renomeação (F2)
    property bool showRenameModal: false
    property var renameTargetItem: null

    // Ordenação e Agrupamento (Nós 51, 2707, 2866, 2710 do Figcraft)
    property string sortField: "name" // "name" | "type" | "modified" | "size"
    property string sortDirection: "asc" // "asc" | "desc"
    property bool groupByType: false

    readonly property bool isPt: I18n.lang.startsWith("pt")

    FileView {
        id: shellConfigView
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/shell.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
    }

    // Raio de borda dinâmico configurado no Ryoku (shell.json radius_widget ou Tokens.radius)
    readonly property int systemRadius: {
        try {
            var txt = shellConfigView.text();
            if (txt && txt.length > 0) {
                var cfg = JSON.parse(txt);
                if (cfg && cfg.theme && cfg.theme.attributes && cfg.theme.attributes.sizing && typeof cfg.theme.attributes.sizing.radius_widget === "number") {
                    return Tokens.px(cfg.theme.attributes.sizing.radius_widget);
                }
            }
        } catch(e) {}
        return Tokens.radius;
    }

    // Gerenciador de Abas (inicia com 1 aba, e a barra só surge com > 1 aba)
    property var tabs: [
        { id: 0, title: "Home", path: Quickshell.env("KAPPA_START") || "/home/panda" }
    ]
    property int activeTabIndex: 0

    // Estado da Busca
    property bool isSearching: false
    property string activeSearchQuery: ""
    property string activeCategoryFilter: "all"
    property string searchScope: "folder"
    property var categoryCounts: ({ all: 0, audio: 0, image: 0, doc: 0, folder: 0, code: 0 })

    // Nome da pasta atual formatado para título
    readonly property string currentFolderName: {
        if (app.viewMode === "kde" && app.activeKdeDevice) {
            return app.activeKdeDevice.label;
        }
        if (!app.currentPath || app.currentPath === "/") {
            return app.isPt ? "Sistema" : "System";
        }
        var parts = app.currentPath.split("/").filter(function(s) { return s.length > 0; });
        return parts.length > 0 ? parts[parts.length - 1] : "Home";
    }

    readonly property string rightFolderName: {
        if (!app.rightPath || app.rightPath === "/") {
            return app.isPt ? "Sistema" : "System";
        }
        var parts = app.rightPath.split("/").filter(function(s) { return s.length > 0; });
        return parts.length > 0 ? parts[parts.length - 1] : "Home";
    }

    // Placa brutalista dinâmica do cabeçalho
    readonly property string activePlateName: {
        if (app.groupByType) return app.isPt ? "07 // TIPOS" : "07 // TYPES";
        if (app.showDetails) return app.isPt ? "02 // DETALHES" : "02 // DETAILS";
        if (app.viewMode === "kde") return "04 // KDE CONNECT";
        if (app.isSearching) return app.isPt ? "08 // BUSCA" : "08 // SEARCH";
        if (app.viewMode === "grid") return app.isPt ? "05 // GRADE" : "05 // GRID";
        return app.isPt ? "01 // ARQUIVOS" : "01 // FILES";
    }

    readonly property string backendBin: "/home/panda/orca/projects/kappa-file-manager/target/debug/kappa-file-manager"

    // Processo para listar arquivos (Painel Principal)
    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok) {
                        app.currentPath = data.path;
                        app.folderEntries = data.entries || [];
                        app.rawEntries = (data.entries || []).slice();
                        app.filterAndDisplayEntries();
                        app.selectedItem = null;
                        app.selectedPaths = [];
                        app.errorMessage = "";
                        app.forceActiveFocus();
                        app.applyPendingSelection("left");

                        // Atualiza o título da aba atual
                        var parts = data.path.split("/").filter(function(s) { return s.length > 0; });
                        var tabTitle = parts.length > 0 ? parts[parts.length - 1] : (app.isPt ? "Sistema" : "System");
                        var updated = [];
                        for (var i = 0; i < app.tabs.length; i++) {
                            if (i === app.activeTabIndex) {
                                updated.push({ id: app.tabs[i].id, title: tabTitle, path: data.path });
                            } else {
                                updated.push(app.tabs[i]);
                            }
                        }
                        app.tabs = updated;
                    } else {
                        app.errorMessage = data.error || (app.isPt ? "Erro ao acessar caminho" : "Error accessing path");
                    }
                } catch (e) {
                    console.error("Falha ao parsear listagem:", e);
                }
            }
        }
    }

    // Processo para listar arquivos (Painel Direito do Split View)
    Process {
        id: rightListProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok) {
                        app.rightPath = data.path;
                        app.folderRightEntries = data.entries || [];
                        app.rightEntries = (data.entries || []).slice();
                        app.rightSelectedItem = null;
                        app.rightSelectedPaths = [];
                        app.forceActiveFocus();
                        app.applyPendingSelection("right");
                    }
                } catch (e) {
                    console.error("Falha ao parsear listagem direita:", e);
                }
            }
        }
    }

    // Processo para carregar lugares e dispositivos
    Process {
        id: placesProc
        command: [app.backendBin, "--places-json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok) {
                        app.placesList = data.places || [];
                        app.devicesList = data.devices || [];
                    }
                } catch (e) {
                    console.error("Falha ao parsear lugares:", e);
                }
            }
        }
    }

    // Monitoramento reativo em tempo real de dispositivos conectados / montagens
    Timer {
        id: placesAutoRefresh
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (!placesProc.running) {
                placesProc.running = true;
            }
        }
    }

    FileView {
        id: mountsWatcher
        path: "/proc/mounts"
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            if (!placesProc.running) {
                placesProc.running = true;
            }
        }
    }

    // Processo para busca inline
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok) {
                        var searchEntries = [];
                        for (var i = 0; i < data.results.length; i++) {
                            searchEntries.push(data.results[i].entry);
                        }
                        app.rawEntries = searchEntries;
                        app.filterAndDisplayEntries();
                    }
                } catch (e) {
                    console.error("Falha ao parsear busca:", e);
                }
            }
        }
    }

    // Processos de ações
    Process {
        id: actionProc
        onExited: {
            if (app.isSplit && app.activePane === "right") {
                app.loadRightFolder(app.rightPath);
            } else {
                app.loadFolder(app.currentPath);
            }
        }
    }

    // Processo de montagem de dispositivo removível (udisksctl)
    Process {
        id: mountProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok && data.path) {
                        placesProc.running = true;
                        if (app.isSplit && app.activePane === "right") {
                            app.loadRightFolder(data.path);
                        } else {
                            app.loadFolder(data.path);
                        }
                    }
                } catch (e) {
                    console.error("Falha ao montar dispositivo:", e);
                }
            }
        }
    }

    // Processo de ejeção de dispositivo removível
    Process {
        id: ejectProc
        onExited: placesProc.running = true
    }

    function mountAndOpenDevice(device) {
        if (device.device_block) {
            mountProc.command = [app.backendBin, "--mount-device", device.device_block];
            mountProc.running = true;
        } else if (device.path) {
            if (app.isSplit && app.activePane === "right") {
                loadRightFolder(device.path);
            } else {
                loadFolder(device.path);
            }
        }
    }

    function ejectDevice(blockOrPath) {
        ejectProc.command = [app.backendBin, "--eject-device", blockOrPath];
        ejectProc.running = true;
    }

    // Processo para Copiar e Mover (Colar) arquivos
    Process {
        id: copyPasteProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data && !data.ok && data.error) {
                        app.errorMessage = data.error;
                    }
                } catch(e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim().length > 0) {
                    console.error("Erro na cópia:", this.text);
                }
            }
        }
        onExited: function(code) {
            if (app.isSplit && app.activePane === "right") {
                app.loadRightFolder(app.rightPath);
            } else {
                app.loadFolder(app.currentPath);
            }
        }
    }

    // Processo de criação de pasta: ao terminar, a nova pasta já abre para renomear
    Process {
        id: newFolderProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.ok && data.path) {
                        app.pendingRenamePath = data.path;
                        if (app.isSplit && app.activePane === "right") {
                            app.loadRightFolder(app.rightPath);
                        } else {
                            app.loadFolder(app.currentPath);
                        }
                    } else if (data.error) {
                        app.errorMessage = data.error;
                    }
                } catch (e) {}
            }
        }
    }

    function createNewFolder() {
        var targetDir = (app.isSplit && app.activePane === "right") ? app.rightPath : app.currentPath;
        var folderName = app.isPt ? "Nova pasta" : "New Folder";
        newFolderProc.command = [app.backendBin, "--new-folder", targetDir, folderName];
        newFolderProc.running = true;
    }

    // Seleciona (e/ou abre renomear) itens recém-criados depois que a listagem carrega
    function applyPendingSelection(pane) {
        var list = pane === "right" ? app.rightEntries : app.currentEntries;
        var ownsPending = function(path) {
            var dir = path.substring(0, path.lastIndexOf("/")) || "/";
            return dir === (pane === "right" ? app.rightPath : app.currentPath);
        };

        if (app.pendingRenamePath !== "" && ownsPending(app.pendingRenamePath)) {
            for (var i = 0; i < list.length; i++) {
                if (list[i].path === app.pendingRenamePath) {
                    app.setSelection(pane, [list[i].path], list[i]);
                    app.selectionAnchor = list[i].path;
                    app.pendingRenamePath = "";
                    app.startRename(list[i]);
                    return;
                }
            }
        }

        if (app.pendingSelectPaths.length > 0) {
            var wanted = {};
            var mine = [];
            for (var k = 0; k < app.pendingSelectPaths.length; k++) {
                if (ownsPending(app.pendingSelectPaths[k])) mine.push(app.pendingSelectPaths[k]);
            }
            for (var m = 0; m < mine.length; m++) wanted[mine[m]] = true;
            var found = [];
            var first = null;
            for (var j = 0; j < list.length; j++) {
                if (wanted[list[j].path]) {
                    found.push(list[j].path);
                    if (!first) first = list[j];
                }
            }
            if (found.length > 0) {
                app.setSelection(pane, found, first);
                app.selectionAnchor = first.path;
                app.pendingSelectPaths = app.pendingSelectPaths.filter(function(p) { return !wanted[p]; });
            }
        }
    }

    // ── Seleção ──────────────────────────────────────────────────────────
    function activeEntries() {
        return (app.isSplit && app.activePane === "right") ? app.rightEntries : app.currentEntries;
    }

    function activePaths() {
        return (app.isSplit && app.activePane === "right") ? app.rightSelectedPaths : app.selectedPaths;
    }

    function setSelection(pane, paths, primary) {
        if (pane === "right") {
            app.rightSelectedPaths = paths;
            app.rightSelectedItem = primary;
        } else {
            app.selectedPaths = paths;
            app.selectedItem = primary;
        }
    }

    function clearSelection(pane) {
        app.setSelection(pane, [], null);
        app.selectionAnchor = "";
    }

    function selectedItems() {
        var set = {};
        var paths = app.activePaths();
        for (var i = 0; i < paths.length; i++) set[paths[i]] = true;
        var list = app.activeEntries();
        var out = [];
        for (var j = 0; j < list.length; j++) {
            if (set[list[j].path]) out.push(list[j]);
        }
        return out;
    }

    // Itens-alvo de uma ação: a seleção inteira se o item clicado faz parte dela, senão só o item
    function targetsFor(item) {
        var sel = app.selectedItems();
        if (item && item.path) {
            for (var i = 0; i < sel.length; i++) {
                if (sel[i].path === item.path) return sel;
            }
            return [item];
        }
        return sel;
    }

    function indexOfPath(list, path) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].path === path) return i;
        }
        return -1;
    }

    function rangePaths(list, fromPath, toPath) {
        var a = app.indexOfPath(list, fromPath);
        var b = app.indexOfPath(list, toPath);
        if (a < 0 || b < 0) return [toPath];
        var lo = Math.min(a, b);
        var hi = Math.max(a, b);
        var out = [];
        for (var i = lo; i <= hi; i++) out.push(list[i].path);
        return out;
    }

    function clickItem(pane, item, modifiers) {
        var right = pane === "right";
        if (app.isSplit) app.activePane = right ? "right" : "left";
        var list = right ? app.rightEntries : app.currentEntries;
        var paths = (right ? app.rightSelectedPaths : app.selectedPaths).slice();
        var ctrl = (modifiers & Qt.ControlModifier) !== 0;
        var shift = (modifiers & Qt.ShiftModifier) !== 0;

        if (shift && app.selectionAnchor !== "" && app.indexOfPath(list, app.selectionAnchor) >= 0) {
            app.setSelection(pane, app.rangePaths(list, app.selectionAnchor, item.path), item);
        } else if (ctrl) {
            var at = paths.indexOf(item.path);
            if (at >= 0) {
                paths.splice(at, 1);
                var keep = paths.length > 0 ? list[app.indexOfPath(list, paths[paths.length - 1])] : null;
                app.setSelection(pane, paths, keep || null);
            } else {
                paths.push(item.path);
                app.setSelection(pane, paths, item);
            }
            app.selectionAnchor = item.path;
        } else {
            app.setSelection(pane, [item.path], item);
            app.selectionAnchor = item.path;
        }
    }

    function selectAll() {
        var pane = (app.isSplit && app.activePane === "right") ? "right" : "left";
        var list = app.activeEntries();
        if (!list || list.length === 0) return;
        var all = [];
        for (var i = 0; i < list.length; i++) all.push(list[i].path);
        var cur = pane === "right" ? app.rightSelectedItem : app.selectedItem;
        app.setSelection(pane, all, cur || list[0]);
        if (app.selectionAnchor === "") app.selectionAnchor = list[0].path;
    }

    // ── Área de transferência ────────────────────────────────────────────
    function copyItem(item) {
        var targets = app.targetsFor(item);
        if (targets.length === 0) return;
        app.clipboardPaths = targets.map(function(t) { return t.path; });
        app.clipboardAction = "copy";
        Quickshell.clipboardText = app.clipboardPaths.join("\n");
    }

    function cutItem(item) {
        var targets = app.targetsFor(item);
        if (targets.length === 0) return;
        app.clipboardPaths = targets.map(function(t) { return t.path; });
        app.clipboardAction = "cut";
        Quickshell.clipboardText = app.clipboardPaths.join("\n");
    }

    function clipboardSources() {
        if (app.clipboardPaths.length > 0) return app.clipboardPaths;
        var raw = (Quickshell.clipboardText || "").trim();
        if (raw.length === 0) return [];
        var out = [];
        var lines = raw.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.startsWith("file://")) line = line.substring(7);
            try { line = decodeURIComponent(line); } catch (e) {}
            if (line.charAt(0) === "/") out.push(line);
        }
        return out;
    }

    function pasteItem() {
        var targetDir = (app.isSplit && app.activePane === "right") ? app.rightPath : app.currentPath;
        var sources = app.clipboardSources();
        if (sources.length === 0) return;
        if (app.transferState === "running" || app.transferState === "paused") return;
        app.startTransfer(app.clipboardAction === "cut" ? "move" : "copy", sources, targetDir);
    }

    // ── Transferência com progresso ──────────────────────────────────────
    Process {
        id: transferProc
        stdout: SplitParser {
            onRead: function(line) { app.onTransferLine(line); }
        }
        onExited: function(code) {
            if (app.transferState === "running" || app.transferState === "paused") {
                if (app.transferCancelled) {
                    app.transferState = "idle";
                } else if (code !== 0) {
                    app.transferState = "error";
                }
            }
            app.refreshPanes();
        }
    }

    Process { id: cleanupProc }

    Timer {
        id: transferHideTimer
        interval: 3500
        onTriggered: if (app.transferState === "done") app.transferState = "idle"
    }

    function refreshPanes() {
        app.loadFolder(app.currentPath);
        if (app.isSplit) app.loadRightFolder(app.rightPath);
    }

    function startTransfer(mode, sources, destDir) {
        transferHideTimer.stop();
        app.transferMode = mode;
        app.transferDestDir = destDir;
        app.transferName = sources.length > 0 ? sources[0].split("/").pop() : "";
        app.transferIndex = 0;
        app.transferItems = sources.length;
        app.transferDone = 0;
        app.transferTotal = 0;
        app.transferSpeed = 0;
        app.transferDest = "";
        app.transferCancelled = false;
        app.transferState = "running";
        transferProc.command = [app.backendBin, "--transfer", mode, destDir].concat(sources);
        transferProc.running = true;
    }

    function onTransferLine(line) {
        var ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        if (ev.event === "start") {
            app.transferTotal = ev.total || 0;
            app.transferItems = ev.items || app.transferItems;
        } else if (ev.event === "progress") {
            app.transferDone = ev.done || 0;
            app.transferTotal = ev.total || app.transferTotal;
            app.transferIndex = ev.index || 0;
            app.transferItems = ev.items || app.transferItems;
            app.transferName = ev.name || app.transferName;
            app.transferDest = ev.dest || "";
            app.transferSpeed = ev.speed || 0;
        } else if (ev.event === "done") {
            app.transferState = "done";
            app.transferDone = ev.bytes || app.transferDone;
            app.transferSeconds = ev.seconds || 0;
            app.transferDest = "";
            app.pendingSelectPaths = ev.paths || [];
            if (app.transferMode === "move") {
                app.clipboardPaths = [];
                app.clipboardAction = "";
            }
            transferHideTimer.restart();
        } else if (ev.event === "error") {
            app.transferState = "error";
            app.errorMessage = ev.error || "";
        }
    }

    function cancelTransfer() {
        if (app.transferState !== "running" && app.transferState !== "paused") {
            app.transferState = "idle";
            return;
        }
        app.transferCancelled = true;
        var partial = app.transferDest;
        if (app.transferState === "paused") transferProc.signal(18);
        transferProc.running = false;
        if (partial !== "") {
            cleanupProc.command = [app.backendBin, "--delete", partial];
            cleanupProc.running = true;
        }
        app.transferState = "idle";
    }

    function togglePauseTransfer() {
        if (app.transferState === "running") {
            transferProc.signal(19);
            app.transferState = "paused";
        } else if (app.transferState === "paused") {
            transferProc.signal(18);
            app.transferState = "running";
        }
    }

    function loadFolder(path) {
        if (app.viewMode === "kde") app.viewMode = "list";
        app.isSearching = false;
        app.activeSearchQuery = "";
        if (titlebar) {
            titlebar.clearSearch();
        }
        if (listProc.running) {
            listProc.running = false;
        }
        var cmd = [app.backendBin, "--list-json", path];
        if (app.showHidden) {
            cmd.push("--hidden");
        }
        listProc.command = cmd;
        listProc.running = true;
    }

    function loadRightFolder(path) {
        if (rightListProc.running) {
            rightListProc.running = false;
        }
        var cmd = [app.backendBin, "--list-json", path];
        if (app.showHidden) {
            cmd.push("--hidden");
        }
        rightListProc.command = cmd;
        rightListProc.running = true;
    }

    function navigateUp() {
        var p = (app.isSplit && app.activePane === "right") ? app.rightPath : app.currentPath;
        var parts = p.split("/").filter(function(s) { return s.length > 0; });
        if (parts.length > 0) {
            parts.pop();
            var upPath = "/" + parts.join("/");
            if (app.isSplit && app.activePane === "right") {
                app.loadRightFolder(upPath);
            } else {
                app.loadFolder(upPath);
            }
        }
    }

    function startRename(item) {
        if (!item) {
            item = (app.isSplit && app.activePane === "right") ? app.rightSelectedItem : app.selectedItem;
        }
        if (!item) return;
        app.renameTargetItem = item;
        app.showRenameModal = true;
        renameModal.open(item);
    }

    function submitRename(newName) {
        if (!app.renameTargetItem || !newName || newName.trim() === "" || newName === app.renameTargetItem.name) {
            app.showRenameModal = false;
            app.renameTargetItem = null;
            app.forceActiveFocus();
            return;
        }
        var renamedDir = app.renameTargetItem.path.substring(0, app.renameTargetItem.path.lastIndexOf("/")) || "/";
        app.pendingSelectPaths = [(renamedDir === "/" ? "" : renamedDir) + "/" + newName.trim()];
        actionProc.command = [app.backendBin, "--rename", app.renameTargetItem.path, newName.trim()];
        actionProc.running = true;
        app.showRenameModal = false;
        app.renameTargetItem = null;
        app.forceActiveFocus();
    }

    function searchFiles(query) {
        var q = (query || "").trim();
        if (q === "") {
            app.isSearching = false;
            app.activeSearchQuery = "";
            if (app.searchScope === "all") {
                loadFolder(app.currentPath);
            } else {
                filterAndDisplayEntries();
            }
            return;
        }

        if (app.viewMode === "kde") app.viewMode = "list";
        app.isSearching = true;
        app.activeSearchQuery = q;

        if (app.searchScope === "all") {
            searchProc.command = [app.backendBin, "--search-json", app.currentPath, q];
            searchProc.running = true;
        } else {
            filterAndDisplayEntries();
        }
    }

    function filterAndDisplayEntries() {
        var counts = { all: 0, audio: 0, image: 0, doc: 0, folder: 0, code: 0 };
        var filtered = [];
        var query = (app.activeSearchQuery || "").trim().toLowerCase();

        var sourceList = (app.searchScope === "folder" && app.folderEntries.length > 0) ? app.folderEntries : app.rawEntries;

        for (var i = 0; i < sourceList.length; i++) {
            var item = Object.assign({}, sourceList[i]);

            var matchQuery = true;
            if (query.length > 0) {
                matchQuery = (item.name || "").toLowerCase().indexOf(query) !== -1;
            }

            if (!matchQuery) continue;

            counts.all++;

            if (item.is_dir) {
                counts.folder++;
                item.section_label = app.isPt ? "PASTAS_" : "FOLDERS_";
                item.kind_priority = 0;
            } else if (item.kind === "image") {
                counts.image++;
                item.section_label = app.isPt ? "IMAGENS_" : "IMAGES_";
                item.kind_priority = 1;
            } else if (item.kind === "document") {
                counts.doc++;
                item.section_label = app.isPt ? "DOCUMENTOS_" : "DOCUMENTS_";
                item.kind_priority = 2;
            } else if (item.kind === "audio") {
                counts.audio++;
                item.section_label = app.isPt ? "ÁUDIO_" : "AUDIO_";
                item.kind_priority = 3;
            } else if (item.kind === "video") {
                item.section_label = app.isPt ? "VÍDEOS_" : "VIDEOS_";
                item.kind_priority = 4;
            } else if (item.kind === "code") {
                counts.code++;
                item.section_label = app.isPt ? "CÓDIGO_" : "CODE_";
                item.kind_priority = 5;
            } else if (item.kind === "archive") {
                item.section_label = app.isPt ? "ARQUIVOS_" : "ARCHIVES_";
                item.kind_priority = 6;
            } else {
                item.section_label = app.isPt ? "OUTROS_" : "OTHER_";
                item.kind_priority = 7;
            }

            var matchCat = true;
            if (app.activeCategoryFilter === "audio") matchCat = item.kind === "audio";
            else if (app.activeCategoryFilter === "image") matchCat = item.kind === "image";
            else if (app.activeCategoryFilter === "doc") matchCat = item.kind === "document";
            else if (app.activeCategoryFilter === "folder") matchCat = item.is_dir;
            else if (app.activeCategoryFilter === "code") matchCat = item.kind === "code";

            if (matchCat) {
                filtered.push(item);
            }
        }

        // Ordenação Dinâmica (Nome, Tipo, Modificado, Tamanho / Asc, Desc)
        filtered.sort(function(a, b) {
            if (app.groupByType) {
                if (a.kind_priority !== b.kind_priority) {
                    return a.kind_priority - b.kind_priority;
                }
            } else {
                // Pastas sempre no topo
                if (a.is_dir !== b.is_dir) {
                    return b.is_dir ? 1 : -1;
                }
            }

            var cmp = 0;
            if (app.sortField === "type") {
                var ka = a.kind || "";
                var kb = b.kind || "";
                cmp = ka.localeCompare(kb);
                if (cmp === 0) cmp = a.name.localeCompare(b.name);
            } else if (app.sortField === "modified") {
                cmp = (a.modified_timestamp || 0) - (b.modified_timestamp || 0);
            } else if (app.sortField === "size") {
                cmp = (a.size_bytes || 0) - (b.size_bytes || 0);
            } else {
                cmp = a.name.localeCompare(b.name);
            }

            return app.sortDirection === "desc" ? -cmp : cmp;
        });

        app.categoryCounts = counts;
        app.currentEntries = filtered;

        // Auto-seleciona primeiro item filtrado quando houver busca ativa
        if (query.length > 0 && filtered.length > 0) {
            var found = false;
            if (app.selectedItem) {
                for (var j = 0; j < filtered.length; j++) {
                    if (filtered[j].path === app.selectedItem.path) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                app.selectedItem = filtered[0];
                app.selectedPaths = [filtered[0].path];
                app.selectionAnchor = filtered[0].path;
            }
        } else if (filtered.length === 0) {
            app.selectedItem = null;
            app.selectedPaths = [];
        }

        // Se estiver em split view com o painel direito ativo, filtra o painel direito também
        if (app.isSplit && app.activePane === "right") {
            var rightSource = app.folderRightEntries.length > 0 ? app.folderRightEntries : app.rightEntries;
            var filteredRight = [];
            for (var r = 0; r < rightSource.length; r++) {
                var rItem = Object.assign({}, rightSource[r]);
                if (query.length === 0 || (rItem.name || "").toLowerCase().indexOf(query) !== -1) {
                    filteredRight.push(rItem);
                }
            }
            app.rightEntries = filteredRight;
            if (query.length > 0 && filteredRight.length > 0) {
                app.rightSelectedItem = filteredRight[0];
            }
        }
    }

    // Colunas da grade (cada célula tem 184px; margens de 24px)
    function gridColumns() {
        var w = app.isSplit ? ((app.activePane === "right") ? splitFileListB.width : splitFileListA.width) : fileList.width;
        return Math.max(1, Math.floor((w - 48) / 184));
    }

    function selectNextItem(delta, extend) {
        var isRight = (app.isSplit && app.activePane === "right");
        var list = isRight ? app.rightEntries : app.currentEntries;
        if (!list || list.length === 0) return;

        var currentSel = isRight ? app.rightSelectedItem : app.selectedItem;
        var curIdx = -1;
        if (currentSel) {
            for (var i = 0; i < list.length; i++) {
                if (list[i].path === currentSel.path) {
                    curIdx = i;
                    break;
                }
            }
        }

        var nextIdx = curIdx < 0 ? (delta > 0 ? 0 : list.length - 1) : curIdx + delta;
        if (nextIdx < 0) nextIdx = 0;
        if (nextIdx >= list.length) nextIdx = list.length - 1;

        var pane = isRight ? "right" : "left";
        var target = list[nextIdx];
        if (extend && app.selectionAnchor !== "" && app.indexOfPath(list, app.selectionAnchor) >= 0) {
            app.setSelection(pane, app.rangePaths(list, app.selectionAnchor, target.path), target);
        } else {
            app.setSelection(pane, [target.path], target);
            app.selectionAnchor = target.path;
        }
    }

    function handleKeyPress(event) {
        if (app.showDeleteModal || app.showAppearance) return;

        // Esc fecha menus flutuantes abertos
        if (event.key === Qt.Key_Escape && (sortMenu.visible || contextMenu.visible)) {
            sortMenu.hide();
            contextMenu.hide();
            event.accepted = true;
            return;
        }

        // Se estiver com modal de renomear aberto, deixa o modal cuidar das teclas
        if (app.showRenameModal) {
            if (event.key === Qt.Key_Escape) {
                app.showRenameModal = false;
                app.renameTargetItem = null;
                app.forceActiveFocus();
                event.accepted = true;
            }
            return;
        }

        // Se a busca estiver com foco, não intercepta atalhos de texto
        if (titlebar && titlebar.isSearchFocused) {
            if (event.key === Qt.Key_Escape) {
                titlebar.clearSearch();
                app.forceActiveFocus();
                event.accepted = true;
            }
            return;
        }

        var isCtrl = (event.modifiers & Qt.ControlModifier) !== 0;
        var isAlt = (event.modifiers & Qt.AltModifier) !== 0;
        var isShift = (event.modifiers & Qt.ShiftModifier) !== 0;

        // --- ATALHOS BÁSICOS COM CTRL ---
        if (isCtrl && !isAlt) {
            // Ctrl+Shift+N: Nova pasta
            if (isShift && event.key === Qt.Key_N) {
                app.createNewFolder();
                event.accepted = true;
                return;
            }
            // Ctrl+C: Copiar
            if (event.key === Qt.Key_C) {
                app.copyItem(null);
                event.accepted = true;
                return;
            }
            // Ctrl+X: Recortar
            if (event.key === Qt.Key_X) {
                app.cutItem(null);
                event.accepted = true;
                return;
            }
            // Ctrl+V: Colar
            if (event.key === Qt.Key_V) {
                app.pasteItem();
                event.accepted = true;
                return;
            }
            // Ctrl+A: Selecionar primeiro/todos
            if (event.key === Qt.Key_A) {
                app.selectAll();
                event.accepted = true;
                return;
            }
            // Ctrl+F: Focar busca
            if (event.key === Qt.Key_F) {
                if (titlebar) titlebar.focusSearch();
                event.accepted = true;
                return;
            }
            // Ctrl+H: Alternar arquivos ocultos
            if (event.key === Qt.Key_H) {
                app.showHidden = !app.showHidden;
                app.loadFolder(app.currentPath);
                event.accepted = true;
                return;
            }
            // Ctrl+R: Recarregar pasta
            if (event.key === Qt.Key_R) {
                if (app.isSplit && app.activePane === "right") {
                    app.loadRightFolder(app.rightPath);
                } else {
                    app.loadFolder(app.currentPath);
                }
                event.accepted = true;
                return;
            }
            // Ctrl+T: Nova aba
            if (event.key === Qt.Key_T) {
                app.openNewTab(app.currentPath);
                event.accepted = true;
                return;
            }
            // Ctrl+W: Fechar aba
            if (event.key === Qt.Key_W) {
                app.closeTab(app.activeTabIndex);
                event.accepted = true;
                return;
            }
            // Ctrl+I: Detalhes
            if (event.key === Qt.Key_I) {
                app.showDetails = !app.showDetails;
                event.accepted = true;
                return;
            }
            return;
        }

        // --- ATALHOS COM ALT ---
        if (isAlt && !isCtrl) {
            // Alt+Up: Subir nível de pasta
            if (event.key === Qt.Key_Up) {
                app.navigateUp();
                event.accepted = true;
                return;
            }
            // Alt+Enter / Alt+Return: Detalhes
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                app.showDetails = !app.showDetails;
                event.accepted = true;
                return;
            }
            return;
        }

        // --- TECLAS FUNCIONAIS E DE NAVEGAÇÃO ---
        // F7: Nova pasta
        if (event.key === Qt.Key_F7) {
            app.createNewFolder();
            event.accepted = true;
            return;
        }

        // --- TECLAS FUNCIONAIS E DE NAVEGAÇÃO ---
        // F2: Renomear
        if (event.key === Qt.Key_F2) {
            var itemToRename = (app.isSplit && app.activePane === "right") ? app.rightSelectedItem : app.selectedItem;
            app.startRename(itemToRename);
            event.accepted = true;
            return;
        }

        // F3: Split View
        if (event.key === Qt.Key_F3) {
            app.isSplit = !app.isSplit;
            if (app.isSplit && app.rightEntries.length === 0) {
                app.loadRightFolder(app.currentPath);
            }
            event.accepted = true;
            return;
        }

        // F5: Recarregar
        if (event.key === Qt.Key_F5) {
            app.loadFolder(app.currentPath);
            event.accepted = true;
            return;
        }

        // Delete: confirmar e mover para lixeira (Shift+Delete: exclusão permanente)
        if (event.key === Qt.Key_Delete) {
            if (app.selectedItems().length > 0) {
                app.requestDelete(null, isShift);
                event.accepted = true;
                return;
            }
        }

        // Backspace: Subir nível de pasta se não estiver buscando
        if (event.key === Qt.Key_Backspace) {
            if (titlebar && titlebar.searchQuery && titlebar.searchQuery.length > 0) {
                var newText = titlebar.searchQuery.slice(0, -1);
                titlebar.searchQuery = newText;
                if (newText.length === 0) {
                    titlebar.clearSearch();
                }
                event.accepted = true;
                return;
            } else {
                app.navigateUp();
                event.accepted = true;
                return;
            }
        }

        // Escape: cancelar transferência, limpar busca ou desmarcar
        if (event.key === Qt.Key_Escape) {
            if (app.transferState === "running" || app.transferState === "paused") {
                app.cancelTransfer();
                event.accepted = true;
                return;
            }
            if (app.isSearching || (titlebar && titlebar.searchQuery && titlebar.searchQuery.length > 0)) {
                if (titlebar) titlebar.clearSearch();
                event.accepted = true;
                return;
            }
        }

        // Return / Enter: Abrir item selecionado
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var sel = (app.isSplit && app.activePane === "right") ? app.rightSelectedItem : app.selectedItem;
            if (sel) {
                app.openItem(sel);
                event.accepted = true;
                return;
            }
        }

        // Navegação por setas (Cima / Baixo)
        var inGrid = app.viewMode === "grid";
        if (event.key === Qt.Key_Down) {
            app.selectNextItem(inGrid ? app.gridColumns() : 1, isShift);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Up) {
            app.selectNextItem(inGrid ? -app.gridColumns() : -1, isShift);
            event.accepted = true;
            return;
        }
        if (inGrid && event.key === Qt.Key_Right) {
            app.selectNextItem(1, isShift);
            event.accepted = true;
            return;
        }
        if (inGrid && event.key === Qt.Key_Left) {
            app.selectNextItem(-1, isShift);
            event.accepted = true;
            return;
        }

        // Tecla Espaço (Space): se busca estiver vazia, alterna o Painel de Detalhes (QuickLook preview)
        if (event.key === Qt.Key_Space && (!titlebar || !titlebar.searchQuery || titlebar.searchQuery.length === 0)) {
            app.showDetails = !app.showDetails;
            event.accepted = true;
            return;
        }

        // Teclas com caracteres imprimíveis iniciam o filtro imediato na pasta ("Type-ahead find")
        if (!isCtrl && !isAlt && event.text && event.text.length > 0) {
            var chCode = event.text.charCodeAt(0);
            if (chCode >= 32) {
                if (titlebar) {
                    titlebar.appendSearchChar(event.text);
                }
                event.accepted = true;
                return;
            }
        }
    }

    function openItem(item) {
        if (item.is_dir) {
            if (app.isSplit && app.activePane === "right") {
                loadRightFolder(item.path);
            } else {
                loadFolder(item.path);
            }
        } else {
            actionProc.command = [app.backendBin, "--open", item.path];
            actionProc.running = true;
        }
    }

    function openNewTab(path) {
        var parts = path.split("/").filter(function(s) { return s.length > 0; });
        var title = parts.length > 0 ? parts[parts.length - 1] : (app.isPt ? "Pasta" : "Folder");
        var newTabs = app.tabs.slice();
        newTabs.push({ id: Date.now(), title: title, path: path });
        app.tabs = newTabs;
        app.activeTabIndex = newTabs.length - 1;
        loadFolder(path);
    }

    function closeTab(index) {
        if (app.tabs.length <= 1) return;
        var newTabs = app.tabs.slice();
        newTabs.splice(index, 1);
        app.tabs = newTabs;
        var newIndex = Math.min(app.activeTabIndex, newTabs.length - 1);
        app.activeTabIndex = newIndex;
        loadFolder(newTabs[newIndex].path);
    }

    function openTerminalAt(path) {
        var dir = path;
        for (var i = 0; i < app.currentEntries.length; i++) {
            if (app.currentEntries[i].path === path && !app.currentEntries[i].is_dir) {
                dir = app.currentPath;
                break;
            }
        }
        actionProc.command = ["ghostty", "--working-directory=" + dir];
        actionProc.running = true;
    }

    // Processo de exclusão (lixeira ou permanente) com retorno JSON
    Process {
        id: deleteProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data && !data.ok && data.error) {
                        app.errorMessage = data.error;
                    }
                } catch (e) {}
            }
        }
        onExited: {
            if (app.deleteQueue.length > 0) {
                app.runNextDelete();
            } else if (app.isSplit && app.activePane === "right") {
                app.loadRightFolder(app.rightPath);
            } else {
                app.loadFolder(app.currentPath);
            }
        }
    }

    property var deleteQueue: []
    property bool deleteQueuePermanent: false

    function runNextDelete() {
        var next = app.deleteQueue[0];
        app.deleteQueue = app.deleteQueue.slice(1);
        deleteProc.command = [app.backendBin, app.deleteQueuePermanent ? "--delete" : "--trash", next];
        deleteProc.running = true;
    }

    function requestDelete(item, permanent) {
        var targets = app.targetsFor(item);
        if (targets.length === 0) return;
        app.showDeleteModal = true;
        deleteModal.open(targets, !!permanent);
    }

    function confirmDelete() {
        var paths = [];
        for (var i = 0; i < deleteModal.targets.length; i++) paths.push(deleteModal.targets[i].path);
        app.deleteQueuePermanent = deleteModal.permanent;
        app.deleteQueue = paths;
        deleteModal.close();
        app.showDeleteModal = false;
        app.forceActiveFocus();
        if (paths.length > 0 && !deleteProc.running) app.runNextDelete();
    }

    function cancelDelete() {
        deleteModal.close();
        app.showDeleteModal = false;
        app.forceActiveFocus();
    }

    // Atalhos globais com contexto de janela (WindowShortcut)
    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Ctrl+T"
        onActivated: app.openNewTab(app.currentPath)
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Ctrl+W"
        onActivated: app.closeTab(app.activeTabIndex)
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "F3"
        onActivated: {
            app.isSplit = !app.isSplit;
            if (app.isSplit && app.rightEntries.length === 0) {
                app.loadRightFolder(app.currentPath);
            }
        }
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Ctrl+I"
        onActivated: app.showDetails = !app.showDetails
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Alt+Return"
        onActivated: app.showDetails = !app.showDetails
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequences: [ StandardKey.Copy ]
        onActivated: app.copyItem(null)
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequences: [ StandardKey.Cut ]
        onActivated: app.cutItem(null)
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequences: [ StandardKey.Paste ]
        onActivated: {
            app.pasteItem();
        }
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequences: [ StandardKey.SelectAll ]
        onActivated: app.selectAll()
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Ctrl+F"
        onActivated: titlebar.focusSearch()
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Ctrl+H"
        onActivated: {
            app.showHidden = !app.showHidden;
            app.loadFolder(app.currentPath);
        }
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequences: [ "F5", "Ctrl+R" ]
        onActivated: app.loadFolder(app.currentPath)
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequence: "F2"
        onActivated: {
            var target = (app.isSplit && app.activePane === "right") ? (app.rightSelectedItem || app.selectedItem) : app.selectedItem;
            app.startRename(target);
        }
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequence: "Delete"
        onActivated: app.requestDelete(null, false)
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequence: "Shift+Delete"
        onActivated: app.requestDelete(null, true)
    }

    Shortcut {
        context: Qt.WindowShortcut
        enabled: app.shortcutsEnabled
        sequences: [ "Ctrl+L", "Alt+D" ]
        onActivated: {
            if (app.viewMode === "kde") return;
            if (app.isSplit) (app.activePane === "right" ? paneBToolbar : paneAToolbar).startEdit();
            else toolbar.startEdit();
        }
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Ctrl+,"
        onActivated: app.openAppearance()
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequence: "Alt+Up"
        onActivated: app.navigateUp()
    }

    Component.onCompleted: {
        app.forceActiveFocus();
        placesProc.running = true;
        loadFolder(app.currentPath);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Barra de Título (Titlebar) com Placa e Busca dinâmicas
        Titlebar {
            id: titlebar
            Layout.fillWidth: true
            currentFolder: (app.isSplit && app.activePane === "right") ? app.rightFolderName : app.currentFolderName
            activePlate: app.activePlateName
            onSearchRequested: function(query) {
                app.searchFiles(query);
            }
            onSearchCleared: {
                app.searchFiles("");
            }
        }

        // Banner de erro: faixa com marcador "// ERRO_" e hairline
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: app.errorMessage !== "" ? 34 : 0
            visible: app.errorMessage !== ""
            color: Qt.rgba(Tokens.sun.r, Tokens.sun.g, Tokens.sun.b, 0.10)

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.rgba(Tokens.sun.r, Tokens.sun.g, Tokens.sun.b, 0.5)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 10

                Text { text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                Text {
                    text: app.isPt ? "ERRO_" : "ERROR_"
                    font.family: Tokens.ui
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.letterSpacing: 2.2
                    color: Tokens.sun
                }
                Text {
                    Layout.fillWidth: true
                    text: app.errorMessage
                    elide: Text.ElideRight
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    color: KappaTheme.ink
                }
                Text {
                    text: "×"
                    font.pixelSize: 18
                    color: KappaTheme.inkDim
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.errorMessage = ""
                    }
                }
            }
        }

        // Área Principal (Sidebar + Conteúdo Central + Painel de Detalhes)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Sidebar / Rail lateral com espaçamento exato do Figcraft
            Sidebar {
                Layout.fillHeight: true
                currentPath: app.currentPath
                placesList: app.placesList
                devicesList: app.devicesList
                onNavigateRequested: function(p) {
                    if (app.isSplit && app.activePane === "right") {
                        app.loadRightFolder(p);
                    } else {
                        app.loadFolder(p);
                    }
                }
                onKdeDeviceClicked: function(dev) {
                    app.activeKdeDevice = dev;
                    app.viewMode = "kde";
                }
                onDeviceMountRequested: function(dev) {
                    app.mountAndOpenDevice(dev);
                }
                onDeviceEjectRequested: function(blockOrPath) {
                    app.ejectDevice(blockOrPath);
                }
            }

            // Área Central (Abas + Toolbar + Filtros de Busca + Viewport de Arquivos)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Barra de Abas: Só aparece quando houver mais de uma aba!
                TabBar {
                    id: tabNav
                    Layout.fillWidth: true
                    Layout.preferredHeight: app.tabs.length > 1 ? 38 : 0
                    visible: app.tabs.length > 1
                    tabs: app.tabs
                    activeIndex: app.activeTabIndex
                    onTabSelected: function(idx, p) {
                        app.activeTabIndex = idx;
                        app.loadFolder(p);
                    }
                    onTabClosed: function(idx) {
                        app.closeTab(idx);
                    }
                    onNewTabRequested: {
                        app.openNewTab(app.currentPath);
                    }

                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 140; easing.type: Easing.OutExpo }
                    }
                }

                // Toolbar (Breadcrumbs + Ordenar + Agrupar + Modo + Dividir F3 + Detalhes)
                Toolbar {
                    id: toolbar
                    Layout.fillWidth: true
                    Layout.preferredHeight: (!app.isSplit && app.viewMode !== "kde") ? 52 : 0
                    visible: !app.isSplit && app.viewMode !== "kde"
                    currentPath: app.currentPath
                    viewMode: app.viewMode === "kde" ? "list" : app.viewMode
                    isSplit: app.isSplit
                    showDetails: app.showDetails
                    sortField: app.sortField
                    sortDirection: app.sortDirection
                    groupByType: app.groupByType
                    onNavigateRequested: function(p) {
                        app.loadFolder(p);
                    }
                    onViewModeChanged: {
                        if (app.viewMode !== "kde") {
                            app.viewMode = toolbar.viewMode;
                        }
                    }
                    onSortMenuRequested: function(x, y) {
                        sortMenu.show(x, y);
                    }
                    onToggleGroupRequested: {
                        app.groupByType = !app.groupByType;
                        app.filterAndDisplayEntries();
                    }
                    onToggleSplitRequested: {
                        app.isSplit = !app.isSplit;
                        if (app.isSplit && app.rightEntries.length === 0) {
                            app.rightPath = app.currentPath;
                            app.loadRightFolder(app.rightPath);
                        }
                    }
                    onToggleDetailsRequested: {
                        app.showDetails = !app.showDetails;
                    }
                }

                // Filtros de Busca com Chips (visível quando pesquisando)
                SearchFilterBar {
                    Layout.fillWidth: true
                    visible: app.isSearching
                    activeCategory: app.activeCategoryFilter
                    searchScope: app.searchScope
                    counts: app.categoryCounts
                    onCategoryChanged: function(cat) {
                        app.activeCategoryFilter = cat;
                        app.filterAndDisplayEntries();
                    }
                    onScopeChanged: function(sc) {
                        app.searchScope = sc;
                        app.searchFiles(app.activeSearchQuery);
                    }
                }

                // Visualização Dedicada do Dispositivo KDE Connect (Frame 425)
                KdeDeviceView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: app.viewMode === "kde"
                    device: app.activeKdeDevice
                    onActionRequested: function(action, devId) {
                        if (action === "ping") {
                            actionProc.command = [app.backendBin, "--kde-ping", devId];
                        } else if (action === "ring") {
                            actionProc.command = [app.backendBin, "--kde-ring", devId];
                        } else if (action === "clipboard") {
                            actionProc.command = [app.backendBin, "--kde-clipboard", devId];
                        } else if (action === "mount") {
                            actionProc.command = [app.backendBin, "--kde-mount", devId];
                        }
                        actionProc.running = true;
                    }
                    onFolderOpened: function(fPath) {
                        app.viewMode = "list";
                        app.loadFolder(fPath);
                    }
                }

                // Viewport de Arquivos em Modo Normal (Aba única)
                FileList {
                    id: fileList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !app.isSplit && app.viewMode !== "kde"
                    entries: app.currentEntries
                    selectedItem: app.selectedItem
                    selectedPaths: app.selectedPaths
                    viewMode: app.viewMode
                    sortField: app.sortField
                    sortDirection: app.sortDirection
                    groupByType: app.groupByType
                    onSortHeaderClicked: function(field) {
                        if (app.sortField === field) {
                            app.sortDirection = app.sortDirection === "asc" ? "desc" : "asc";
                        } else {
                            app.sortField = field;
                            app.sortDirection = "asc";
                        }
                        app.filterAndDisplayEntries();
                    }
                    onItemClicked: function(item, modifiers) {
                        app.clickItem("left", item, modifiers);
                    }
                    onBackgroundClicked: app.clearSelection("left")
                    onItemActivated: function(item) {
                        app.openItem(item);
                    }
                    onContextMenuRequested: function(item, x, y) {
                        contextMenu.show(item, x, y, app.devicesList);
                    }
                }

                // Viewport de Split View em 2 Abas/Painéis com Toolbar dedicada e Redimensionamento (Frame 2414 / 2574)
                Item {
                    id: splitContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: app.isSplit && app.viewMode !== "kde"

                    // Painel A (Nó 2575: Pane A)
                    Item {
                        id: paneA
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(160, Math.min(parent.width - 169, (parent.width - 9) * app.splitRatio))

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Toolbar do Painel A (Nó 2499: 585x52)
                            Toolbar {
                                id: paneAToolbar
                                Layout.fillWidth: true
                                height: 52
                                isCompact: true
                                isActivePane: app.activePane === "left"
                                currentPath: app.currentPath
                                viewMode: app.viewMode === "kde" ? "list" : app.viewMode
                                onNavigateRequested: function(p) {
                                    app.activePane = "left";
                                    app.loadFolder(p);
                                }
                                onViewModeChanged: {
                                    if (app.viewMode !== "kde") {
                                        app.viewMode = viewMode;
                                    }
                                }
                            }

                            // Lista de arquivos do Painel A (Nó 2509)
                            FileList {
                                id: splitFileListA
                                showWatermark: false
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                entries: app.currentEntries
                                selectedItem: app.selectedItem
                                selectedPaths: app.selectedPaths
                                viewMode: app.viewMode
                                sortField: app.sortField
                                sortDirection: app.sortDirection
                                groupByType: app.groupByType
                                onSortHeaderClicked: function(field) {
                                    if (app.sortField === field) {
                                        app.sortDirection = app.sortDirection === "asc" ? "desc" : "asc";
                                    } else {
                                        app.sortField = field;
                                        app.sortDirection = "asc";
                                    }
                                    app.filterAndDisplayEntries();
                                }
                                onItemClicked: function(item, modifiers) {
                                    app.clickItem("left", item, modifiers);
                                }
                                onBackgroundClicked: {
                                    app.activePane = "left";
                                    app.clearSelection("left");
                                }
                                onItemActivated: function(item) {
                                    app.activePane = "left";
                                    app.openItem(item);
                                }
                                onContextMenuRequested: function(item, x, y) {
                                    app.activePane = "left";
                                    contextMenu.show(item, x, y, app.devicesList);
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            propagateComposedEvents: true
                            onPressed: function(mouse) {
                                app.activePane = "left";
                                mouse.accepted = false;
                            }
                        }
                    }

                    // Divisor e Alça de Redimensionamento (Nós 2646 e 2647)
                    Item {
                        id: splitterItem
                        anchors.left: paneA.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 9
                        z: 10

                        // Linha vertical de 1px (Nó 2646: Divisor)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 1
                            height: parent.height
                            color: Qt.rgba(KappaTheme.sun.r, KappaTheme.sun.g, KappaTheme.sun.b, 0.35)
                        }

                        // Alça Divisora (Nó 2647: Alca divisor - 9x40)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 9
                            height: 40
                            radius: app.systemRadius
                            color: KappaTheme.paperLift
                            border.width: 1
                            border.color: KappaTheme.sun

                            Column {
                                anchors.centerIn: parent
                                spacing: 3

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        width: 3
                                        height: 3
                                        color: KappaTheme.sun
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SplitHCursor
                            hoverEnabled: true
                            onPositionChanged: function(mouse) {
                                if (pressed) {
                                    var mapped = mapToItem(splitContainer, mouse.x, mouse.y);
                                    var ratio = mapped.x / splitContainer.width;
                                    app.splitRatio = Math.max(0.15, Math.min(0.85, ratio));
                                }
                            }
                        }
                    }

                    // Painel B (Nó 2576: Pane B)
                    Item {
                        id: paneB
                        anchors.left: splitterItem.right
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Toolbar do Painel B (Nó 2577: 585x52)
                            Toolbar {
                                id: paneBToolbar
                                Layout.fillWidth: true
                                height: 52
                                isCompact: true
                                isActivePane: app.activePane === "right"
                                currentPath: app.rightPath
                                showCloseSplit: true
                                onCloseSplitRequested: {
                                    app.isSplit = false;
                                }
                                viewMode: app.viewMode === "kde" ? "list" : app.viewMode
                                onNavigateRequested: function(p) {
                                    app.activePane = "right";
                                    app.loadRightFolder(p);
                                }
                                onViewModeChanged: {
                                    if (app.viewMode !== "kde") {
                                        app.viewMode = viewMode;
                                    }
                                }
                            }

                            // Lista de arquivos do Painel B (Nó 2587)
                            FileList {
                                id: splitFileListB
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                entries: app.rightEntries
                                selectedItem: app.rightSelectedItem
                                selectedPaths: app.rightSelectedPaths
                                viewMode: app.viewMode
                                sortField: app.sortField
                                sortDirection: app.sortDirection
                                groupByType: app.groupByType
                                onSortHeaderClicked: function(field) {
                                    if (app.sortField === field) {
                                        app.sortDirection = app.sortDirection === "asc" ? "desc" : "asc";
                                    } else {
                                        app.sortField = field;
                                        app.sortDirection = "asc";
                                    }
                                    app.filterAndDisplayEntries();
                                }
                                onItemClicked: function(item, modifiers) {
                                    app.clickItem("right", item, modifiers);
                                }
                                onBackgroundClicked: {
                                    app.activePane = "right";
                                    app.clearSelection("right");
                                }
                                onItemActivated: function(item) {
                                    app.activePane = "right";
                                    if (item.is_dir) {
                                        app.loadRightFolder(item.path);
                                    } else {
                                        app.openItem(item);
                                    }
                                }
                                onContextMenuRequested: function(item, x, y) {
                                    app.activePane = "right";
                                    contextMenu.show(item, x, y, app.devicesList);
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            propagateComposedEvents: true
                            onPressed: function(mouse) {
                                app.activePane = "right";
                                mouse.accepted = false;
                            }
                        }
                    }
                }
            }

            // Painel de Detalhes com Animação de Slide Suave (Frame 155 - 340px)
            DetailsPanel {
                id: detailsDrawer
                Layout.fillHeight: true
                Layout.preferredWidth: app.showDetails ? 340 : 0
                visible: Layout.preferredWidth > 0
                fileItem: app.activeSelectedItem || (app.currentEntries.length > 0 ? app.currentEntries[0] : null)
                isOpen: app.showDetails
                onCloseRequested: {
                    app.showDetails = false;
                }
                onOpenRequested: function(item) {
                    app.openItem(item);
                }
                onSetWallpaperRequested: function(wallPath) {
                    actionProc.command = ["swww", "img", wallPath];
                    actionProc.running = true;
                }

                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutExpo
                    }
                }
            }
        }

        // Barra de Status (Statusbar com "Tema: segue o wallpaper")
        Statusbar {
            Layout.fillWidth: true
            totalItems: app.viewMode === "kde" ? 1 : app.currentEntries.length
            selectedItem: app.activeSelectedItem
            selectedCount: app.activeSelectedCount
            transferState: app.transferState
            transferFraction: app.transferFraction
            transferMode: app.transferMode
            onThemeClicked: app.openAppearance()
        }
    }

    // Menu Ordenar Flutuante (Frame 2866 do Figcraft - 252x256)
    SortMenu {
        id: sortMenu
        z: 101
        anchors.fill: parent
        sortField: app.sortField
        sortDirection: app.sortDirection
        groupByType: app.groupByType
        onSortFieldSelected: function(field) {
            app.sortField = field;
            app.filterAndDisplayEntries();
        }
        onSortDirectionSelected: function(dir) {
            app.sortDirection = dir;
            app.filterAndDisplayEntries();
        }
        onToggleGroupByType: {
            app.groupByType = !app.groupByType;
            app.filterAndDisplayEntries();
        }
    }

    // Menu de Contexto Flutuante Pixel-Perfect
    ContextMenu {
        id: contextMenu
        z: 100
        anchors.fill: parent
        onOpenTriggered: function(item) {
            if (item) app.openItem(item);
        }
        onOpenNewTabTriggered: function(item) {
            var targetPath = (item && item.is_dir) ? item.path : ((app.isSplit && app.activePane === "right") ? app.rightPath : app.currentPath);
            app.openNewTab(targetPath);
        }
        onOpenTerminalTriggered: function(item) {
            var target = (item && item.path) ? item.path : ((app.isSplit && app.activePane === "right") ? app.rightPath : app.currentPath);
            app.openTerminalAt(target);
        }
        onPlayRyotunesTriggered: function(item) {
            if (item) app.openItem(item);
        }
        onCopyTriggered: function(item) {
            app.copyItem(item);
        }
        onCutTriggered: function(item) {
            app.cutItem(item);
        }
        onPasteTriggered: function() {
            app.pasteItem();
        }
        onNewFolderTriggered: function() {
            app.createNewFolder();
        }
        onReloadTriggered: function() {
            if (app.isSplit && app.activePane === "right") {
                app.loadRightFolder(app.rightPath);
            } else {
                app.loadFolder(app.currentPath);
            }
        }
        onSelectAllTriggered: function() {
            app.selectAll();
        }
        onCopyPathTriggered: function(item) {
            var p = (item && item.path) ? item.path : ((app.isSplit && app.activePane === "right") ? app.rightPath : app.currentPath);
            Quickshell.clipboardText = p;
        }
        onTrashTriggered: function(item) {
            app.requestDelete(item, false);
        }
        onRenameTriggered: function(item) {
            app.startRename(item);
        }
        onSendKdeTriggered: function(item, devId) {
            if (item && item.path) {
                actionProc.command = [app.backendBin, "--kde-share", devId, item.path];
                actionProc.running = true;
            }
        }
        onPropertiesTriggered: function(item) {
            if (item) {
                app.clickItem((app.isSplit && app.activePane === "right") ? "right" : "left", item, 0);
            }
            app.showDetails = true;
        }
    }

    // Cartão de progresso de cópia/movimentação
    TransferCard {
        id: transferCard
        z: 90
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 36 + 16
        state: app.transferState
        mode: app.transferMode
        name: app.transferName
        destDir: app.transferDestDir
        index: app.transferIndex
        items: app.transferItems
        done: app.transferDone
        total: app.transferTotal
        speed: app.transferSpeed
        seconds: app.transferSeconds
        errorText: app.errorMessage
        onCancelRequested: app.cancelTransfer()
        onPauseToggled: app.togglePauseTransfer()
        onDismissed: app.transferState = "idle"
        onRevealRequested: {
            app.transferState = "idle";
            app.refreshPanes();
        }
    }

    // Diálogo de Aparência (Frames "Kappa / Aparência")
    AppearanceDialog {
        id: appearanceDialog
        z: 130
        anchors.fill: parent
        onClosed: {
            app.showAppearance = false;
            app.forceActiveFocus();
        }
    }

    // Modal de confirmação de exclusão (Frames "Confirmar exclusão")
    DeleteModal {
        id: deleteModal
        z: 120
        anchors.fill: parent
        onConfirmed: app.confirmDelete()
        onCancelled: app.cancelDelete()
    }

    // Modal de renomeação (F2 / nova pasta)
    RenameModal {
        id: renameModal
        z: 110
        anchors.fill: parent
        active: app.showRenameModal
        onSubmitted: function(newName) { app.submitRename(newName); }
        onCancelled: {
            app.showRenameModal = false;
            app.renameTargetItem = null;
            app.forceActiveFocus();
        }
    }
}
