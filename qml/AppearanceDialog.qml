import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// Diálogo de Aparência (Frames "Kappa / Aparência (tema)" e "(fixo)")
Item {
    id: root
    visible: false
    focus: visible

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    // Rascunho (só vale após "Aplicar")
    property string dMode: "follow"
    property string dScheme: "scheme-tonal-spot"
    property string dSource: "wallpaper"
    property string dAppearance: "dark"

    readonly property bool dFixed: root.dMode === "fixed"
    readonly property var swatches: [
        { name: "Vermillion", hex: "#e2342a" },
        { name: "Água", hex: "#80d4d9" },
        { name: "Ouro", hex: "#d9a441" },
        { name: "Jade", hex: "#4fae7b" },
        { name: "Violeta", hex: "#8a6fd1" }
    ]

    signal closed()

    function draft() {
        return { mode: root.dMode, scheme: root.dScheme, source: root.dSource, appearance: root.dAppearance };
    }

    function open() {
        root.dMode = KappaTheme.mode;
        root.dScheme = KappaTheme.scheme;
        root.dSource = KappaTheme.source;
        root.dAppearance = KappaTheme.appearance;
        root.visible = true;
        root.forceActiveFocus();
        root.requestPreview();
    }

    function close() {
        root.visible = false;
        root.closed();
    }

    function requestPreview() { previewTimer.restart(); }

    Timer {
        id: previewTimer
        interval: 150
        onTriggered: if (root.dFixed) KappaTheme.generate(root.draft(), false)
    }

    onDModeChanged: requestPreview()
    onDSchemeChanged: requestPreview()
    onDSourceChanged: requestPreview()
    onDAppearanceChanged: requestPreview()

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.close();
            event.accepted = true;
        } else if (hexInput.activeFocus) {
            return;
        } else {
            event.accepted = true;
        }
    }

    function previewColor(role, fallback) {
        if (root.dFixed && KappaTheme.usable(KappaTheme.previewRoles[role])) return KappaTheme.previewRoles[role];
        return fallback;
    }

    // Scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    MultiEffect {
        source: dialog
        anchors.fill: dialog
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.65)
        shadowVerticalOffset: 14
        shadowBlur: 0.8
    }

    // Chip reutilizável
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool active: false
        property color swatch: "transparent"
        signal clicked()
        implicitHeight: 32
        implicitWidth: chipRow.implicitWidth + 24
        radius: root.effectiveRadius
        color: active ? Qt.rgba(Tokens.sun.r, Tokens.sun.g, Tokens.sun.b, 0.12) : (chipArea.containsMouse ? KappaTheme.tint10 : "transparent")
        border.width: 1
        border.color: active ? KappaTheme.sun : KappaTheme.line

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                visible: chip.swatch.a > 0
                width: 12; height: 12; radius: 6
                color: chip.swatch
            }
            Text {
                text: chip.label
                font.family: Tokens.ui
                font.pixelSize: 13
                font.bold: chip.active
                color: chip.active ? KappaTheme.sun : KappaTheme.inkDim
            }
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component SectionTitle: RowLayout {
        property string title: ""
        Layout.fillWidth: true
        spacing: 10
        Text { text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkFaint }
        Text {
            text: parent.title
            font.family: Tokens.ui
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 2.2
            color: KappaTheme.inkDim
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: KappaTheme.lineSoft }
    }

    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: 560
        height: content.implicitHeight + 48
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: KappaTheme.lineStrong

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: root.isPt ? "Aparência" : "Appearance"
                    font.family: Tokens.display
                    font.pixelSize: 22
                    color: KappaTheme.ink
                }
                Text {
                    text: "外観"
                    font.family: Tokens.jp
                    font.pixelSize: 12
                    color: KappaTheme.inkDim
                }
                Item { Layout.fillWidth: true }
                Text { text: "esc"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                Text {
                    text: "×"
                    font.pixelSize: 20
                    color: KappaTheme.inkDim
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                }
            }

            // ORIGEM
            SectionTitle { title: root.isPt ? "ORIGEM_" : "SOURCE_" }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Chip { label: root.isPt ? "Seguir o sistema" : "Follow system"; active: !root.dFixed; onClicked: root.dMode = "follow" }
                Chip { label: root.isPt ? "Fixo no Kappa" : "Fixed in Kappa"; active: root.dFixed; onClicked: root.dMode = "fixed" }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.dFixed
                      ? (root.isPt ? "Paleta própria do Kappa. O resto do desktop não muda." : "Kappa's own palette. The rest of the desktop is unchanged.")
                      : (root.isPt ? "Segue o tema do Ryoku: mudar o tema do sistema muda o Kappa." : "Follows the Ryoku theme: changing the system theme changes Kappa.")
                font.family: Tokens.ui
                font.pixelSize: 12
                color: KappaTheme.inkDim
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 20
                opacity: root.dFixed ? 1.0 : 0.35
                enabled: root.dFixed

                SectionTitle { title: root.isPt ? "ESQUEMA_" : "SCHEME_" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: KappaTheme.schemeNames
                        delegate: Chip {
                            required property var modelData
                            label: modelData.label
                            active: root.dScheme === modelData.id
                            onClicked: root.dScheme = modelData.id
                        }
                    }
                }

                SectionTitle { title: root.isPt ? "COR DE ORIGEM_" : "SEED COLOR_" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Chip { label: "Wallpaper"; active: root.dSource === "wallpaper"; onClicked: root.dSource = "wallpaper" }
                    Repeater {
                        model: root.swatches
                        delegate: Rectangle {
                            required property var modelData
                            width: 28; height: 28; radius: 14
                            color: modelData.hex
                            border.width: root.dSource.toLowerCase() === modelData.hex ? 2 : 1
                            border.color: root.dSource.toLowerCase() === modelData.hex ? KappaTheme.sun : KappaTheme.line
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.dSource = modelData.hex; hexInput.text = modelData.hex; }
                            }
                        }
                    }
                    Rectangle {
                        implicitWidth: 96
                        implicitHeight: 32
                        radius: root.effectiveRadius
                        color: "transparent"
                        border.width: 1
                        border.color: hexInput.activeFocus ? KappaTheme.sun : KappaTheme.line

                        TextInput {
                            id: hexInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Tokens.mono
                            font.pixelSize: 13
                            color: KappaTheme.inkDim
                            maximumLength: 7
                            selectByMouse: true
                            text: root.dSource.charAt(0) === "#" ? root.dSource : "#e2342a"
                            onTextEdited: {
                                if (/^#[0-9a-fA-F]{6}$/.test(text)) root.dSource = text.toLowerCase();
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                SectionTitle { title: root.isPt ? "MODO_" : "MODE_" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Chip { label: root.isPt ? "Escuro" : "Dark"; active: root.dAppearance === "dark"; onClicked: root.dAppearance = "dark" }
                    Chip { label: root.isPt ? "Claro" : "Light"; active: root.dAppearance === "light"; onClicked: root.dAppearance = "light" }
                    Chip { label: root.isPt ? "Seguir o sistema" : "System"; active: root.dAppearance === "system"; onClicked: root.dAppearance = "system" }
                }
            }

            // PRÉVIA
            SectionTitle { title: root.isPt ? "PRÉVIA_" : "PREVIEW_" }
            Rectangle {
                Layout.fillWidth: true
                height: 56
                color: "transparent"
                border.width: 1
                border.color: KappaTheme.line

                Row {
                    anchors.fill: parent
                    anchors.margins: 1
                    Repeater {
                        model: [
                            { role: "surface", fb: Tokens.paper },
                            { role: "surface_container_low", fb: Tokens.paperLift },
                            { role: "outline_variant", fb: Tokens.line },
                            { role: "on_surface", fb: Tokens.ink },
                            { role: "primary", fb: Tokens.sun },
                            { role: "tertiary", fb: Tokens.sunDeep }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width) / 6
                            height: parent.height
                            color: root.previewColor(modelData.role, modelData.fb)
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: KappaTheme.lineSoft }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "~/.config/kappa/theme.json"
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.inkDim
                }
                Item { Layout.fillWidth: true }
                Chip {
                    label: root.isPt ? "Restaurar" : "Restore"
                    onClicked: { KappaTheme.restore(); root.close(); }
                }
                Rectangle {
                    implicitWidth: applyLabel.implicitWidth + 36
                    implicitHeight: 32
                    radius: root.effectiveRadius
                    color: KappaTheme.sun
                    Text {
                        id: applyLabel
                        anchors.centerIn: parent
                        text: root.isPt ? "Aplicar" : "Apply"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: true
                        color: KappaTheme.inkOnBone
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { KappaTheme.apply(root.draft()); root.close(); }
                    }
                }
            }
        }
    }
}
