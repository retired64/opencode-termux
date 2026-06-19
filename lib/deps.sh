#!/data/data/com.termux/files/usr/bin/bash

# ── Include guard ─────────────────────────────────
# deps.sh antes hacía source .../lib/env.sh y .../lib/logging.sh
# internamente con rutas hardcodeadas a /lib/, causando:
#   1. Doble source de variables readonly → error en bash
#   2. Rotura en modo standalone (libs sin subdir lib/)
# install.sh ya cargó env.sh, colors.sh y logging.sh antes
# de sourcear deps.sh, así que aquí no se necesitan.
[[ -n "${_OT_DEPS_LOADED:-}" ]] && return 0
readonly _OT_DEPS_LOADED=1

# ── Mapa de dependencias: paquete → binario verificador ──
# FIX CRÍTICO (scope): install.sh sourcea este archivo DENTRO de la
# función _cloned_bootstrap(). En bash, "declare -A" ejecutado en ese
# contexto crea la variable como LOCAL a esa función (el scope depende
# de dónde se EJECUTA el source, no de dónde está escrito el archivo).
# Al salir de _cloned_bootstrap, OT_DEPS desaparecía, y _main() veía
# un array vacío: el "for pkg in ${!OT_DEPS[@]}" nunca iteraba y el
# script reportaba "Todas las dependencias listas" sin haber verificado
# ni instalado nada (clang nunca se instalaba).
# "declare -gA" fuerza que el array sea global, sobreviviendo a la
# salida de la función donde fue sourceado.
declare -gA OT_DEPS=(
    ["git"]="git"
    ["ripgrep"]="rg"
    ["python"]="python"
    ["clang"]="clang"
    ["jq"]="jq"
    ["nodejs-lts"]="node"
    ["curl"]="curl"
    ["tar"]="tar"
)

# ── Verifica e instala glibc ──────────────────────
install_glibc() {
    log_info "Verificando glibc..."

    if [[ ! -f "$GLIBC_REPO_FILE" ]]; then
        log_info "Instalando glibc-repo..."
        if ! pkg install glibc-repo -y; then
            log_error "No se pudo instalar glibc-repo"
            return 1
        fi
    fi

    if [[ ! -f "$GLIBC_LIBC" ]]; then
        log_info "Instalando glibc..."
        if ! pkg install glibc -y; then
            log_error "No se pudo instalar glibc"
            return 1
        fi
    fi

    log_ok "glibc listo"
    return 0
}

# ── Verifica e instala dependencias de usuario ────
install_user_deps() {
    log_info "Verificando dependencias..."
    local missing=0

    for pkg in "${!OT_DEPS[@]}"; do
        local bin="${OT_DEPS[$pkg]}"
        if command -v "$bin" &>/dev/null; then
            log_ok "$pkg (ya instalado)"
        else
            log_info "Instalando $pkg..."
            # FIX: antes se silenciaba con &>/dev/null, lo que ocultaba
            # la causa real de un fallo (mirror caído, conflicto de
            # paquetes, falta de espacio, etc). Ahora se muestra el
            # output de pkg solo cuando falla, para poder diagnosticar.
            if pkg install "$pkg" -y; then
                log_ok "$pkg instalado"
            else
                log_error "Fallo al instalar $pkg"
                # FIX CRÍTICO (set -e): "((missing++))" con missing=0
                # evalúa la EXPRESIÓN PREVIA al incremento (post-incremento),
                # que es 0, y bash interpreta "expresión aritmética = 0"
                # como código de salida 1 (falso). Con "set -e" activo en
                # install.sh, eso mataba el script ahí mismo en el PRIMER
                # fallo, de forma silenciosa, sin llegar nunca al mensaje
                # "Faltan N dependencia(s)".
                # "missing=$((missing + 1))" es una asignación simple que
                # no falla por el valor resultante.
                missing=$((missing + 1))
            fi
        fi
    done

    if [[ $missing -gt 0 ]]; then
        log_error "Faltan $missing dependencia(s)"
        return 1
    fi

    log_ok "Todas las dependencias listas"
    return 0
}

# ── Verifica arquitectura ─────────────────────────
check_architecture() {
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "aarch64" ]]; then
        log_error "Arquitectura no soportada: $arch"
        log_error "opencode-termux solo funciona en aarch64 (ARM64)"
        log_info "Tu arquitectura: $arch"
        return 1
    fi
    log_ok "Arquitectura: aarch64"
    return 0
}

# ── Punto de entrada único ────────────────────────
verify_all_deps() {
    check_architecture || return 1
    install_glibc || return 1
    install_user_deps || return 1
    return 0
}

