pragma Singleton

import QtQuick
import Quickshell

// Ajudantes de segurança para tudo que vem do disco (nomes, caminhos, imagens, área de transferência)
Singleton {
    // Só formatos comuns e bem testados são decodificados em miniaturas; nada de SVG, PSD, EXR etc.
    readonly property var previewExts: ["png", "jpg", "jpeg", "gif", "webp", "bmp"]
    // Acima disto o arquivo não vira miniatura (evita arquivos gigantes e "decompression bombs")
    readonly property real maxPreviewBytes: 32 * 1024 * 1024

    // URL file:// com cada segmento codificado ("#", "?" e "%" no nome não mudam o alvo)
    function fileUrl(path) {
        if (!path || path.charAt(0) !== "/") return "";
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function extOf(name) {
        var i = name ? name.lastIndexOf(".") : -1;
        return i >= 0 ? name.substring(i + 1).toLowerCase() : "";
    }

    function isPreviewable(item) {
        if (!item || item.is_dir || item.kind !== "image") return false;
        if (previewExts.indexOf(extOf(item.name)) < 0) return false;
        return (item.size_bytes || 0) > 0 && item.size_bytes <= maxPreviewBytes;
    }

    function previewUrl(item) {
        return isPreviewable(item) ? fileUrl(item.path) : "";
    }

    // Caminhos vindos da área de transferência: só URIs file:// absolutas, sem NUL
    function pathsFromClipboard(text) {
        var out = [];
        var lines = (text || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.indexOf("file:///") !== 0) continue;
            var p;
            try { p = decodeURIComponent(line.substring(7)); } catch (e) { continue; }
            if (p.charAt(0) === "/" && p.indexOf("\u0000") < 0) out.push(p);
        }
        return out;
    }
}
