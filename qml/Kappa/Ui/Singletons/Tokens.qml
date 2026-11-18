pragma Singleton

import QtQuick

// Tokens visuais do Kappa. Funciona em qualquer desktop: usa a paleta própria
// (escura ou clara, conforme o tema do sistema). Se o módulo Ryoku.Ui.Singletons
// estiver instalado, uma ponte opcional passa a seguir o tema do Ryoku.
Item {
    id: t
    visible: false

    // Ponte opcional: só existe se o módulo do Ryoku puder ser importado
    property var ryoku: null

    Component.onCompleted: {
        try {
            t.ryoku = Qt.createQmlObject(
                'import QtQuick\n' +
                'import Ryoku.Ui.Singletons as R\n' +
                'QtObject {\n' +
                '  readonly property color paper: R.Tokens.paper\n' +
                '  readonly property color paperLift: R.Tokens.paperLift\n' +
                '  readonly property color ink: R.Tokens.ink\n' +
                '  readonly property color inkDim: R.Tokens.inkDim\n' +
                '  readonly property color inkFaint: R.Tokens.inkFaint\n' +
                '  readonly property color inkOnBone: R.Tokens.inkOnBone\n' +
                '  readonly property color sun: R.Tokens.sun\n' +
                '  readonly property color sunDeep: R.Tokens.sunDeep\n' +
                '  readonly property color line: R.Tokens.line\n' +
                '  readonly property color lineSoft: R.Tokens.lineSoft\n' +
                '  readonly property color lineStrong: R.Tokens.lineStrong\n' +
                '  readonly property color tint5: R.Tokens.tint5\n' +
                '  readonly property color tint10: R.Tokens.tint10\n' +
                '  readonly property color tint16: R.Tokens.tint16\n' +
                '  readonly property bool light: R.Tokens.light\n' +
                '  readonly property int radius: R.Tokens.radius\n' +
                '  readonly property string ui: R.Tokens.ui\n' +
                '  readonly property string mono: R.Tokens.mono\n' +
                '  function px(n) { return R.Tokens.px(n); }\n' +
                '}', t, "KappaRyokuBridge");
        } catch (e) {
            t.ryoku = null;
        }
    }

    readonly property bool hasRyoku: t.ryoku !== null

    // Tema do sistema (Qt 6.5+); sem informação, assume escuro
    readonly property bool systemLight: Qt.styleHints.colorScheme === Qt.ColorScheme.Light

    readonly property bool light: hasRyoku ? ryoku.light : systemLight

    // ── Paleta própria ───────────────────────────────────────────────────
    readonly property color ownPaper: light ? "#f4f1ec" : "#0c0c0d"
    readonly property color ownPaperLift: light ? "#e9e5de" : "#161617"
    readonly property color ownInk: light ? "#1b1a19" : "#cdc4ba"
    readonly property color ownInkDim: light ? "#55514c" : "#b0a9a0"
    readonly property color ownSun: "#e2342a"

    readonly property color paper: hasRyoku ? ryoku.paper : ownPaper
    readonly property color paperLift: hasRyoku ? ryoku.paperLift : ownPaperLift
    readonly property color ink: hasRyoku ? ryoku.ink : ownInk
    readonly property color inkDim: hasRyoku ? ryoku.inkDim : ownInkDim
    readonly property color inkFaint: hasRyoku ? ryoku.inkFaint : Qt.rgba(ownInkDim.r, ownInkDim.g, ownInkDim.b, 0.68)
    readonly property color inkOnBone: hasRyoku ? ryoku.inkOnBone : (light ? "#f4f1ec" : "#000000")
    readonly property color sun: hasRyoku ? ryoku.sun : ownSun
    readonly property color sunDeep: hasRyoku ? ryoku.sunDeep : Qt.darker(ownSun, 1.3)

    readonly property color line: hasRyoku ? ryoku.line : Qt.rgba(ownInk.r, ownInk.g, ownInk.b, 0.26)
    readonly property color lineSoft: hasRyoku ? ryoku.lineSoft : Qt.rgba(ownInk.r, ownInk.g, ownInk.b, 0.13)
    readonly property color lineStrong: hasRyoku ? ryoku.lineStrong : Qt.rgba(ownInk.r, ownInk.g, ownInk.b, 0.42)
    readonly property color tint5: hasRyoku ? ryoku.tint5 : Qt.rgba(ownInk.r, ownInk.g, ownInk.b, 0.05)
    readonly property color tint10: hasRyoku ? ryoku.tint10 : Qt.rgba(ownInk.r, ownInk.g, ownInk.b, 0.10)
    readonly property color tint16: hasRyoku ? ryoku.tint16 : Qt.rgba(ownInk.r, ownInk.g, ownInk.b, 0.16)

    // ── Fontes ───────────────────────────────────────────────────────────
    // `font.family` do QML não aceita lista com vírgulas: escolhemos a primeira
    // família realmente instalada. Os ícones são glifos Nerd Font, então qualquer
    // "Nerd Font" instalada serve se as preferidas faltarem.
    readonly property var installedFonts: Qt.fontFamilies()

    function firstInstalled(candidates, fallback) {
        var have = t.installedFonts;
        for (var i = 0; i < candidates.length; i++) {
            if (have.indexOf(candidates[i]) !== -1) return candidates[i];
        }
        return fallback;
    }

    function anyNerd() {
        var have = t.installedFonts;
        for (var i = 0; i < have.length; i++) {
            if (have[i].indexOf("Nerd Font") !== -1 && have[i].indexOf("Propo") === -1) return have[i];
        }
        return "monospace";
    }

    readonly property string display: firstInstalled(["Fraunces", "Fraunces 72pt"], "serif")
    readonly property string ui: hasRyoku ? ryoku.ui : firstInstalled(["Space Grotesk"], "sans-serif")
    readonly property string mono: hasRyoku ? ryoku.mono
        : firstInstalled(["SpaceMono Nerd Font", "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono"], anyNerd())
    readonly property string jp: firstInstalled(["Noto Sans CJK JP"], "sans-serif")

    // ── Geometria ────────────────────────────────────────────────────────
    readonly property int radius: hasRyoku ? ryoku.radius : 6
    function px(n) { return hasRyoku ? ryoku.px(n) : Math.round(n); }
}
