#!/data/data/com.termux/files/usr/bin/bash
# shellcheck disable=SC2034

# ── Include guard ─────────────────────────────────
# Evita redefinir readonly vars si este archivo ya fue
# sourceado (ocurre cuando logging.sh, deps.sh, etc.
# son cargados después de que install.sh ya lo cargó).
[[ -n "${_OT_COLORS_LOADED:-}" ]] && return 0
readonly _OT_COLORS_LOADED=1

# ── Colores ANSI ──────────────────────────────────
readonly CLR_RESET='\e[0m'
readonly CLR_BOLD='\e[1m'
readonly CLR_DIM='\e[2m'

readonly CLR_RED='\e[31m'
readonly CLR_GREEN='\e[32m'
readonly CLR_YELLOW='\e[33m'
readonly CLR_BLUE='\e[34m'
readonly CLR_CYAN='\e[36m'
readonly CLR_WHITE='\e[37m'

# ── Semánticos ────────────────────────────────────
readonly CLR_OK="${CLR_GREEN}"
readonly CLR_ERROR="${CLR_RED}${CLR_BOLD}"
readonly CLR_WARN="${CLR_YELLOW}"
readonly CLR_INFO="${CLR_CYAN}"
readonly CLR_TITLE="${CLR_BLUE}${CLR_BOLD}"
