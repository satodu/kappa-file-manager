import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    height: 40
    color: KappaTheme.paperLift
    border.width: 1
    border.color: KappaTheme.lineSoft

    property string activeCategory: "all"
    property string searchScope: "folder" // "folder" | "all"
    property var counts: ({ all: 0, audio: 0, image: 0, doc: 0, folder: 0, code: 0 })
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius

    signal categoryChanged(string category)
    signal scopeChanged(string scope)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 8

        // Chips de Filtro
        Repeater {
            model: [
                { id: "all", label: root.isPt ? "Tudo" : "All", key: "all" },
                { id: "audio", label: root.isPt ? "Áudio" : "Audio", key: "audio" },
                { id: "image", label: root.isPt ? "Imagens" : "Images", key: "image" },
                { id: "doc", label: root.isPt ? "Documentos" : "Documents", key: "doc" },
                { id: "folder", label: root.isPt ? "Pastas" : "Folders", key: "folder" },
                { id: "code", label: root.isPt ? "Código" : "Code", key: "code" }
            ]

            delegate: Rectangle {
                required property var modelData

                implicitWidth: chipRow.implicitWidth + 16
                implicitHeight: 26
                radius: root.effectiveRadius
                color: root.activeCategory === modelData.id ? KappaTheme.sun : (chipMouse.containsMouse ? KappaTheme.tint10 : "transparent")
                border.width: 1
                border.color: root.activeCategory === modelData.id ? KappaTheme.sun : KappaTheme.line

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        textFormat: Text.PlainText
                        text: modelData.label
                        font.family: Tokens.ui
                        font.pixelSize: 11
                        font.bold: root.activeCategory === modelData.id
                        color: root.activeCategory === modelData.id ? KappaTheme.paper : KappaTheme.ink
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: String(root.counts[modelData.key] || 0)
                        font.family: Tokens.mono
                        font.pixelSize: 10
                        color: root.activeCategory === modelData.id ? KappaTheme.paper : KappaTheme.inkFaint
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.activeCategory = modelData.id;
                        root.categoryChanged(modelData.id);
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Easing.OutExpo }
                }
            }
        }

        Rectangle {
            width: 1
            height: 18
            color: KappaTheme.line
        }

        // Seletor de Escopo: Esta pasta vs Tudo
        RowLayout {
            spacing: 4

            Rectangle {
                implicitWidth: scopeFolderText.implicitWidth + 12
                implicitHeight: 24
                radius: root.effectiveRadius
                color: root.searchScope === "folder" ? KappaTheme.tint16 : "transparent"
                border.width: 1
                border.color: root.searchScope === "folder" ? KappaTheme.lineStrong : "transparent"

                Text {
                    textFormat: Text.PlainText
                    id: scopeFolderText
                    anchors.centerIn: parent
                    text: root.isPt ? "Esta pasta" : "This folder"
                    font.family: Tokens.ui
                    font.pixelSize: 11
                    color: root.searchScope === "folder" ? KappaTheme.ink : KappaTheme.inkDim
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.searchScope = "folder";
                        root.scopeChanged("folder");
                    }
                }
            }

            Rectangle {
                implicitWidth: scopeAllText.implicitWidth + 12
                implicitHeight: 24
                radius: root.effectiveRadius
                color: root.searchScope === "all" ? KappaTheme.tint16 : "transparent"
                border.width: 1
                border.color: root.searchScope === "all" ? KappaTheme.lineStrong : "transparent"

                Text {
                    textFormat: Text.PlainText
                    id: scopeAllText
                    anchors.centerIn: parent
                    text: root.isPt ? "Tudo" : "All"
                    font.family: Tokens.ui
                    font.pixelSize: 11
                    color: root.searchScope === "all" ? KappaTheme.ink : KappaTheme.inkDim
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.searchScope = "all";
                        root.scopeChanged("all");
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            textFormat: Text.PlainText
            text: root.isPt ? "ordenar: relevância" : "sort: relevance"
            font.family: Tokens.mono
            font.pixelSize: 11
            color: KappaTheme.inkFaint
        }
    }
}
