#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# update.sh solo soporta modo clonado (no curl | bash).
# BASH_SOURCE[0] está definido aquí porque el usuario
# ejecuta directamente: bash update.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Cargar librerías ──────────────────────────────
# Cada lib tiene include guard propio, así que el orden
# de source no genera conflictos de readonly.
if [[ -f "${SCRIPT_DIR}/lib/env.sh" ]]; then
    source "${SCRIPT_DIR}/lib/env.sh"
    source "${SCRIPT_DIR}/lib/colors.sh"
    source "${SCRIPT_DIR}/lib/logging.sh"
    source "${SCRIPT_DIR}/lib/download.sh"
    source "${SCRIPT_DIR}/lib/compile.sh"
else
    echo "Error: No se encontraron las librerías en ${SCRIPT_DIR}/lib/"
    echo "Ejecuta este script desde la raíz del repositorio clonado:"
    echo "  git clone https://github.com/retired64/opencode-termux.git"
    echo "  cd opencode-termux && bash update.sh"
    exit 1
fi

# ── Flujo principal ───────────────────────────────
show_banner

log_title "Verificando actualizaciones de OpenCode..."

if [[ ! -f "${OT_DATA_DIR}/.version" ]]; then
    log_warn "No se encontró instalación previa de OpenCode"
    log_info "Ejecuta install.sh primero:"
    log_info "  bash install.sh"
    exit 1
fi

if check_for_updates; then
    log_title "Actualizando OpenCode..."
    download_opencode || exit 1
    log_info "Recompilando bootstrapper..."
    compile_bootstrapper || log_warn "Bootstrapper no se pudo recompilar (usando el existente)"
    echo ""
    log_ok "OpenCode actualizado correctamente"
else
    echo ""
    log_ok "No hay actualizaciones disponibles"
fi

echo ""

