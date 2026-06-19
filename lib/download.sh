#!/data/data/com.termux/files/usr/bin/bash

# ── Include guard ─────────────────────────────────
# Mismo problema que deps.sh: source interno de env.sh y logging.sh
# con ruta hardcodeada /lib/ → doble source → error readonly.
# install.sh ya cargó todo lo necesario antes de llegar aquí.
[[ -n "${_OT_DOWNLOAD_LOADED:-}" ]] && return 0
readonly _OT_DOWNLOAD_LOADED=1

# ── Obtiene la última versión de OpenCode ─────────
get_latest_version() {
    local version
    version=$(curl -fsSL "$OPENCODE_API" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$version" ]]; then
        log_error "No se pudo obtener la última versión de OpenCode"
        log_error "Verifica tu conexión a internet y que GitHub sea accesible"
        return 1
    fi
    echo "$version"
}

# ── Descarga y extrae el binario ──────────────────
download_opencode() {
    local version
    version=$(get_latest_version) || return 1

    log_info "Última versión de OpenCode: ${CLR_BOLD}${version}${CLR_RESET}"

    local url="${OPENCODE_DOWNLOAD}/${version}/${TARBALL_NAME}"
    local tmp_tarball="${OT_CACHE_DIR}/${TARBALL_NAME}"

    mkdir -p "$OT_CACHE_DIR" "$OT_BIN_DIR"

    log_info "Descargando OpenCode..."
    if ! curl -fsSL --progress-bar "$url" -o "$tmp_tarball"; then
        log_error "Fallo al descargar OpenCode desde:"
        log_error "  $url"
        return 1
    fi
    log_ok "Descarga completada"

    log_info "Extrayendo binario..."
    if ! tar -zxf "$tmp_tarball" -C "$OT_BIN_DIR"; then
        log_error "Fallo al extraer el tarball"
        rm -f "$tmp_tarball"
        return 1
    fi

    rm -f "$tmp_tarball"

    if [[ ! -f "$OPENCODE_REAL_BIN" ]]; then
        log_error "Binario de OpenCode no encontrado tras extracción"
        log_error "Contenido de ${OT_BIN_DIR}:"
        ls -la "$OT_BIN_DIR"
        return 1
    fi

    chmod +x "$OPENCODE_REAL_BIN"

    # Guardar versión instalada para futuras comparaciones
    echo "$version" >"${OT_DATA_DIR}/.version"

    log_ok "OpenCode ${version} instalado en ${OT_BIN_DIR}"
    return 0
}

# ── Verifica si hay nueva versión disponible ──────
check_for_updates() {
    local current latest

    if [[ -f "${OT_DATA_DIR}/.version" ]]; then
        current=$(cat "${OT_DATA_DIR}/.version")
    else
        log_warn "No se encontró registro de versión instalada"
        return 1
    fi

    latest=$(get_latest_version) || return 1

    if [[ "$current" != "$latest" ]]; then
        log_info "Nueva versión disponible: ${CLR_BOLD}${latest}${CLR_RESET} (actual: ${CLR_DIM}${current}${CLR_RESET})"
        return 0
    else
        log_ok "OpenCode ya está en la última versión (${current})"
        return 1
    fi
}
