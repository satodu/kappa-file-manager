import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    // Componente auxiliar para desenhar ícones monocromáticos usando texto/nerd font ou vetores simples
    component Glyph: Text {
        property string name: ""
        font.family: Tokens.mono
        font.pixelSize: 14
        color: KappaTheme.inkDim
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter

        text: {
            switch(name) {
                case "folder": return "󰉋"
                case "file": return "󰈔"
                case "doc": return "󰈙"
                case "img": return "󰋩"
                case "music": return "󰎆"
                case "video": return "󰕧"
                case "code": return "󰅩"
                case "archive": return "󰛫"
                case "home": return "󰋜"
                case "down": return "󰉍"
                case "drive": return "󰋊"
                case "search": return "󰍉"
                case "arrow-left": return "󰁍"
                case "arrow-right": return "󰁔"
                case "arrow-up": return "󰁝"
                case "refresh": return "󰑐"
                default: return "󰈔"
            }
        }
    }
}
