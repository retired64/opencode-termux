#!/data/data/com.termux/files/usr/bin/bash

# ── Include guard ─────────────────────────────────
# logging.sh antes hacía source .../lib/colors.sh internamente
# con ruta hardcodeada a /lib/, lo que:
#   1. Rompía el modo standalone (libs planas, sin subdir lib/)
#   2. Causaba doble source de colors.sh → error "readonly variable"
# Solución: NO sourcea colors.sh aquí. install.sh ya lo cargó
# antes de cargar logging.sh, y colors.sh tiene su propio guard.
[[ -n "${_OT_LOGGING_LOADED:-}" ]] && return 0
readonly _OT_LOGGING_LOADED=1

# ── Funciones de logging ──────────────────────────
log_info()  { echo -e "  ${CLR_INFO}→${CLR_RESET}  $*"; }
log_ok()    { echo -e "  ${CLR_OK}✔${CLR_RESET}  $*"; }
log_warn()  { echo -e "  ${CLR_WARN}⚠${CLR_RESET}  $*"; }
log_error() { echo -e "  ${CLR_ERROR}✖${CLR_RESET}  $*" >&2; }
log_title() { echo -e "\n  ${CLR_TITLE}◆  $*${CLR_RESET}\n"; }

# ── Barra de progreso simple ──────────────────────
progress_bar() {
    local current="$1" total="$2" width="${3:-30}"
    local pct=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    printf "\r  ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%" "$pct"
}

# ── Banner ────────────────────────────────────────
show_banner() {
    echo
    echo -e "  ${CLR_TITLE}╔══════════════════════════════════════╗${CLR_RESET}"
    echo -e "  ${CLR_TITLE}║${CLR_RESET}     OpenCode Termux Installer      ${CLR_TITLE}║${CLR_RESET}"
    echo -e "  ${CLR_TITLE}║${CLR_RESET}   Native glibc + C bootstrapper    ${CLR_TITLE}║${CLR_RESET}"
    echo -e "  ${CLR_TITLE}╚══════════════════════════════════════╝${CLR_RESET}"
    echo -e "  ${CLR_DIM}v${OT_VERSION}  |  github.com/retired64/opencode-termux${CLR_RESET}"
    echo
}

