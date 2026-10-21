import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    width: 340
    color: KappaTheme.paperLift
    clip: true

    property var fileItem: null
    property bool isOpen: false
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    property var paletteColors: []

    // Quantiza em 4 bits por canal, conta e escolhe as mais frequentes que se distinguem entre si
    function dominantColors(data, count) {
        var buckets = {};
        for (var i = 0; i < data.length; i += 4) {
            if (data[i + 3] < 128) continue;
            var key = ((data[i] >> 4) << 8) | ((data[i + 1] >> 4) << 4) | (data[i + 2] >> 4);
            var b = buckets[key];
            if (b) { b.n++; b.r += data[i]; b.g += data[i + 1]; b.b += data[i + 2]; }
            else buckets[key] = { n: 1, r: data[i], g: data[i + 1], b: data[i + 2] };
        }
        var list = [];
        for (var k in buckets) {
            var e = buckets[k];
            list.push({ n: e.n, r: Math.round(e.r / e.n), g: Math.round(e.g / e.n), b: Math.round(e.b / e.n) });
        }
        list.sort(function(a, b) { return b.n - a.n; });
        var out = [];
        for (var j = 0; j < list.length && out.length < count; j++) {
            var c = list[j], far = true;
            for (var m = 0; m < out.length; m++) {
                var d = Math.abs(c.r - out[m].r) + Math.abs(c.g - out[m].g) + Math.abs(c.b - out[m].b);
                if (d < 60) { far = false; break; }
            }
            if (far) out.push(c);
        }
        return out.map(function(c) {
            return "#" + [c.r, c.g, c.b].map(function(v) { return (v < 16 ? "0" : "") + v.toString(16); }).join("");
        });
    }

    signal openRequested(var item)
    signal setWallpaperRequested(string path)
    signal closeRequested()
    signal copyRequested(string text, string message)

    // Borda vertical esquerda divisória (Nó 560)
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: KappaTheme.line
    }

    // Lê pixels de uma cópia 48x48 da prévia; nada é gravado nem enviado
    Canvas {
        id: paletteCanvas
        width: 48
        height: 48
        opacity: 0
        x: -100
        property string src: previewImg.status === Image.Ready ? previewImg.source.toString() : ""
        onSrcChanged: {
            root.paletteColors = [];
            if (src !== "") loadImage(src);
        }
        onImageLoaded: requestPaint()
        onPaint: {
            if (src === "" || !isImageLoaded(src)) return;
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, 48, 48);
            ctx.drawImage(src, 0, 0, 48, 48);
            root.paletteColors = root.dominantColors(ctx.getImageData(0, 0, 48, 48).data, 6);
            unloadImage(src);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // 1. Cabeçalho da Seção PREVIEW (Nó 562: 292x20)
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
                text: root.isPt ? "PREVIEW_" : "PREVIEW_"
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

            // Botão fechar painel
            Text {
                textFormat: Text.PlainText
                text: "󰅖"
                font.family: Tokens.mono
                font.pixelSize: 12
                color: KappaTheme.inkDim
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        // 2. Card de Preview Grande (Nó 567: 292x190)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 190
            radius: root.effectiveRadius
            color: KappaTheme.paper
            border.width: 1
            border.color: KappaTheme.line
            clip: true

            // Imagem real se for foto (exceto .svg que causa erro de decodificação)
            Image {
                id: previewImg
                anchors.fill: parent
                source: KappaSafe.previewUrl(root.fileItem)
                sourceSize: Qt.size(584, 380)
                cache: false
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: root.fileItem && root.fileItem.kind === "image" && status === Image.Ready
            }

            // Fallback visual se for pasta ou outro arquivo
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8
                visible: !previewImg.visible

                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        if (!root.fileItem) return "󰈔";
                        if (root.fileItem.is_dir) return "󰉋";
                        switch(root.fileItem.icon_name) {
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
                    font.pixelSize: 56
                    color: (root.fileItem && root.fileItem.is_dir) ? KappaTheme.sun : KappaTheme.inkDim
                }
            }

            // Ticks técnicos de blueprint nos 4 cantos (Nó 570)
            Item {
                anchors.fill: parent
                Rectangle { x: 4; y: 4; width: 6; height: 1; color: KappaTheme.sun }
                Rectangle { x: 4; y: 4; width: 1; height: 6; color: KappaTheme.sun }
                Rectangle { x: parent.width - 10; y: 4; width: 6; height: 1; color: KappaTheme.sun }
                Rectangle { x: parent.width - 5; y: 4; width: 1; height: 6; color: KappaTheme.sun }
                Rectangle { x: 4; y: parent.height - 5; width: 6; height: 1; color: KappaTheme.sun }
                Rectangle { x: 4; y: parent.height - 10; width: 1; height: 6; color: KappaTheme.sun }
                Rectangle { x: parent.width - 10; y: parent.height - 5; width: 6; height: 1; color: KappaTheme.sun }
                Rectangle { x: parent.width - 5; y: parent.height - 10; width: 1; height: 6; color: KappaTheme.sun }
            }

            // Plaqueta de Dimensão / Tamanho no canto inferior direito (Nó 571)
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                implicitWidth: dimText.implicitWidth + 12
                implicitHeight: 20
                color: Qt.rgba(0, 0, 0, 0.75)
                border.width: 1
                border.color: KappaTheme.line

                Text {
                    textFormat: Text.PlainText
                    id: dimText
                    anchors.centerIn: parent
                    text: root.fileItem ? (root.fileItem.is_dir ? (root.isPt ? "Pasta" : "Folder") : root.fileItem.size_formatted) : ""
                    font.family: Tokens.mono
                    font.pixelSize: 10
                    color: KappaTheme.paper
                }
            }
        }

        // 3. Título e Subtítulo (Nós 573 e 574)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.fileItem ? root.fileItem.name : ""
                font.family: Tokens.display
                font.pixelSize: 18
                font.bold: true
                color: KappaTheme.ink
                elide: Text.ElideRight
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: {
                    if (!root.fileItem) return "";
                    var k = root.fileItem.kind;
                    var label = k;
                    if (root.fileItem.is_dir) label = root.isPt ? "Diretório" : "Directory";
                    else if (k === "image") label = root.isPt ? "Imagem" : "Image";
                    else if (k === "document") label = root.isPt ? "Documento" : "Document";
                    else if (k === "audio") label = root.isPt ? "Áudio" : "Audio";
                    else if (k === "code") label = root.isPt ? "Código-fonte" : "Source Code";
                    return label + (root.fileItem.is_dir ? "" : (" · " + root.fileItem.size_formatted));
                }
                font.family: Tokens.ui
                font.pixelSize: 12
                color: KappaTheme.inkDim
                elide: Text.ElideRight
            }
        }

        // 4. Seção DETALHES (Nó 575: 292x20)
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
                text: root.isPt ? "DETALHES_" : "DETAILS_"
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

        // Tabela de Metadados Chave-Valor (Nós 580 a 597)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            // TIPO
            RowLayout {
                Layout.fillWidth: true
                height: 22
                Text { textFormat: Text.PlainText; text: root.isPt ? "TIPO" : "TYPE"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkFaint; Layout.preferredWidth: 90 }
                Text { textFormat: Text.PlainText; text: root.fileItem ? root.fileItem.mime_type : "—"; font.family: Tokens.ui; font.pixelSize: 12; color: KappaTheme.ink; Layout.fillWidth: true; elide: Text.ElideRight }
            }

            // MODIFICADO
            RowLayout {
                Layout.fillWidth: true
                height: 22
                Text { textFormat: Text.PlainText; text: root.isPt ? "MODIFICADO" : "MODIFIED"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkFaint; Layout.preferredWidth: 90 }
                Text { textFormat: Text.PlainText; text: root.fileItem ? root.fileItem.modified_formatted : "—"; font.family: Tokens.ui; font.pixelSize: 12; color: KappaTheme.ink; Layout.fillWidth: true; elide: Text.ElideRight }
            }

            // TAMANHO
            RowLayout {
                Layout.fillWidth: true
                height: 22
                Text { textFormat: Text.PlainText; text: root.isPt ? "TAMANHO" : "SIZE"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkFaint; Layout.preferredWidth: 90 }
                Text { textFormat: Text.PlainText; text: root.fileItem ? root.fileItem.size_formatted : "—"; font.family: Tokens.ui; font.pixelSize: 12; color: KappaTheme.ink; Layout.fillWidth: true }
            }

            // LOCAL
            RowLayout {
                Layout.fillWidth: true
                height: 22
                Text { textFormat: Text.PlainText; text: root.isPt ? "LOCAL" : "LOCATION"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkFaint; Layout.preferredWidth: 90 }
                Text {
                    textFormat: Text.PlainText
                    text: root.fileItem ? root.fileItem.path : "—"
                    font.family: Tokens.ui; font.pixelSize: 12
                    color: pathMouse.containsMouse ? KappaTheme.sun : KappaTheme.ink
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    MouseArea {
                        id: pathMouse
                        anchors.fill: parent
                        enabled: root.fileItem !== null
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.copyRequested(root.fileItem.path, root.isPt ? "Localização copiada" : "Location copied")
                    }
                }
            }
        }

        // 5. Seção PALETA (Nó 598: se for imagem)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.fileItem && root.fileItem.kind === "image" && root.paletteColors.length > 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                spacing: 8

                Text { textFormat: Text.PlainText; text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.sun }
                Text { textFormat: Text.PlainText; text: root.isPt ? "PALETA_" : "PALETTE_"; font.family: Tokens.ui; font.pixelSize: 11; font.bold: true; color: KappaTheme.inkDim }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: KappaTheme.line
                }
            }

            // Amostras: cores dominantes da própria prévia (já limitada por KappaSafe.previewUrl)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.paletteColors
                    delegate: Rectangle {
                        required property string modelData
                        Layout.fillWidth: true
                        height: 26
                        radius: root.effectiveRadius
                        color: modelData
                        border.width: 1
                        border.color: swatchMouse.containsMouse ? KappaTheme.sun : KappaTheme.line
                        MouseArea {
                            id: swatchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copyRequested(modelData.toUpperCase(), (root.isPt ? "Cor copiada: " : "Color copied: ") + modelData.toUpperCase())
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // 6. Barra de Ações (Nó 611: 292x32)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Botão Abrir
            Rectangle {
                implicitWidth: 70
                implicitHeight: 32
                radius: root.effectiveRadius
                color: openBtnMouse.containsMouse ? KappaTheme.tint16 : KappaTheme.paper
                border.width: 1
                border.color: KappaTheme.lineStrong

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.isPt ? "Abrir" : "Open"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    font.bold: true
                    color: KappaTheme.ink
                }

                MouseArea {
                    id: openBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.fileItem) root.openRequested(root.fileItem);
                    }
                }
            }

            // Botão Definir como Wallpaper (se for imagem)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: root.effectiveRadius
                visible: root.fileItem && root.fileItem.kind === "image"
                color: wallBtnMouse.containsMouse ? KappaTheme.sun : KappaTheme.paper
                border.width: 1
                border.color: KappaTheme.sun

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.isPt ? "Definir como wallpaper" : "Set as wallpaper"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    font.bold: true
                    color: wallBtnMouse.containsMouse ? KappaTheme.paper : KappaTheme.sun
                }

                MouseArea {
                    id: wallBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.fileItem) root.setWallpaperRequested(root.fileItem.path);
                    }
                }
            }
        }
    }
}
