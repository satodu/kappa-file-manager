import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Ryoku.Ui.Singletons

// Cartão de progresso de cópia/movimentação (Frames "Copiando arquivo grande" e "Cópia concluída")
Item {
    id: root
    width: 400
    height: card.height
    visible: opacity > 0
    opacity: root.state !== "idle" ? 1.0 : 0.0

    // "idle" | "running" | "paused" | "done" | "error"
    property string state: "idle"
    property string mode: "copy"
    property string name: ""
    property string destDir: ""
    property int index: 0
    property int items: 1
    property real done: 0
    property real total: 0
    property real speed: 0
    property real seconds: 0
    property string errorText: ""

    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    readonly property real fraction: root.total > 0 ? Math.min(1, root.done / root.total) : (root.state === "done" ? 1 : 0)
    readonly property bool finished: root.state === "done"
    readonly property bool failed: root.state === "error"
    readonly property color accent: root.failed ? Tokens.sun : KappaTheme.sun

    signal cancelRequested()
    signal pauseToggled()
    signal dismissed()
    signal revealRequested()

    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutExpo } }

    function formatSize(bytes) {
        if (bytes < 1024) return Math.round(bytes) + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1).replace(".", ",") + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1).replace(".", ",") + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(1).replace(".", ",") + " GB";
    }

    function formatEta() {
        if (root.speed <= 0 || root.total <= root.done) return "";
        var secs = Math.ceil((root.total - root.done) / root.speed);
        if (secs < 60) return secs + " s";
        return Math.floor(secs / 60) + " min " + (secs % 60) + " s";
    }

    readonly property string verb: {
        if (root.finished) return root.isPt ? "CONCLUÍDO_" : "DONE_";
        if (root.failed) return root.isPt ? "ERRO_" : "ERROR_";
        if (root.state === "paused") return root.isPt ? "PAUSADO_" : "PAUSED_";
        return root.mode === "move" ? (root.isPt ? "MOVENDO_" : "MOVING_") : (root.isPt ? "COPIANDO_" : "COPYING_");
    }

    MultiEffect {
        source: card
        anchors.fill: card
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.65)
        shadowVerticalOffset: 14
        shadowBlur: 0.8
    }

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + 40
        radius: root.effectiveRadius
        color: KappaTheme.paperLift
        border.width: 1
        border.color: root.failed ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : KappaTheme.lineStrong

        // Cantos técnicos em L
        Repeater {
            model: 4
            delegate: Item {
                required property int index
                readonly property bool atRight: index % 2 === 1
                readonly property bool atBottom: index >= 2
                x: atRight ? card.width - 13 : 6
                y: atBottom ? card.height - 13 : 6
                width: 7
                height: 7
                Rectangle { width: 7; height: 1; color: root.accent; y: parent.atBottom ? 6 : 0 }
                Rectangle { width: 1; height: 7; color: root.accent; x: parent.atRight ? 6 : 0 }
            }
        }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: "transparent"
                    border.width: 1.5
                    border.color: root.finished ? KappaTheme.sun : root.accent

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: root.finished ? "✓" : (root.failed ? "!" : "河")
                        font.family: root.finished || root.failed ? Tokens.ui : Tokens.jp
                        font.pixelSize: 14
                        font.bold: true
                        color: root.finished ? KappaTheme.sun : root.accent
                    }
                }

                ColumnLayout {
                    spacing: 2

                    RowLayout {
                        spacing: 8
                        Text { textFormat: Text.PlainText; text: "//"; font.family: Tokens.mono; font.pixelSize: 11; color: KappaTheme.inkDim }
                        Text {
                            textFormat: Text.PlainText
                            text: root.verb
                            font.family: Tokens.ui
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 2.2
                            color: root.accent
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: {
                            var n = root.items;
                            var where = root.destDir.split("/").pop() || "/";
                            if (root.finished) {
                                return n + (root.isPt ? (n === 1 ? " item" : " itens") : (n === 1 ? " item" : " items")) + " · " + root.formatSize(root.done) + " · " + Math.max(1, Math.round(root.seconds)) + " s";
                            }
                            return (root.index + 1) + (root.isPt ? " de " : " of ") + n + (n === 1 ? " item · → " : (root.isPt ? " itens · → " : " items · → ")) + where;
                        }
                        font.family: Tokens.mono
                        font.pixelSize: 11
                        color: KappaTheme.inkDim
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    textFormat: Text.PlainText
                    text: "×"
                    font.pixelSize: 20
                    color: KappaTheme.inkDim
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.finished || root.failed ? root.dismissed() : root.cancelRequested()
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: root.failed && root.errorText !== ""
                text: root.errorText
                wrapMode: Text.WordWrap
                font.family: Tokens.ui
                font.pixelSize: 12
                color: root.accent
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.name
                elide: Text.ElideMiddle
                font.family: Tokens.ui
                font.pixelSize: 15
                font.weight: Font.Medium
                color: KappaTheme.ink
            }

            // Barra segmentada (35 blocos 8x10)
            Row {
                spacing: 2
                Repeater {
                    model: 35
                    delegate: Rectangle {
                        required property int index
                        width: 8
                        height: 10
                        color: index < Math.round(root.fraction * 35) ? root.accent : KappaTheme.lineSoft
                        Behavior on color { ColorAnimation { duration: 90 } }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    textFormat: Text.PlainText
                    text: root.finished
                          ? (root.formatSize(root.done) + " / " + root.formatSize(root.done))
                          : (root.formatSize(root.done) + " / " + root.formatSize(root.total))
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.ink
                }
                Item { Layout.fillWidth: true }
                Text {
                    textFormat: Text.PlainText
                    text: root.finished ? "100%" : (root.state === "paused"
                          ? (root.isPt ? "pausado" : "paused")
                          : (root.speed > 0 ? root.formatSize(root.speed) + "/s" + (root.formatEta() !== "" ? " · " + root.formatEta() : "") : Math.round(root.fraction * 100) + "%"))
                    font.family: Tokens.mono
                    font.pixelSize: 12
                    color: KappaTheme.inkDim
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: !root.finished && !root.failed
                    implicitWidth: pauseLabel.implicitWidth + 28
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: pauseArea.containsMouse ? KappaTheme.tint10 : "transparent"
                    border.width: 1
                    border.color: KappaTheme.line
                    Text {
                        textFormat: Text.PlainText
                        id: pauseLabel
                        anchors.centerIn: parent
                        text: root.state === "paused" ? (root.isPt ? "Continuar" : "Resume") : (root.isPt ? "Pausar" : "Pause")
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: KappaTheme.inkDim
                    }
                    MouseArea {
                        id: pauseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pauseToggled()
                    }
                }

                Rectangle {
                    visible: !root.finished && !root.failed
                    implicitWidth: cancelLabel.implicitWidth + 28
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: cancelArea.containsMouse ? Qt.rgba(Tokens.sun.r, Tokens.sun.g, Tokens.sun.b, 0.12) : "transparent"
                    border.width: 1
                    border.color: Tokens.sun
                    Text {
                        textFormat: Text.PlainText
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: root.isPt ? "Cancelar" : "Cancel"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: Tokens.sun
                    }
                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelRequested()
                    }
                }

                Rectangle {
                    visible: root.finished
                    implicitWidth: revealLabel.implicitWidth + 28
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: "transparent"
                    border.width: 1
                    border.color: KappaTheme.sun
                    Text {
                        textFormat: Text.PlainText
                        id: revealLabel
                        anchors.centerIn: parent
                        text: root.isPt ? "Mostrar na pasta" : "Show in folder"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: KappaTheme.sun
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.revealRequested()
                    }
                }

                Rectangle {
                    visible: root.finished || root.failed
                    implicitWidth: closeLabel.implicitWidth + 28
                    implicitHeight: 30
                    radius: root.effectiveRadius
                    color: "transparent"
                    border.width: 1
                    border.color: KappaTheme.line
                    Text {
                        textFormat: Text.PlainText
                        id: closeLabel
                        anchors.centerIn: parent
                        text: root.isPt ? "Fechar" : "Close"
                        font.family: Tokens.ui
                        font.pixelSize: 12
                        color: KappaTheme.inkDim
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissed()
                    }
                }
            }
        }
    }
}
