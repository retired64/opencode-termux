> Arquitectura detallada, decisiones de diseño y convenciones de código.
> Referenciado desde `AGENTS.md`. Leer completo antes de tocar `install.sh`, cualquier `lib/*.sh`, o el helper C.

---

## 1. Qué es este proyecto

**opencode-termux** es un instalador shell (bash) para correr el binario **OpenCode** (CLI de IA tipo agent, repo `anomalyco/opencode`) dentro de **Termux** en Android (**arquitectura aarch64 únicamente**).

El problema central que resuelve: el binario de OpenCode está compilado contra **glibc**, pero Termux usa **bionic/musl-like** nativo y no tiene glibc por defecto. La solución es:

1. Instalar `glibc` vía `pkg install glibc-repo glibc` (paquete de terceros para Termux).
2. Descargar el último release de OpenCode desde GitHub (`anomalyco/opencode`, tarball `opencode-linux-arm64.tar.gz`).
3. Compilar un **bootstrapper en C** (`src/opencode_helper.c`) que se instala como `$PREFIX/bin/opencode` y que en runtime hace `execv()` del binario real de OpenCode a través del **loader de glibc** (`ld-linux-aarch64.so.1 --library-path <glibc_lib> <bin_real>`), limpiando `LD_PRELOAD`/`LD_LIBRARY_PATH` y fijando `SSL_CERT_FILE` al certificado de Termux.

Es decir: `opencode` en el PATH del usuario no es OpenCode — es un wrapper C de ~40 líneas que reejecuta el OpenCode real bajo glibc.

- **Versión actual**: `1.0.0` (ver `VERSION` y `OT_VERSION` en `lib/env.sh`, deben mantenerse sincronizados manualmente — runbook 13.5).
- **Repo del proyecto**: `retired64/opencode-termux` (GitHub).
- **Repo de OpenCode (upstream)**: `anomalyco/opencode`.
- **Audiencia**: usuarios de Termux en Android ARM64 que quieren correr OpenCode.

---

## 2. Estructura real del repositorio

```
.
├── install.sh              # Entry point principal — detecta modo de ejecución y orquesta todo
├── update.sh                # Solo modo clonado. Chequea y aplica updates de OpenCode
├── uninstall.sh             # Standalone total, sin dependencias de lib/
├── VERSION                  # "1.0.0" — versión del proyecto (texto plano)
├── src/
│   └── opencode_helper.c    # Fuente canónica del bootstrapper C
└── lib/
    ├── env.sh               # Variables readonly: rutas, URLs, nombres de paquete
    ├── colors.sh            # Códigos ANSI + alias semánticos (CLR_OK, CLR_ERROR, ...)
    ├── logging.sh           # log_info/log_ok/log_warn/log_error/log_title + banner + progress_bar
    ├── deps.sh              # Verificación de arquitectura, glibc y dependencias de usuario (pkg)
    ├── download.sh          # Resolución de última versión + descarga/extracción del tarball
    └── compile.sh           # Compilación del bootstrapper C con clang
```

`src/opencode_helper.c` es la fuente canónica y se usa en **modo clonado y modo flat** (cuando `$SCRIPT_DIR/src/opencode_helper.c` existe). `lib/compile.sh::write_embedded_helper()` mantiene una **segunda copia textual** del mismo código embebida en un heredoc, que se usa exclusivamente como fallback en **modo standalone** (`curl | bash`), donde no existe ningún `src/` local. Estas dos copias **deben ser idénticas en todo momento** — protocolo obligatorio en `docs/runbooks.md` §13.1.

---

## 3. Los tres modos de bootstrap (lo más importante de entender)

`install.sh` se autodetecta y bifurca en 3 escenarios mutuamente excluyentes, resueltos al final del archivo (líneas ~111-136):

| Modo | Cómo se invoca | `BASH_SOURCE[0]` | Origen de las libs | Origen del helper C |
|---|---|---|---|---|
| **Cloned** | `git clone ... && bash install.sh` | definido | `$SCRIPT_DIR/lib/*.sh` | `$SCRIPT_DIR/src/opencode_helper.c` |
| **Flat** | libs copiadas manualmente junto a `install.sh` (sin subdir) | definido | `$SCRIPT_DIR/*.sh` | `$SCRIPT_DIR/src/opencode_helper.c` (si existe) |
| **Standalone (pipe)** | `curl -fsSL .../install.sh \| bash` | **no definido** (pipe a stdin) | descarga cada lib desde `raw.githubusercontent.com/.../main/lib/*.sh` a `$TMPDIR/opencode-termux-lib/` | heredoc embebido en `compile.sh` (no se descarga `src/`) |

