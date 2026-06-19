#!/data/data/com.termux/files/usr/bin/bash

# ── Include guard ─────────────────────────────────
# Mismo problema que deps.sh y download.sh: source interno
# con /lib/ hardcodeado → doble source → error readonly.
[[ -n "${_OT_COMPILE_LOADED:-}" ]] && return 0
readonly _OT_COMPILE_LOADED=1

# ── Ruta al helper C ──────────────────────────────
# SCRIPT_DIR se hereda del entorno de install.sh.
# En modo clonado apunta al repo; en modo standalone
# apunta a $TMPDIR/opencode-termux-lib donde se
# descargaron las libs. El .c vive en src/ solo en
# el repo clonado; en standalone se usa el fallback embebido.
HELPER_SRC="${SCRIPT_DIR}/src/opencode_helper.c"

# ── Compila el bootstrapper ───────────────────────
compile_bootstrapper() {
    log_info "Compilando bootstrapper C..."

    if [[ ! -f "$HELPER_SRC" ]]; then
        log_warn "Fuente no encontrada en ${HELPER_SRC}, usando fuente embebida"
        write_embedded_helper || return 1
    fi

    if ! command -v clang &>/dev/null; then
        log_error "clang no está instalado. Ejecuta primero la verificación de dependencias."
        return 1
    fi

    if clang -O2 -o "$OPENCODE_BOOTSTRAPPER" "$HELPER_SRC"; then
        chmod +x "$OPENCODE_BOOTSTRAPPER"
        log_ok "Bootstrapper compilado: ${OPENCODE_BOOTSTRAPPER}"
        return 0
    else
        log_error "Fallo la compilación del bootstrapper"
        return 1
    fi
}

# ── Escribe el código C embebido (fallback) ───────
# Se usa cuando no existe src/opencode_helper.c (modo standalone).
# Usa $OT_CACHE_DIR en lugar de /tmp (no existe en Termux).
write_embedded_helper() {
    local tmp_src="${OT_CACHE_DIR}/opencode_helper.c"
    mkdir -p "$OT_CACHE_DIR"

    cat >"$tmp_src" <<'OPENCODE_HELPER_EOF'
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>

int main(int argc, char** argv) {
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");

    setenv("GODEBUG", "netdns=cgo", 1);
    setenv("SSL_CERT_FILE", "/data/data/com.termux/files/usr/etc/tls/cert.pem", 1);

    char exec_path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exec_path, sizeof(exec_path) - 1);
    if (len == -1) return 1;
    exec_path[len] = '\0';

    char* loader = "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1";
    char real_bin[] = "/data/data/com.termux/files/home/.local/share/opencode-termux/bin/opencode";
    char lib_path[] = "/data/data/com.termux/files/usr/glibc/lib";

    char** new_argv = malloc((argc + 4) * sizeof(char*));
    if (!new_argv) return 1;

    new_argv[0] = loader;
    new_argv[1] = "--library-path";
    new_argv[2] = lib_path;
    new_argv[3] = real_bin;

    for (int i = 1; i < argc; i++)
        new_argv[i + 3] = argv[i];
    new_argv[argc + 3] = NULL;

    execv(loader, new_argv);
    perror("execv");
    free(new_argv);
    return 1;
}
OPENCODE_HELPER_EOF

    HELPER_SRC="$tmp_src"
    return 0
}

# ── Verifica que el bootstrapper funciona ─────────
verify_bootstrapper() {
    if [[ -x "$OPENCODE_BOOTSTRAPPER" ]]; then
        log_ok "Bootstrapper verificado"
        return 0
    else
        log_error "Bootstrapper no es ejecutable"
        return 1
    fi
}

