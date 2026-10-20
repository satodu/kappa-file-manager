import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

Item {
    id: root
    visible: false

    property string sortField: "name" // "name" | "type" | "modified" | "size"
    property string sortDirection: "asc" // "asc" | "desc"
    property bool groupByType: false
    property real menuX: 0
    property real menuY: 0

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    readonly property color cyanAccent: KappaTheme.sun

    signal sortFieldSelected(string field)
    signal sortDirectionSelected(string direction)
    signal toggleGroupByType()

    function show(posX, posY) {
        var clampX = Math.min(posX, root.width - 252 - 16);
        var clampY = Math.min(posY, root.height - 256 - 16);
        root.menuX = Math.max(16, clampX);
        root.menuY = Math.max(16, clampY);
        root.visible = true;
    }

    function hide() {
        root.visible = false;
    }

    // Camada invisível para fechar ao clicar fora
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.hide()
        onWheel: root.hide()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SOMBRA SUAVE (Nó 2867: dropShadow y:14 blur:30 a:0.65)
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
    // MENU ORDENAR (Nó 2867 do Figcraft - 252x256)
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: menuBox
        x: root.menuX
        y: root.menuY
        width: 252
        implicitHeight: sortLayout.implicitHeight + 12
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: KappaTheme.lineStrong
        z: 2

        ColumnLayout {
            id: sortLayout
            anchors.fill: parent
            anchors.margins: 6
            spacing: 0

            // 1. Nome (Nó 2868: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: nameMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰁨"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.sortField === "name" ? root.cyanAccent : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Nome" : "Name"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.sortField === "name"
                        color: root.sortField === "name" ? root.cyanAccent : KappaTheme.ink
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cyanAccent
                        visible: root.sortField === "name"
                    }
                }

                MouseArea {
                    id: nameMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.sortFieldSelected("name"); root.hide(); }
                }
            }

            // 2. Tipo (Nó 2872: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: typeMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰈙"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.sortField === "type" ? root.cyanAccent : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Tipo" : "Type"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.sortField === "type"
                        color: root.sortField === "type" ? root.cyanAccent : KappaTheme.ink
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cyanAccent
                        visible: root.sortField === "type"
                    }
                }

                MouseArea {
                    id: typeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.sortFieldSelected("type"); root.hide(); }
                }
            }

            // 3. Data / Modificado (Nó 2876: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: dateMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰃭"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.sortField === "modified" ? root.cyanAccent : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Data" : "Date"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.sortField === "modified"
                        color: root.sortField === "modified" ? root.cyanAccent : KappaTheme.ink
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cyanAccent
                        visible: root.sortField === "modified"
                    }
                }

                MouseArea {
                    id: dateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.sortFieldSelected("modified"); root.hide(); }
                }
            }

            // 4. Tamanho (Nó 2886: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: sizeMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰆼"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.sortField === "size" ? root.cyanAccent : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Tamanho" : "Size"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.sortField === "size"
                        color: root.sortField === "size" ? root.cyanAccent : KappaTheme.ink
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cyanAccent
                        visible: root.sortField === "size"
                    }
                }

                MouseArea {
                    id: sizeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.sortFieldSelected("size"); root.hide(); }
                }
            }

            // Separador (Nó 2880: 9px)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
            }

            // 5. Crescente A→Z (Nó 2890: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: ascMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰁝"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.sortDirection === "asc" ? root.cyanAccent : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Crescente" : "Ascending"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.sortDirection === "asc"
                        color: root.sortDirection === "asc" ? root.cyanAccent : KappaTheme.ink
                    }

                    Text {
                        text: "A→Z"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: root.sortDirection === "asc" ? root.cyanAccent : KappaTheme.inkFaint
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cyanAccent
                        visible: root.sortDirection === "asc"
                    }
                }

                MouseArea {
                    id: ascMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.sortDirectionSelected("asc"); root.hide(); }
                }
            }

            // 6. Decrescente Z→A (Nó 2894: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: descMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰁅"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.sortDirection === "desc" ? root.cyanAccent : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Decrescente" : "Descending"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.sortDirection === "desc"
                        color: root.sortDirection === "desc" ? root.cyanAccent : KappaTheme.ink
                    }

                    Text {
                        text: "Z→A"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: root.sortDirection === "desc" ? root.cyanAccent : KappaTheme.inkFaint
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: root.cyanAccent
                        visible: root.sortDirection === "desc"
                    }
                }

                MouseArea {
                    id: descMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.sortDirectionSelected("desc"); root.hide(); }
                }
            }

            // Separador (Nó 2898: 9px)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: KappaTheme.line }
            }

            // 7. Agrupar por tipo (Nó 2882: 238x32)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: root.effectiveRadius
                color: groupMouse.containsMouse ? KappaTheme.tint10 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "󰅪"
                        font.family: Tokens.mono
                        font.pixelSize: 13
                        color: root.groupByType ? KappaTheme.sun : KappaTheme.inkDim
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.isPt ? "Agrupar por tipo" : "Group by type"
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        font.bold: root.groupByType
                        color: root.groupByType ? KappaTheme.sun : KappaTheme.ink
                    }

                    Text {
                        text: "✓"
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        font.bold: true
                        color: KappaTheme.sun
                        visible: root.groupByType
                    }
                }

                MouseArea {
                    id: groupMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.toggleGroupByType(); root.hide(); }
                }
            }
        }
    }
}
