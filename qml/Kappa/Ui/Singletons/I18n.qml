pragma Singleton

import QtQuick

// Idioma da interface: o Ryoku (se instalado) decide; senão vale o locale do sistema.
Item {
    id: i18n
    visible: false

    property var ryoku: null

    Component.onCompleted: {
        try {
            i18n.ryoku = Qt.createQmlObject(
                'import QtQuick\n' +
                'import Ryoku.Ui.Singletons as R\n' +
                'QtObject { readonly property string lang: R.I18n.lang }',
                i18n, "KappaRyokuI18n");
        } catch (e) {
            i18n.ryoku = null;
        }
    }

    // Ex.: "pt_BR", "en_US"
    readonly property string lang: ryoku ? ryoku.lang : Qt.locale().name
}
