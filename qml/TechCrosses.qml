import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root
    anchors.fill: parent

    // As 22 posições exatas do nó 145 (Reg marcas) do Figcraft
    readonly property var crossPositions: [
        {x: 0, y: 3}, {x: 184, y: 3}, {x: 368, y: 3}, {x: 552, y: 3}, {x: 736, y: 3}, {x: 920, y: 3}, {x: 1104, y: 3},
        {x: 0, y: 95}, {x: 184, y: 95}, {x: 368, y: 95}, {x: 552, y: 95}, {x: 736, y: 95}, {x: 920, y: 95},
        {x: 0, y: 187}, {x: 184, y: 187}, {x: 368, y: 187}, {x: 552, y: 187},
        {x: 0, y: 279}, {x: 184, y: 279}, {x: 368, y: 279},
        {x: 0, y: 371}, {x: 184, y: 371}
    ]

    Repeater {
        model: root.crossPositions
        delegate: Item {
            required property var modelData
            x: modelData.x + 20
            y: modelData.y + 380
            width: 7
            height: 7
            opacity: 0.12

            // Linha horizontal da cruz (+)
            Rectangle {
                x: 0; y: 3; width: 7; height: 1
                color: KappaTheme.inkDim
            }
            // Linha vertical da cruz (+)
            Rectangle {
                x: 3; y: 0; width: 1; height: 7
                color: KappaTheme.inkDim
            }
        }
    }
}
