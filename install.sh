#!/usr/bin/env bash
# Installs Floema for this user (~/.local), without root. It becomes nobody's
# default terminal: that is a switch in Floema itself.
#
#   ./install.sh           a copy of it
#   ./install.sh --here    runs from this checkout (GENOMA=<genoma to run it with>)
set -euo pipefail
cd "$(dirname "$0")"

id=dev.akusen.floema
bin="$HOME/.local/bin"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
run="${GENOMA:-genoma}"
command -v "$run" >/dev/null || { echo "Floema needs genoma in PATH."; exit 1; }

if [[ "${1:-}" == --here ]]; then
    dir="$PWD/genoma"
else
    dir="$data/floema/app"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp -r genoma/. "$dir/"
fi
mkdir -p "$bin"
sed "s|/usr/share/floema|$dir|; s|\${GENOMA:-genoma}|\${GENOMA:-$run}|" floema > "$bin/floema"
chmod 755 "$bin/floema"
install -Dm644 "$id.desktop" "$data/applications/$id.desktop"
install -Dm644 assets/floema.svg "$data/icons/hicolor/scalable/apps/$id.svg"
# The grid's font, where it is not installed already.
if ! fc-list : family | grep -qx "Space Mono"; then
    install -Dm644 -t "$data/fonts/floema" assets/fonts/*.ttf
    fc-cache -f "$data/fonts/floema" 2>/dev/null || true
fi
update-desktop-database "$data/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$data/icons/hicolor" 2>/dev/null || true
echo "Installed: $bin/floema"