**Por qué esto importa para cualquier cambio**: si agregás una nueva lib (`lib/nueva.sh`), tenés que tocar los 3 modos — ver runbook 13.3 en `docs/runbooks.md`.

`uninstall.sh` es la excepción: es 100% autocontenido, no sourcea nada de `lib/`, recalcula las rutas inline. Si cambiás convenciones de rutas en `env.sh`, **hay que replicar el cambio a mano en `uninstall.sh`** (runbook 13.4).

---

## 4. Convención de include guards (no romper esto)

Cada archivo de `lib/` tiene un guard al estilo:

```bash
[[ -n "${_OT_<NOMBRE>_LOADED:-}" ]] && return 0
readonly _OT_<NOMBRE>_LOADED=1
```

Esto existe porque casi todas las variables en `env.sh` y `colors.sh` son `readonly`, y bash lanza error fatal si se intenta reasignar una `readonly` (típicamente al sourcear el mismo archivo dos veces). Los comentarios en el código documentan que **esto ya fue un bug real** (logging.sh hacía `source .../lib/colors.sh` internamente con ruta hardcodeada, rompiendo modo standalone y duplicando sources).

**Regla para cualquier archivo nuevo en `lib/`:**
- Debe llevar su propio guard único (`_OT_<NOMBRE>_LOADED`).
- **No debe** hacer `source` de otras libs internamente — el orden de carga es responsabilidad exclusiva de quien lo invoca (`install.sh`/`update.sh`), nunca del archivo en sí. Esto es explícito y deliberado, no un descuido.

---

## 5. Bugs ya corregidos — no los reintroduzcas

El código tiene comentarios `FIX` extensos documentando bugs reales ya resueltos. Son la mejor fuente de "qué no hacer":

1. **`BASH_SOURCE[0]` unbound en pipe** (`install.sh`): usar siempre `${BASH_SOURCE[0]:-}` con fallback, nunca `${BASH_SOURCE[0]}` a secas.
2. **`/tmp` no existe/no es escribible en Termux**: usar siempre `${TMPDIR:-${PREFIX}/tmp}`, nunca hardcodear `/tmp`.
3. **`declare -A` dentro de función = scope local** (`deps.sh`, `OT_DEPS`): si un array necesita sobrevivir al `return` de la función donde se sourcea el archivo, hay que usar `declare -gA`, no `declare -A`. Esto causó que `clang` nunca se instalara y el script reportara éxito falso.
4. **Post-incremento en aritmética con `set -e`** (`deps.sh`): `((missing++))` con `missing=0` devuelve código de salida 1 (porque evalúa el valor *antes* del incremento, que es `0` = falso), matando el script silenciosamente bajo `set -euo pipefail`. Usar siempre `missing=$((missing + 1))`.
5. **Rutas hardcodeadas a `/lib/` dentro de las propias libs** (`deps.sh`, `download.sh`, `compile.sh`, `logging.sh`): rompía el modo standalone (libs planas sin subdirectorio `lib/`). Las libs **nunca** deben sourcear nada por su cuenta.
6. **`pkg install` silenciado con `&>/dev/null`**: ocultaba la causa real de fallos (mirror caído, falta de espacio, conflicto de paquetes). Ahora el output se muestra solo si falla.

Si tu cambio reintroduce cualquiera de estos patrones, es casi seguro una regresión.

---

## 6. Variables de entorno y rutas clave (`lib/env.sh`)

Todo lo "constante" del proyecto vive acá, como `readonly`. Si necesitás una ruta nueva, agregala aquí — **no la hardcodees en otro archivo** (excepto `uninstall.sh`, que es deliberadamente autocontenido, y el helper C, que no puede leer bash en runtime).

