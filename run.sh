#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "» Compilando motor Rust..."
cargo build

export QT_PLUGIN_PATH="/usr/lib/qt6/plugins:${QT_PLUGIN_PATH}"

echo "» Iniciando Kappa File Manager..."
QS_APP_ID=kappa-file-manager KAPPA_BACKEND="$DIR/target/debug/kappa-file-manager" quickshell -p "$DIR/qml/shell.qml"
