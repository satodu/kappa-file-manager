import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: root
    height: 56
    color: KappaTheme.paper

    property string currentFolder: "Home"
    property string activePlate: "01 // ARQUIVOS"
    property alias searchQuery: searchInput.text
    readonly property bool isSearchFocused: searchInput.activeFocus
    readonly property bool isPt: I18n.lang.startsWith("pt")
    readonly property int effectiveRadius: (typeof app !== "undefined" && app && app.systemRadius !== undefined) ? app.systemRadius : Tokens.radius
    signal searchRequested(string query)
    signal searchCleared()

    function focusSearch() {
        searchInput.forceActiveFocus();
        searchInput.selectAll();
    }

    function appendSearchChar(ch) {
        searchInput.text = searchInput.text + ch;
        searchInput.cursorPosition = searchInput.text.length;
        searchInput.forceActiveFocus();
    }

    function clearSearch() {
        searchInput.text = "";
        searchInput.focus = false;
        root.searchCleared();
    }

    PixelGlyphs { id: glyphs }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 12

        // Marca Kappa + Meandro Pixel Art Real
        RowLayout {
            spacing: 8

            // Meandro geométrico oficial do Figcraft
            PixelGlyphs.PixelMeander {
                glyphColor: KappaTheme.inkDim
            }

            Text {
                text: "Kappa"
                font.family: Tokens.display
                font.pixelSize: 20
                font.bold: true
                color: KappaTheme.ink
            }

            // Kana oficial: "ファイル"
            Text {
                text: "ファイル"
                font.family: Tokens.jp
                font.pixelSize: 12
                color: KappaTheme.inkDim
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Placa brutalista
        Rectangle {
            implicitWidth: badgeText.implicitWidth + 14
            implicitHeight: 22
            radius: root.effectiveRadius
            color: "transparent"
            border.width: 1
            border.color: KappaTheme.lineStrong

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: root.activePlate
                font.family: Tokens.mono
                font.pixelSize: 11
                color: KappaTheme.ink
            }
        }

        // Pixel Torii Oficial do Figcraft + Chevrons
        RowLayout {
            spacing: 8

            PixelGlyphs.PixelTorii {
                glyphColor: KappaTheme.inkDim
            }

            Text {
                text: "//////"
                font.family: Tokens.mono
                font.pixelSize: 11
                color: KappaTheme.inkFaint
            }
        }

        Item { Layout.fillWidth: true }

        // Campo de Busca Inline com atalho Ctrl+F
        Rectangle {
            implicitWidth: 320
            implicitHeight: 34
            radius: root.effectiveRadius
            color: searchInput.activeFocus ? KappaTheme.paperLift : KappaTheme.tint5
            border.width: 1
            border.color: searchInput.activeFocus ? KappaTheme.sun : KappaTheme.line

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: "󰍉"
                    font.family: Tokens.mono
                    font.pixelSize: 13
                    color: searchInput.activeFocus ? KappaTheme.sun : KappaTheme.inkDim
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: KappaTheme.ink
                    font.family: Tokens.ui
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true

                    Text {
                        anchors.fill: parent
                        text: root.isPt ? ("Buscar em " + root.currentFolder + "…") : ("Search in " + root.currentFolder + "…")
                        color: KappaTheme.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: 13
                        visible: !searchInput.text && !searchInput.activeFocus
                        verticalAlignment: Text.AlignVCenter
                    }

                    onTextChanged: {
                        root.searchRequested(text)
                    }

                    Keys.onEscapePressed: {
                        root.clearSearch();
                        if (typeof app !== "undefined" && app) {
                            app.forceActiveFocus();
                        }
                    }

                    Keys.onDownPressed: {
                        searchInput.focus = false;
                        if (typeof app !== "undefined" && app) {
                            app.forceActiveFocus();
                            app.selectNextItem(1);
                        }
                    }

                    Keys.onUpPressed: {
                        searchInput.focus = false;
                        if (typeof app !== "undefined" && app) {
                            app.forceActiveFocus();
                            app.selectNextItem(-1);
                        }
                    }

                    Keys.onReturnPressed: {
                        if (typeof app !== "undefined" && app) {
                            var sel = (app.isSplit && app.activePane === "right") ? app.rightSelectedItem : app.selectedItem;
                            if (sel) {
                                app.openItem(sel);
                            }
                        }
                    }
                }

                // Atalho Ctrl+F em mono
                Rectangle {
                    implicitWidth: atalhoText.implicitWidth + 8
                    implicitHeight: 18
                    radius: root.effectiveRadius
                    color: KappaTheme.tint10
                    visible: !searchInput.text

                    Text {
                        id: atalhoText
                        anchors.centerIn: parent
                        text: "Ctrl+F"
                        font.family: Tokens.mono
                        font.pixelSize: 10
                        color: KappaTheme.inkFaint
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusSearch()
                    }
                }

                // Botão limpar busca
                Text {
                    text: "󰅖"
                    font.family: Tokens.mono
                    font.pixelSize: 11
                    color: KappaTheme.inkDim
                    visible: searchInput.text.length > 0
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.clearSearch();
                            if (typeof app !== "undefined" && app) {
                                app.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }
    }

    // Linha inferior hairline
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: KappaTheme.line
    }
}