| Variable | Valor / propósito |
|---|---|
| `PREFIX` | Raíz de Termux (`/data/data/com.termux/files/usr`) |
| `HOME_DIR` | Home de Termux |
| `OT_DATA_DIR` | `~/.local/share/opencode-termux` — binario real + `.version` |
| `OT_BIN_DIR` | `$OT_DATA_DIR/bin` |
| `OT_CACHE_DIR` | `~/.cache/opencode-termux` — tarballs temporales, fuente embebida |
| `OPENCODE_REAL_BIN` | `$OT_BIN_DIR/opencode` — el binario glibc real |
| `OPENCODE_BOOTSTRAPPER` | `$PREFIX/bin/opencode` — el wrapper C, lo que el usuario ejecuta |
| `GLIBC_LOADER` | `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` |
| `GLIBC_LIB_PATH` / `GLIBC_LIBC` | Librería y verificación de glibc instalado |
| `SSL_CERT_FILE` | `$PREFIX/etc/tls/cert.pem` — certs de Termux, inyectado en runtime por el helper C |
| `OPENCODE_REPO` / `OPENCODE_API` / `OPENCODE_DOWNLOAD` | `anomalyco/opencode`, GitHub Releases API, base URL de descarga |
| `TARBALL_NAME` | `opencode-linux-arm64.tar.gz` (**arquitectura fija**, no parametrizada) |
| `OT_REPO` / `OT_RAW` | `retired64/opencode-termux`, raw.githubusercontent base |

⚠️ El helper C (`src/opencode_helper.c`) tiene **estas mismas rutas hardcodeadas como strings literales** (no las lee de env), porque es un binario compilado independiente del shell. Si cambiás `OT_BIN_DIR`, `GLIBC_LOADER` o `SSL_CERT_FILE` en `env.sh`, **tenés que actualizar manualmente el `.c` en dos lugares**: `src/opencode_helper.c` y el heredoc embebido en `lib/compile.sh::write_embedded_helper()`. Runbook 13.1 en `docs/runbooks.md`.

---

## 7. Flujo de `install.sh` (4 pasos)

```
1/4  check_architecture          → exige aarch64, aborta en cualquier otra arch
2/4  install_glibc                → pkg install glibc-repo, glibc
     install_user_deps            → git, ripgrep, python, clang, jq, nodejs-lts, curl, tar
3/4  download_opencode            → resuelve última release vía GitHub API, descarga tarball, extrae
4/4  compile_bootstrapper         → clang -O2 sobre src/opencode_helper.c → $PREFIX/bin/opencode
     verify_bootstrapper          → chequea que sea ejecutable
```

`_check_existing()` detecta instalación previa (`-x $OPENCODE_BOOTSTRAPPER`) y pide confirmación interactiva (`[s/N]`) antes de reinstalar — acepta `s/S/y/Y` (es bilingüe ES/EN en el regex, intencional).

**Dependencias de usuario** (`OT_DEPS` en `deps.sh`) — mapa paquete→binario verificador:
`git`, `ripgrep`(`rg`), `python`, `clang`, `jq`, `nodejs-lts`(`node`), `curl`, `tar`.

---

## 8. Convenciones de código a respetar

- **Shebang fijo**: `#!/data/data/com.termux/files/usr/bin/bash` en todos los scripts (ruta absoluta de Termux, no `#!/bin/bash` ni `#!/usr/bin/env bash`). Es deliberado: Termux no tiene `/bin/bash`.
- **`set -euo pipefail`** en los entry points (`install.sh`, `update.sh`), pero **no** en las libs de `lib/` (porque se sourcean, no se ejecutan — un `exit` ahí mataría el shell padre). Si agregás una lib nueva, no le pongas `set -e`.
- **Idioma**: todos los mensajes de usuario, comentarios y logs están en **español**. Mantener consistencia — no mezclar inglés en strings visibles al usuario.
- **Logging**: nunca usar `echo` plano para mensajes de estado — usar siempre `log_info/log_ok/log_warn/log_error/log_title` de `logging.sh` (excepción: `uninstall.sh`, que es autocontenido y usa `echo` con símbolos inline a propósito).
- **Funciones devuelven código de salida**, no imprimen y abortan: el patrón estándar es `funcion || return 1` / `funcion || exit 1`, permitiendo testear funciones individualmente.
- **Nomenclatura de funciones privadas**: prefijo `_` para funciones internas de `install.sh` (`_main`, `_check_existing`, `_cloned_bootstrap`, etc.) que no están pensadas para llamarse desde otros archivos.
- **Prefijo `OT_`** para todo lo namespaced del proyecto (evita colisión con variables de Termux/usuario): `OT_VERSION`, `OT_DATA_DIR`, `OT_DEPS`, `OT_REPO`, etc.

Estas convenciones derivan directamente de la filosofía del proyecto (ver `AGENTS.md` §2: compatibilidad con Termux, simplicidad, dependencias mínimas, robustez, bash explícito).

