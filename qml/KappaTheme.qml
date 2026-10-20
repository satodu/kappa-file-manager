pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

// Camada de cor própria do Kappa: por padrão segue o tema do Ryoku (Tokens),
// mas pode ser fixada com um esquema Material gerado pelo matugen.
// Config persistida em ~/.config/kappa/theme.json.
Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/kappa"
    readonly property string configPath: root.configDir + "/theme.json"

    // Configuração aplicada
    property string mode: "follow"            // "follow" | "fixed"
    property string scheme: "scheme-tonal-spot"
    property string source: "wallpaper"       // "wallpaper" (cor primária do Ryoku) ou "#rrggbb"
    property string appearance: "dark"        // "dark" | "light" | "system"
    property var roles: ({})                  // papéis Material gerados (chaves snake_case)

    // Pré-visualização do diálogo de Aparência
    property var previewRoles: ({})

    readonly property var schemeNames: [
        { id: "scheme-tonal-spot", label: "Tonal Spot" },
        { id: "scheme-fidelity", label: "Fidelity" },
        { id: "scheme-expressive", label: "Expressive" },
        { id: "scheme-vibrant", label: "Vibrant" },
        { id: "scheme-neutral", label: "Neutral" },
        { id: "scheme-monochrome", label: "Monochrome" },
        { id: "scheme-rainbow", label: "Rainbow" },
        { id: "scheme-fruit-salad", label: "Fruit Salad" },
        { id: "scheme-content", label: "Content" }
    ]

    readonly property bool fixed: root.mode === "fixed"

    function usable(v) { return typeof v === "string" && v.length > 0; }

    function validScheme(v) {
        for (var i = 0; i < root.schemeNames.length; i++) {
            if (root.schemeNames[i].id === v) return true;
        }
        return false;
    }

    function validSource(v) {
        return v === "wallpaper" || (typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v));
    }

    function pick(key, base) {
        if (root.fixed && root.usable(root.roles[key])) return root.roles[key];
        return base;
    }

    // ── Cores usadas pelo Kappa (mesmos nomes de Tokens) ─────────────────
    readonly property color paper: pick("surface", Tokens.paper)
    readonly property color paperLift: pick("surface_container_low", Tokens.paperLift)
    readonly property color ink: pick("on_surface", Tokens.ink)
    readonly property color inkDim: pick("on_surface_variant", Tokens.inkDim)
    readonly property color inkFaint: root.fixed ? Qt.rgba(inkDim.r, inkDim.g, inkDim.b, 0.68) : Tokens.inkFaint
    readonly property color inkOnBone: pick("inverse_on_surface", Tokens.inkOnBone)
    readonly property color sun: pick("primary", Tokens.sun)

    readonly property color line: root.fixed ? Qt.rgba(ink.r, ink.g, ink.b, 0.26) : Tokens.line
    readonly property color lineSoft: root.fixed ? Qt.rgba(ink.r, ink.g, ink.b, 0.13) : Tokens.lineSoft
    readonly property color lineStrong: root.fixed ? Qt.rgba(ink.r, ink.g, ink.b, 0.42) : Tokens.lineStrong
    readonly property color tint5: root.fixed ? Qt.rgba(ink.r, ink.g, ink.b, 0.05) : Tokens.tint5
    readonly property color tint10: root.fixed ? Qt.rgba(ink.r, ink.g, ink.b, 0.10) : Tokens.tint10
    readonly property color tint16: root.fixed ? Qt.rgba(ink.r, ink.g, ink.b, 0.16) : Tokens.tint16

    // Rótulo curto para a statusbar
    readonly property string summary: {
        if (!root.fixed) return "follow";
        for (var i = 0; i < root.schemeNames.length; i++) {
            if (root.schemeNames[i].id === root.scheme) return root.schemeNames[i].label;
        }
        return root.scheme;
    }

    // ── Persistência ─────────────────────────────────────────────────────
    FileView {
        id: configFile
        path: root.configPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: { configFile.reload(); root.loadFromFile(); }
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.configDir]
    }

    function loadFromFile() {
        try {
            var txt = configFile.text();
            if (!txt || txt.length === 0) return;
            var cfg = JSON.parse(txt);
            root.mode = cfg.mode === "fixed" ? "fixed" : "follow";
            // Valores vão para a linha de comando do matugen: aceita só esquemas conhecidos e cores #rrggbb
            if (root.validScheme(cfg.scheme)) root.scheme = cfg.scheme;
            if (root.validSource(cfg.source)) root.source = cfg.source;
            if (cfg.appearance === "dark" || cfg.appearance === "light" || cfg.appearance === "system") root.appearance = cfg.appearance;
        } catch (e) {
            console.warn("Kappa: theme.json inválido:", e);
        }
        if (root.fixed) root.generate(root.currentConfig(), true);
    }

    function currentConfig() {
        return { mode: root.mode, scheme: root.scheme, source: root.source, appearance: root.appearance };
    }

    function seedFor(cfg) {
        if (cfg.source && cfg.source.charAt(0) === "#") return cfg.source;
        return Tokens.sun.toString();
    }

    function modeFor(cfg) {
        if (cfg.appearance === "light") return "light";
        if (cfg.appearance === "dark") return "dark";
        return Tokens.light ? "light" : "dark";
    }

    // Gera os papéis Material via matugen. apply=true grava no estado aplicado; senão, na prévia.
    property bool generating: false
    property var pendingTarget: "roles"
    function generate(cfg, applied) {
        pendingTarget = applied ? "roles" : "previewRoles";
        genProc.pendingMode = modeFor(cfg);
        genProc.command = ["matugen", "color", "hex", seedFor(cfg), "-t", cfg.scheme, "-m", genProc.pendingMode, "--json", "hex", "--dry-run"];
        if (genProc.running) genProc.running = false;
        genProc.running = true;
    }

    Process {
        id: genProc
        property string pendingMode: "dark"
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    var out = {};
                    for (var k in data.colors) {
                        var entry = data.colors[k][genProc.pendingMode];
                        if (entry && entry.color) out[k] = entry.color;
                    }
                    root[root.pendingTarget] = out;
                } catch (e) {
                    console.warn("Kappa: falha ao gerar esquema:", e);
                }
            }
        }
    }

    function save() {
        mkdirProc.running = true;
        configFile.setText(JSON.stringify(root.currentConfig(), null, 2) + "\n");
    }

    // Aplica a configuração escolhida no diálogo
    function apply(cfg) {
        root.mode = cfg.mode === "fixed" ? "fixed" : "follow";
        if (root.validScheme(cfg.scheme)) root.scheme = cfg.scheme;
        if (root.validSource(cfg.source)) root.source = cfg.source;
        root.appearance = cfg.appearance;
        if (root.fixed) root.generate(cfg, true);
        root.save();
    }

    function restore() {
        apply({ mode: "follow", scheme: "scheme-tonal-spot", source: "wallpaper", appearance: "dark" });
    }

    Component.onCompleted: root.loadFromFile()
}
