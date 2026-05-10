#!/bin/bash
# install.sh — Bardo Akten-Scan, Userspace-Install nach ~/.local/
#
# Setzt Symlinks von diesem Repo nach ~/.local/bin/, ~/.local/share/applications/,
# ~/.local/share/icons/. Kein Root nötig. Prüft die System-Dependencies und
# meldet fehlende Pakete mit dem passenden apt-Befehl.
#
# Verwendung:
#   ./install.sh             # installieren (Symlinks setzen)
#   ./install.sh --uninstall # Symlinks entfernen
#   ./install.sh --check     # nur Dependency-Check, keine Installation
#
# Bardo-AI · 2026 · MIT OR Apache-2.0

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons"

ACTION="install"
case "${1:-}" in
    --uninstall) ACTION="uninstall" ;;
    --check)     ACTION="check" ;;
    --help|-h)
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "") ACTION="install" ;;
    *)
        echo "Unbekanntes Argument: $1" >&2
        echo "Verwendung: $0 [--install|--uninstall|--check]" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------
# Dependency-Check
# ---------------------------------------------------------------
DEPS_FOUND=()
DEPS_MISSING=()
for cmd in scanimage ocrmypdf tesseract img2pdf pdfseparate pdftotext pdfunite python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
        DEPS_FOUND+=("$cmd")
    else
        DEPS_MISSING+=("$cmd")
    fi
done

# Mapping cmd → Paket-Name (Debian/Ubuntu)
get_pkg_for_cmd() {
    case "$1" in
        scanimage)    echo "sane-utils" ;;
        ocrmypdf)     echo "ocrmypdf" ;;
        tesseract)    echo "tesseract-ocr tesseract-ocr-deu" ;;
        img2pdf)      echo "img2pdf" ;;
        pdfseparate|pdftotext|pdfunite) echo "poppler-utils" ;;
        python3)      echo "python3 python3-tk" ;;
        *)            echo "$1" ;;
    esac
}

echo "Bardo Akten-Scan — Setup"
echo "Repo:    $REPO_DIR"
echo "Action:  $ACTION"
echo "─────────────────────────────────────────────"

echo "Dependency-Check:"
for cmd in "${DEPS_FOUND[@]}"; do
    echo "  ✓ $cmd"
done
if [ ${#DEPS_MISSING[@]} -gt 0 ]; then
    echo
    echo "Folgende Programme fehlen:"
    PKGS=""
    for cmd in "${DEPS_MISSING[@]}"; do
        pkg=$(get_pkg_for_cmd "$cmd")
        echo "  ✗ $cmd   (Paket: $pkg)"
        PKGS="$PKGS $pkg"
    done
    echo
    echo "Installation auf Debian/Ubuntu/Mint:"
    echo "    sudo apt install$PKGS"
    echo
    if [ "$ACTION" = "check" ]; then
        exit 1
    fi
    echo "Installation kann trotzdem fortfahren — Bardo-Scan startet, aber"
    echo "OCR/Scan/PDF-Operationen schlagen ohne diese Pakete fehl."
    echo
fi

if [ "$ACTION" = "check" ]; then
    echo "Alle Dependencies vorhanden."
    exit 0
fi

# ---------------------------------------------------------------
# Install / Uninstall
# ---------------------------------------------------------------
mkdir -p "$BIN_DIR" "$APPS_DIR" "$ICONS_DIR"

# Symlink-Tabelle: Quelle (relativ zum Repo) → Ziel
declare -A LINKS=(
    ["bin/bardo-scan"]="$BIN_DIR/bardo-scan"
    ["bin/bardo-duplex-merge"]="$BIN_DIR/bardo-duplex-merge"
    ["share/applications/bardo-scan.desktop"]="$APPS_DIR/bardo-scan.desktop"
    ["share/icons/bardo-scan.svg"]="$ICONS_DIR/bardo-scan.svg"
)

if [ "$ACTION" = "install" ]; then
    echo "Setze Symlinks:"
    for src in "${!LINKS[@]}"; do
        target="${LINKS[$src]}"
        src_abs="$REPO_DIR/$src"
        if [ ! -e "$src_abs" ]; then
            echo "  ! $src nicht gefunden, übersprungen" >&2
            continue
        fi
        if [ -L "$target" ] || [ -e "$target" ]; then
            echo "  ↻ $target (überschrieben)"
            rm -f "$target"
        else
            echo "  + $target"
        fi
        ln -s "$src_abs" "$target"
    done

    # Cache-Aktualisierung wenn möglich (still bei Fehler — nicht kritisch)
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -t "$ICONS_DIR" 2>/dev/null || true
    fi

    echo
    echo "Fertig. Bardo Akten-Scan ist im Anwendungs-Menü verfügbar."
    echo "Oder im Terminal:  bardo-scan"
    echo
    echo "Hinweis: $BIN_DIR muss im PATH sein. Prüfen mit:"
    echo "    echo \$PATH | tr ':' '\\n' | grep -F \"$BIN_DIR\""

elif [ "$ACTION" = "uninstall" ]; then
    echo "Entferne Symlinks:"
    for src in "${!LINKS[@]}"; do
        target="${LINKS[$src]}"
        if [ -L "$target" ]; then
            link_target=$(readlink "$target")
            if [[ "$link_target" == "$REPO_DIR/"* ]]; then
                rm "$target"
                echo "  - $target"
            else
                echo "  ! $target zeigt nicht auf dieses Repo, übersprungen"
            fi
        elif [ -e "$target" ]; then
            echo "  ! $target ist kein Symlink, manuelle Prüfung nötig"
        fi
    done

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -t "$ICONS_DIR" 2>/dev/null || true
    fi

    echo
    echo "Fertig. Symlinks entfernt."
fi
