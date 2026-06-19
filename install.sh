#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# FIX 1: BASH_SOURCE[0] no está definido cuando se ejecuta via pipe (curl | bash)
# En ese caso, no hay archivo fuente, así que SCRIPT_DIR queda vacío/inválido.
# Usamos ${BASH_SOURCE[0]:-} con fallback a "" para evitar el error "unbound variable"
# y luego detectamos si el path resultante tiene libs disponibles.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || echo "")"

# FIX 2: /tmp no existe en Termux o es read-only.
# Termux expone su directorio temporal real en la variable $TMPDIR
# (típicamente /data/data/com.termux/files/usr/tmp).
# Nunca usar /tmp hardcodeado en scripts para Termux.
TERMUX_TMP="${TMPDIR:-${PREFIX}/tmp}"
OPENCODE_TMP="${TERMUX_TMP}/opencode-termux-lib"

# ── Modo standalone: descarga libs desde GitHub raw ─
# Se activa cuando el script llega por pipe (curl | bash) y no hay repo clonado.
# BASH_SOURCE[0] no está definido en ese contexto, por eso SCRIPT_DIR queda vacío.
_standalone_bootstrap() {
    local raw="$1"

    # FIX 2 aplicado: usar $TERMUX_TMP en lugar de /tmp
    mkdir -p "${OPENCODE_TMP}"

    for lib in env.sh colors.sh logging.sh deps.sh download.sh compile.sh; do
        curl -fsSL "${raw}/lib/${lib}" -o "${OPENCODE_TMP}/${lib}" 2>/dev/null || {
            echo "Error: No se pudo descargar lib/${lib}"
            echo "El repositorio puede no estar disponible. Intenta clonarlo manualmente:"
            echo "  git clone https://github.com/retired64/opencode-termux.git"
            echo "  cd opencode-termux && bash install.sh"
            exit 1
        }
    done

    # Apuntar SCRIPT_DIR a donde se descargaron las libs
    # En modo standalone las libs quedan planas en OPENCODE_TMP (sin subdirectorio lib/)
    SCRIPT_DIR="${OPENCODE_TMP}"
    _flat_bootstrap  # usa source directo sin subdir lib/
}

# ── Bootstrap para libs descargadas en modo standalone (planas, sin lib/) ──
# Cuando se descargan via curl las libs van a $OPENCODE_TMP directamente,
# no a $OPENCODE_TMP/lib/, así que se sourcean desde el dir raíz.
_flat_bootstrap() {
    source "${SCRIPT_DIR}/env.sh"
    source "${SCRIPT_DIR}/colors.sh"
    source "${SCRIPT_DIR}/logging.sh"
    source "${SCRIPT_DIR}/deps.sh"
    source "${SCRIPT_DIR}/download.sh"
    source "${SCRIPT_DIR}/compile.sh"
}

# ── Modo clonado: source directo desde el repo ────
# Se activa cuando el usuario clonó el repo y ejecuta bash install.sh.
# BASH_SOURCE[0] sí está definido y SCRIPT_DIR apunta al repo.
_cloned_bootstrap() {
    source "${SCRIPT_DIR}/lib/env.sh"
    source "${SCRIPT_DIR}/lib/colors.sh"
    source "${SCRIPT_DIR}/lib/logging.sh"
    source "${SCRIPT_DIR}/lib/deps.sh"
    source "${SCRIPT_DIR}/lib/download.sh"
    source "${SCRIPT_DIR}/lib/compile.sh"
}

# ── Detecta si ya hay una instalación previa ──────
_check_existing() {
    if [[ -x "$OPENCODE_BOOTSTRAPPER" ]]; then
        log_warn "OpenCode ya está instalado en ${OPENCODE_BOOTSTRAPPER}"
        if [[ -f "${OT_DATA_DIR}/.version" ]]; then
            log_info "Versión instalada: $(cat "${OT_DATA_DIR}/.version")"
        fi
        echo ""
        echo -n "  ¿Desea reinstalar? [s/N]: "
        read -r answer
        if [[ ! "$answer" =~ ^[sSyY]$ ]]; then
            log_info "Instalación cancelada"
            exit 0
        fi
    fi
}

# ── Flujo principal ───────────────────────────────
_main() {
    show_banner

    _check_existing

    log_title "Paso 1/4: Verificando arquitectura"
    check_architecture || exit 1

    log_title "Paso 2/4: Instalando dependencias"
    install_glibc || exit 1
    install_user_deps || exit 1

    log_title "Paso 3/4: Descargando OpenCode"
    download_opencode || exit 1

    log_title "Paso 4/4: Compilando bootstrapper"
    compile_bootstrapper || exit 1
    verify_bootstrapper || exit 1

    echo ""
    log_ok "╔══════════════════════════════════════════╗"
    log_ok "║  OpenCode instalado correctamente        ║"
    log_ok "║  Ejecuta: opencode --help                ║"
    log_ok "╚══════════════════════════════════════════╝"
    echo ""
}

# ── Bootstrap: detectar modo de ejecución ─────────
#
# CASO 1 - Repo clonado, libs en lib/:
#   bash install.sh  →  BASH_SOURCE[0]="install.sh", SCRIPT_DIR=directorio del repo
#
# CASO 2 - Libs copiadas junto a install.sh (sin subdirectorio):
#   Útil si el usuario copió archivos manualmente al mismo nivel
#
# CASO 3 - Pipe (curl | bash):
#   BASH_SOURCE[0] no definido → SCRIPT_DIR=""
#   No hay libs locales → descarga desde GitHub raw
#
if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/lib/env.sh" ]]; then
    # Caso 1: repo clonado con estructura lib/
    _cloned_bootstrap
    _main "$@"
elif [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/env.sh" ]]; then
    # Caso 2: libs planas junto a install.sh
    _flat_bootstrap
    _main "$@"
else
    # Caso 3: modo standalone via curl pipe, SCRIPT_DIR vacío o sin libs
    _standalone_bootstrap "https://raw.githubusercontent.com/retired64/opencode-termux/main"
    _main "$@"
fi

