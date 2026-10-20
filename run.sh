#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "» Compilando motor Rust..."
cargo build

export QT_PLUGIN_PATH="/usr/lib/qt6/plugins:${QT_PLUGIN_PATH}"

echo "» Iniciando Kappa File Manager..."
quickshell -p "$DIR/qml/shell.qml"
