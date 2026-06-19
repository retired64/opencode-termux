#!/data/data/com.termux/files/usr/bin/bash
# shellcheck disable=SC2034

# ── Include guard ─────────────────────────────────
# env.sh define variables readonly: si se sourcea dos veces
# (desde install.sh y luego desde deps.sh/download.sh/compile.sh)
# bash lanza error. El guard lo evita.
[[ -n "${_OT_ENV_LOADED:-}" ]] && return 0
readonly _OT_ENV_LOADED=1

# ── Versión del instalador ─────────────────────────
readonly OT_VERSION="1.0.0"

# ── Rutas de Termux ───────────────────────────────
readonly PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
readonly HOME_DIR="${HOME:-/data/data/com.termux/files/home}"

# ── Rutas de opencode-termux ──────────────────────
readonly OT_DATA_DIR="${XDG_DATA_HOME:-$HOME_DIR/.local/share}/opencode-termux"
readonly OT_BIN_DIR="${OT_DATA_DIR}/bin"
readonly OT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME_DIR/.cache}/opencode-termux"

# ── Ruta del binario real de OpenCode ─────────────
readonly OPENCODE_REAL_BIN="${OT_BIN_DIR}/opencode"

# ── Ruta de instalación del bootstrapper ──────────
readonly OPENCODE_BOOTSTRAPPER="${PREFIX}/bin/opencode"

# ── Rutas de glibc ────────────────────────────────
readonly GLIBC_LOADER="${PREFIX}/glibc/lib/ld-linux-aarch64.so.1"
readonly GLIBC_LIB_PATH="${PREFIX}/glibc/lib"
readonly GLIBC_LIBC="${GLIBC_LIB_PATH}/libc.so.6"
readonly GLIBC_REPO_FILE="${PREFIX}/etc/apt/sources.list.d/glibc.list"

# ── Certificado SSL de Termux ─────────────────────
readonly SSL_CERT_FILE="${PREFIX}/etc/tls/cert.pem"

# ── GitHub API ────────────────────────────────────
readonly OPENCODE_REPO="anomalyco/opencode"
readonly OPENCODE_API="https://api.github.com/repos/${OPENCODE_REPO}/releases/latest"
readonly OPENCODE_DOWNLOAD="https://github.com/${OPENCODE_REPO}/releases/download"

# ── Nombre del tarball (arquitectura fija: arm64) ─
readonly TARBALL_NAME="opencode-linux-arm64.tar.gz"

# ── URLs del instalador ───────────────────────────
readonly OT_REPO="retired64/opencode-termux"
readonly OT_RAW="https://raw.githubusercontent.com/${OT_REPO}/main"

