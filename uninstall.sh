#!/data/data/com.termux/files/usr/bin/bash

# ── Rutas (autocontenido, no depende de lib/ externa) ──
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
OT_DATA_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/opencode-termux"
OT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME_DIR/.cache}/opencode-termux"
OPENCODE_BOOTSTRAPPER="${PREFIX}/bin/opencode"

echo ""
echo "  === Desinstalando OpenCode (opencode-termux) ==="
echo ""

# 1. Eliminar bootstrapper
if [[ -f "$OPENCODE_BOOTSTRAPPER" ]]; then
    rm -f "$OPENCODE_BOOTSTRAPPER"
    echo "  ✔ Bootstrapper eliminado: $OPENCODE_BOOTSTRAPPER"
else
    echo "  → Bootstrapper no encontrado en $OPENCODE_BOOTSTRAPPER"
fi

# 2. Eliminar binario real y datos
if [[ -d "$OT_DATA_DIR" ]]; then
    rm -rf "$OT_DATA_DIR"
    echo "  ✔ Datos eliminados: $OT_DATA_DIR"
else
    echo "  → Directorio de datos no encontrado"
fi

# 3. Limpiar cache
if [[ -d "$OT_CACHE_DIR" ]]; then
    rm -rf "$OT_CACHE_DIR"
    echo "  ✔ Cache eliminado: $OT_CACHE_DIR"
fi

echo ""
echo "  ✔ OpenCode desinstalado completamente"
echo ""
echo "  Para reinstalar:"
echo "    curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash"
echo ""

