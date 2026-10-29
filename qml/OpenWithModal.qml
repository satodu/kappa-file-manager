import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// "Outro aplicativo…": todos os aplicativos instalados, com busca, para abrir o arquivo com qualquer um deles
Item {
    id: root
    visible: active

    property bool active: false
    property var target: null
    property var apps: []
    property bool loading: false
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    readonly property var filtered: {
        var q = searchInput.text.trim().toLowerCase();
        if (q === "") return root.apps;
        return root.apps.filter(function(a) { return a.name.toLowerCase().indexOf(q) !== -1; });
    }

    signal chosen(string appId)
    signal cancelled()

    function open(item) {
        root.target = item;
        root.apps = [];
        root.loading = true;
        searchInput.text = "";
        list.currentIndex = 0;
        searchInput.forceActiveFocus();
    }

    function pick() {
        if (list.currentIndex >= 0 && list.currentIndex < root.filtered.length) {
            root.chosen(root.filtered[list.currentIndex].id);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea { anchors.fill: parent; onClicked: root.cancelled() }
    }

    MultiEffect {
        source: dialog
        anchors.fill: dialog
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.65)
        shadowVerticalOffset: 14
        shadowBlur: 0.8
    }

    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: 460
        height: Math.min(parent.height - 80, 520)
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: KappaTheme.lineStrong

        MouseArea { anchors.fill: parent }

        Repeater {
            model: 4
            delegate: Item {
                required property int index
                readonly property bool atRight: index % 2 === 1
                readonly property bool atBottom: index >= 2
                x: atRight ? dialog.width - 13 : 6
                y: atBottom ? dialog.height - 13 : 6
                width: 7
                height: 7
                Rectangle { width: 7; height: 1; color: KappaTheme.sun; y: parent.atBottom ? 6 : 0 }
                Rectangle { width: 1; height: 7; color: KappaTheme.sun; x: parent.atRight ? 6 : 0 }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: "transparent"
                    border.width: 1.5
                    border.color: KappaTheme.sun
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "開"
                        font.family: Tokens.jp
                        font.pixelSize: 18
                        font.bold: true
                        color: KappaTheme.sun
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        spacing: 8
                        Text { textFormat: Text.PlainText; text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                        Text {
                            textFormat: Text.PlainText
                            text: root.isPt ? "ABRIR COM_" : "OPEN WITH_"
                            font.family: Tokens.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 2.2
                            color: KappaTheme.sun
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: root.target ? root.target.name : ""
                        elide: Text.ElideMiddle
                        font.family: Tokens.display
                        font.pixelSize: 20
                        color: KappaTheme.ink
                    }
                }

                Text { textFormat: Text.PlainText; text: "esc"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim; Layout.alignment: Qt.AlignTop }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: Math.max(0, root.effectiveRadius - 2)
                color: KappaTheme.paper
                border.width: 1
                border.color: searchInput.activeFocus ? KappaTheme.sun : KappaTheme.line

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: KappaTheme.ink
                    selectionColor: KappaTheme.sun
                    selectedTextColor: KappaTheme.inkOnBone
                    selectByMouse: true
                    font.family: Tokens.ui
                    font.pixelSize: 14
                    clip: true

                    onTextChanged: list.currentIndex = 0
                    Keys.onReturnPressed: root.pick()
                    Keys.onEnterPressed: root.pick()
                    Keys.onEscapePressed: root.cancelled()
                    Keys.onDownPressed: list.currentIndex = Math.min(list.currentIndex + 1, root.filtered.length - 1)
                    Keys.onUpPressed: list.currentIndex = Math.max(list.currentIndex - 1, 0)

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                        text: root.isPt ? "Buscar aplicativo…" : "Search applications…"
                        font: searchInput.font
                        color: KappaTheme.inkFaint
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.filtered
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: root.filtered.length === 0
                    text: root.loading ? "…" : (root.isPt ? "Nenhum aplicativo encontrado" : "No applications found")
                    font.family: Tokens.ui
                    font.pixelSize: 13
                    color: KappaTheme.inkFaint
                }

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 34
                    radius: root.effectiveRadius
                    color: (rowMouse.containsMouse || ListView.isCurrentItem) ? KappaTheme.tint10 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Text { textFormat: Text.PlainText; text: "󰀻"; font.family: Tokens.mono; font.pixelSize: 13; color: ListView.isCurrentItem ? KappaTheme.sun : KappaTheme.inkDim }
                        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; font.family: Tokens.ui; font.pixelSize: 13; color: KappaTheme.ink }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chosen(modelData.id)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: KappaTheme.line }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { textFormat: Text.PlainText; text: "↑↓  Enter"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 88
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: cancelArea.containsMouse ? KappaTheme.tint10 : "transparent"
                    border.width: 1
                    border.color: KappaTheme.line
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.isPt ? "Cancelar" : "Cancel"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: KappaTheme.inkDim
                    }
                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }
                }
            }
        }
    }
}
