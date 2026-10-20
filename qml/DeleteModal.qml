import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// Modal de confirmação de exclusão (Frames "Confirmar exclusão (lixeira)" e "(permanente)")
Item {
    id: root
    visible: false
    focus: visible

    property var targets: []
    property bool permanent: false
    property bool acknowledged: false

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    readonly property bool canConfirm: !root.permanent || root.acknowledged

    signal confirmed()
    signal cancelled()

    function open(items, isPermanent) {
        root.targets = items || [];
        root.permanent = !!isPermanent;
        root.acknowledged = false;
        root.visible = true;
        root.forceActiveFocus();
    }

    function close() {
        root.visible = false;
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1).replace(".", ",") + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1).replace(".", ",") + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(1).replace(".", ",") + " GB";
    }

    readonly property real totalBytes: {
        var t = 0;
        for (var i = 0; i < root.targets.length; i++) t += (root.targets[i].size_bytes || 0);
        return t;
    }

    function tryConfirm() {
        if (root.canConfirm) root.confirmed();
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.cancelled();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.tryConfirm();
            event.accepted = true;
        } else if (event.key === Qt.Key_Space && root.permanent) {
            root.acknowledged = !root.acknowledged;
            event.accepted = true;
        } else {
            event.accepted = true;
        }
    }

    // Scrim
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelled()
        }
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
        width: 440
        height: content.implicitHeight + 48
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: root.permanent ? Qt.rgba(KappaTheme.sun.r, KappaTheme.sun.g, KappaTheme.sun.b, 0.6) : KappaTheme.lineStrong

        MouseArea { anchors.fill: parent }

        // Cantos técnicos em L (corner ticks)
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
                Rectangle {
                    width: 7; height: 1; color: KappaTheme.sun
                    y: parent.atBottom ? 6 : 0
                }
                Rectangle {
                    width: 1; height: 7; color: KappaTheme.sun
                    x: parent.atRight ? 6 : 0
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 16

            // Cabeçalho: hanko + título
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
                        anchors.centerIn: parent
                        text: root.permanent ? "捨" : "河"
                        font.family: Tokens.jp
                        font.pixelSize: 18
                        font.bold: true
                        color: KappaTheme.sun
                    }
                }

                ColumnLayout {
                    spacing: 3

                    RowLayout {
                        spacing: 8
                        Text {
                            text: "//"
                            font.family: Tokens.mono
                            font.pixelSize: 11
                            color: KappaTheme.inkDim
                        }
                        Text {
                            text: root.permanent
                                  ? (root.isPt ? "EXCLUIR PERMANENTE_" : "DELETE PERMANENTLY_")
                                  : (root.isPt ? "LIXEIRA_" : "TRASH_")
                            font.family: Tokens.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 2.2
                            color: KappaTheme.sun
                        }
                    }

                    Text {
                        text: root.permanent
                              ? (root.isPt ? "Excluir permanentemente?" : "Delete permanently?")
                              : (root.isPt ? "Mover para a lixeira?" : "Move to trash?")
                        font.family: Tokens.display
                        font.pixelSize: 20
                        color: KappaTheme.ink
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "esc"
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.inkDim
                    Layout.alignment: Qt.AlignTop
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.permanent
                      ? (root.isPt ? "Esta ação não pode ser desfeita. Os itens serão removidos do disco." : "This cannot be undone. The items will be removed from disk.")
                      : (root.isPt ? "Você poderá restaurar os itens pela Lixeira do sistema." : "You can restore the items from the system Trash.")
                font.family: Tokens.ui
                font.pixelSize: 13
                color: KappaTheme.inkDim
            }

            // Lista dos itens
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: itemsCol.implicitHeight
                radius: Math.max(0, root.effectiveRadius - 2)
                color: KappaTheme.paper
                border.width: 1
                border.color: KappaTheme.line
                clip: true

                Column {
                    id: itemsCol
                    width: parent.width

                    Repeater {
                        model: Math.min(root.targets.length, 5)
                        delegate: RowLayout {
                            required property int index
                            readonly property var it: root.targets[index]
                            width: itemsCol.width
                            height: 38
                            spacing: 12

                            Item { Layout.preferredWidth: 2 }
                            Text {
                                text: it.is_dir ? "▣" : "▤"
                                font.family: Tokens.mono
                                font.pixelSize: 13
                                color: KappaTheme.sun
                            }
                            Text {
                                Layout.fillWidth: true
                                text: it.name
                                elide: Text.ElideMiddle
                                font.family: Tokens.ui
                                font.pixelSize: 13
                                color: KappaTheme.ink
                            }
                            Text {
                                text: it.is_dir ? (root.isPt ? "Pasta" : "Folder") : root.formatSize(it.size_bytes || 0)
                                font.family: Tokens.mono
                                font.pixelSize: 11
                                color: KappaTheme.inkDim
                            }
                            Item { Layout.preferredWidth: 2 }
                        }
                    }

                    Text {
                        visible: root.targets.length > 5
                        leftPadding: 16
                        height: 30
                        verticalAlignment: Text.AlignVCenter
                        text: "+ " + (root.targets.length - 5) + (root.isPt ? " itens" : " more")
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkDim
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.targets.length + (root.isPt ? (root.targets.length === 1 ? " item selecionado" : " itens selecionados") : (root.targets.length === 1 ? " item selected" : " items selected"))
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.ink
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.formatSize(root.totalBytes)
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.inkDim
                }
            }

            // Confirmação explícita (somente exclusão permanente)
            RowLayout {
                Layout.fillWidth: true
                visible: root.permanent
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    radius: 4
                    color: "transparent"
                    border.width: 1.5
                    border.color: KappaTheme.sun

                    Text {
                        anchors.centerIn: parent
                        visible: root.acknowledged
                        text: "✓"
                        font.pixelSize: 11
                        color: KappaTheme.sun
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.acknowledged = !root.acknowledged
                    }
                }
                Text {
                    text: root.isPt ? "Entendo que não é possível desfazer" : "I understand this cannot be undone"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    color: KappaTheme.ink

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.acknowledged = !root.acknowledged
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: KappaTheme.line
            }

            // Rodapé
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    visible: !root.permanent
                    text: root.isPt ? "Excluir permanentemente" : "Delete permanently"
                    font.family: Tokens.ui
                    font.pixelSize: 12
                    font.underline: true
                    color: KappaTheme.sun

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.permanent = true;
                            root.acknowledged = false;
                        }
                    }
                }
                Text {
                    visible: root.permanent
                    text: "Shift+Del"
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.inkDim
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 88
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: cancelArea.containsMouse ? KappaTheme.tint10 : "transparent"
                    border.width: 1
                    border.color: KappaTheme.line

                    Text {
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

                Rectangle {
                    implicitWidth: confirmLabel.implicitWidth + 36
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: KappaTheme.sun
                    opacity: root.canConfirm ? 1.0 : 0.4

                    Text {
                        id: confirmLabel
                        anchors.centerIn: parent
                        text: root.permanent
                              ? (root.isPt ? "Excluir" : "Delete")
                              : (root.isPt ? "Mover para a lixeira" : "Move to trash")
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        font.bold: true
                        color: KappaTheme.inkOnBone
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.canConfirm
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmed()
                    }
                }
            }
        }
    }
}
