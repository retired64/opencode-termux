# Developer Helper: opencode-termux

> Guía técnica exhaustiva para mantener, versionar y publicar `opencode-termux`.  
> Repositorio: `https://github.com/retired64/opencode-termux.git`

---

## Índice

1. [Arquitectura interna del instalador](#1-arquitectura-interna-del-instalador)
2. [Modos de ejecución (cloned vs standalone)](#2-modos-de-ejecución-cloned-vs-standalone)
3. [Namespace OT_\* y rutas](#3-namespace-ot_-y-rutas)
4. [Flujo de instalación completo (trace)](#4-flujo-de-instalación-completo-trace)
5. [Bootstrapper C: cadena de compilación y ejecución](#5-bootstrapper-c-cadena-de-compilación-y-ejecución)
6. [Mecanismo de versionado del instalador](#6-mecanismo-de-versionado-del-instalador)
7. [Procedimiento para sacar una nueva release](#7-procedimiento-para-sacar-una-nueva-release)
8. [Procedimiento para actualizar dependencias](#8-procedimiento-para-actualizar-dependencias)
9. [Pruebas locales (sin publicar)](#9-pruebas-locales-sin-publicar)
10. [CI/CD: GitHub Actions explicado](#10-cicd-github-actions-explicado)
11. [Puntos de fallo y monitoreo](#11-puntos-de-fallo-y-monitoreo)
12. [Cómo modificar el bootstrapper C](#12-cómo-modificar-el-bootstrapper-c)
13. [Script de release automatizado](#13-script-de-release-automatizado)
14. [Script de verificación pre-release](#14-script-de-verificación-pre-release)

---

## 1. Arquitectura interna del instalador

### 1.1 Grafo de dependencias entre archivos

```
install.sh ────────────────────────────────────────────
  │
  │ detecta modo
  │
  ├─ [CLONED]: source "${SCRIPT_DIR}/lib/*.sh"
  │
  └─ [STANDALONE]: curl descarga libs desde GitHub raw
                    a /tmp/opencode-termux-lib/
                    luego source igual que CLONED
  │
  ├── lib/env.sh        (constantes puras, sin side-effects)
  ├── lib/colors.sh     (variables readonly ANSI)
  ├── lib/logging.sh ───┤ source lib/colors.sh
  │                      │ usa ${OT_VERSION} de lib/env.sh
  ├── lib/deps.sh ──────┤ source lib/env.sh, lib/logging.sh
  │                      │ declara -A OT_DEPS
  │                      │ check_architecture()
  │                      │ install_glibc()
  │                      │ install_user_deps()
  ├── lib/download.sh ──┤ source lib/env.sh, lib/logging.sh
  │                      │ get_latest_version()
  │                      │ download_opencode()
  │                      │ check_for_updates()
  └── lib/compile.sh ───┤ source lib/env.sh, lib/logging.sh
                         │ compile_bootstrapper()
                         │ write_embedded_helper()
                         │ verify_bootstrapper()

update.sh ─────────────────────────────────────────────
  ├── lib/env.sh
  ├── lib/logging.sh
  ├── lib/download.sh     (check_for_updates + download_opencode)
  └── lib/compile.sh      (compile_bootstrapper)

uninstall.sh ──────────────────────────────────────────
  (autocontenido, no sourcea lib/ para ser ejecutable
   incluso si el repo fue borrado)
```

### 1.2 Cada archivo es sourceable independientemente

Todos los `lib/*.sh` usan `source "${SCRIPT_DIR}/lib/..."` donde `SCRIPT_DIR` se define en el script que los invoca (`install.sh`, `update.sh`). Esto permite que cada archivo de `lib/` sea testeable individualmente si defines `SCRIPT_DIR` manualmente:

```bash
SCRIPT_DIR="$(pwd)" source lib/env.sh
echo "$OT_VERSION"  # 1.0.0
```

---

## 2. Modos de ejecución (cloned vs standalone)

### 2.1 Detección de modo

En `install.sh:95-106`:

```bash
if [[ -f "${SCRIPT_DIR}/lib/env.sh" ]]; then
    _cloned_bootstrap     # Modo clonado
elif [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
    _cloned_bootstrap     # Caso borde: libs copiadas junto a install.sh
else
    _standalone_bootstrap "https://raw.githubusercontent.com/retired64/opencode-termux/main"
fi
```

**Modo clonado:** El usuario hizo `git clone` y ejecuta `bash install.sh` desde el directorio del repo. `SCRIPT_DIR` apunta al root del repo y `lib/env.sh` existe → source directo.

**Modo standalone:** El usuario hizo `curl ... | bash`. El script se ejecuta desde `bash` stdin. `SCRIPT_DIR` es `/tmp` o `/data/data/com.termux/files/home`. No hay `lib/` → descarga cada archivo `.sh` desde GitHub raw a `/tmp/opencode-termux-lib/`.

### 2.2 ¿Por qué standalone descarga en lugar de embeber?

Embeber todo como heredocs haría `install.sh` tener ~400 líneas. Separar en descarga mantiene:
- El archivo `install.sh` pequeño y auditable (~80 líneas)
- Las libs se descargan individualmente → si falla una, el error es claro
- Las libs pueden tener su propio versionado

### 2.3 Flujo standalone en detalle

```
1. Usuario ejecuta: curl ... | bash
2. bash recibe install.sh por stdin, SCRIPT_DIR es /tmp o $HOME
3. _standalone_bootstrap se activa porque no encuentra lib/env.sh
4. Crea /tmp/opencode-termux-lib/
5. Descarga secuencialmente:
   curl -fsSL raw.../lib/env.sh       -o /tmp/.../env.sh
   curl -fsSL raw.../lib/colors.sh    -o /tmp/.../colors.sh
   curl -fsSL raw.../lib/logging.sh   -o /tmp/.../logging.sh
   curl -fsSL raw.../lib/deps.sh      -o /tmp/.../deps.sh
   curl -fsSL raw.../lib/download.sh  -o /tmp/.../download.sh
   curl -fsSL raw.../lib/compile.sh   -o /tmp/.../compile.sh
6. Si alguna descarga falla → mensaje de error + sugerencia de clonar
7. SCRIPT_DIR se reasigna a /tmp/opencode-termux-lib/
8. _cloned_bootstrap se ejecuta normalmente con las libs descargadas
```

---

## 3. Namespace OT_\* y rutas

### 3.1 Todas las constantes definidas en `lib/env.sh`

| Variable               | Valor                                                       | Categoría      |
|------------------------|-------------------------------------------------------------|----------------|
| `OT_VERSION`           | `1.0.0`                                                     | Versión        |
| `OT_DATA_DIR`          | `~/.local/share/opencode-termux`                             | Datos          |
| `OT_BIN_DIR`           | `$OT_DATA_DIR/bin`                                          | Binarios       |
| `OT_CACHE_DIR`         | `~/.cache/opencode-termux`                                   | Cache          |
| `OPENCODE_REAL_BIN`    | `$OT_BIN_DIR/opencode`                                      | Binario real   |
| `OPENCODE_BOOTSTRAPPER`| `$PREFIX/bin/opencode`                                      | Bootstrapper   |
| `GLIBC_LOADER`         | `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`                   | glibc          |
| `GLIBC_LIB_PATH`       | `$PREFIX/glibc/lib`                                         | glibc          |
| `GLIBC_LIBC`           | `$GLIBC_LIB_PATH/libc.so.6`                                 | glibc          |
| `GLIBC_REPO_FILE`      | `$PREFIX/etc/apt/sources.list.d/glibc.list`                 | glibc          |
| `SSL_CERT_FILE`        | `$PREFIX/etc/tls/cert.pem`                                  | SSL            |
| `OPENCODE_REPO`        | `anomalyco/opencode`                                        | Upstream       |
| `OPENCODE_API`         | `https://api.github.com/repos/anomalyco/opencode/releases/latest` | Upstream |
| `OPENCODE_DOWNLOAD`    | `https://github.com/anomalyco/opencode/releases/download`   | Upstream       |
| `TARBALL_NAME`         | `opencode-linux-arm64.tar.gz`                               | Upstream       |
| `OT_REPO`              | `retired64/opencode-termux`                                 | Auto-ref       |
| `OT_RAW`               | `https://raw.githubusercontent.com/retired64/opencode-termux/main` | Auto-ref |

### 3.2 Reglas del namespace OT_\*

1. **Todo** lo interno de `opencode-termux` usa el prefijo `OT_` (OpenCode Termux).
2. Las rutas de Termux (`PREFIX`, `HOME_DIR`) no llevan prefijo porque son estándar.
3. Las rutas de glibc (`GLIBC_*`) no llevan `OT_` porque pertenecen al ecosistema Termux/glibc, no a este proyecto.
4. Las rutas de OpenCode upstream (`OPENCODE_*`) no llevan `OT_` porque apuntan a `anomalyco/opencode`.
5. Si en el futuro se añade una variable nueva, debe seguir este criterio.

---

## 4. Flujo de instalación completo (trace)

```
install.sh ejecutado
│
├─ set -euo pipefail                           # Strict mode
├─ SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")    # Resolver ruta propia
├─ _cloned_bootstrap o _standalone_bootstrap   # Cargar libs
│
├─ show_banner                                 # ASCII art + versión
├─ _check_existing                             # ¿Ya instalado? → preguntar
│
├─ log_title "Paso 1/4: Verificando arquitectura"
│   └─ check_architecture()
│       ├─ arch=$(uname -m)
│       ├─ ¿arch == "aarch64"?
│       │   ├─ SÍ → log_ok, return 0
│       │   └─ NO → log_error, return 1
│
├─ log_title "Paso 2/4: Instalando dependencias"
│   ├─ install_glibc()
│   │   ├─ ¿-f $GLIBC_REPO_FILE? → NO → pkg install glibc-repo -y
│   │   ├─ ¿-f $GLIBC_LIBC?      → NO → pkg install glibc -y
│   │   └─ log_ok, return 0
│   └─ install_user_deps()
│       ├─ Itera OT_DEPS (8 paquetes)
│       ├─ Para cada uno: ¿command -v $bin? → ya instalado : pkg install -y
│       └─ return 0 si todos OK
│
├─ log_title "Paso 3/4: Descargando OpenCode"
│   └─ download_opencode()
│       ├─ version=$(get_latest_version)
│       │   └─ curl API GitHub → grep tag_name → sed extrae versión
│       ├─ url = https://github.com/anomalyco/opencode/releases/download/$version/$TARBALL
│       ├─ mkdir -p $OT_CACHE_DIR $OT_BIN_DIR
│       ├─ curl -fsSL --progress-bar "$url" -o $OT_CACHE_DIR/$TARBALL
│       ├─ tar -zxf $tarball -C $OT_BIN_DIR
│       ├─ rm $tarball
│       ├─ chmod +x $OT_BIN_DIR/opencode
│       └─ echo "$version" > $OT_DATA_DIR/.version
│
├─ log_title "Paso 4/4: Compilando bootstrapper"
│   └─ compile_bootstrapper()
│       ├─ ¿-f $HELPER_SRC? → NO → write_embedded_helper()
│       │   └─ heredoc C → $OT_CACHE_DIR/opencode_helper.c
│       ├─ clang -O2 -o $PREFIX/bin/opencode $HELPER_SRC
│       ├─ chmod +x $PREFIX/bin/opencode
│       └─ verify_bootstrapper() → ¿-x $PREFIX/bin/opencode?
│
└─ Mensaje final: "OpenCode instalado correctamente"
```

---

## 5. Bootstrapper C: cadena de compilación y ejecución

### 5.1 Compilación

```bash
clang -O2 -o $PREFIX/bin/opencode src/opencode_helper.c
```

| Componente | Detalle |
|------------|---------|
| Compilador | `clang` (de `pkg install clang`) |
| Flags | `-O2` (optimización nivel 2, balance velocidad/tamaño) |
| `-o` | `$PREFIX/bin/opencode` (directamente al PATH de Termux) |
| Fuente | `src/opencode_helper.c` (52 líneas) |
| Linker | Enlazado dinámicamente contra Bionic (libc de Android) — por defecto |
| Tamaño | ~15-30 KB |

No se necesitan flags `-l` porque solo usa funciones de libc estándar (`unsetenv`, `setenv`, `readlink`, `malloc`, `execv`, `perror`).

### 5.2 Cadena de ejecución en runtime

```
$ opencode --help
    │
    ▼
/bin/bash ejecuta $PREFIX/bin/opencode
    │
    ▼
main(argc=2, argv=["opencode", "--help"])
    │
    ├─ unsetenv("LD_PRELOAD")           ← limpia Bionic preloads
    ├─ unsetenv("LD_LIBRARY_PATH")      ← limpia search paths Bionic
    ├─ setenv("GODEBUG", "netdns=cgo")  ← fuerza resolución DNS via cgo
    ├─ setenv("SSL_CERT_FILE", "...")   ← apunta al cert.pem de Termux
    │
    ├─ readlink("/proc/self/exe")       ← resuelve su propia ruta
    │   └─ resultado: "$PREFIX/bin/opencode"
    │   └─ dirname: "$PREFIX/bin" (no usado en la lógica actual)
    │
    ├─ Construye new_argv:
    │   [0] = "$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
    │   [1] = "--library-path"
    │   [2] = "$PREFIX/glibc/lib"
    │   [3] = "$HOME/.local/share/opencode-termux/bin/opencode"
    │   [4] = "--help"
    │   [5] = NULL
    │
    └─ execv(ld-linux-aarch64.so.1, new_argv)
            │
            ▼
       Dynamic linker glibc carga el binario real
            │
            ├─ Busca bibliotecas en $PREFIX/glibc/lib
            ├─ Resuelve símbolos: libc.so.6, libpthread.so.0, ...
            ├─ Mapea el binario opencode en memoria
            └─ Salta a _start del runtime de Go
                    │
                    ▼
               Go runtime inicializa
                    │
                    ├─ netdns=cgo → usa getaddrinfo() de glibc
                    ├─ SSL_CERT_FILE → verifica TLS con cert de Termux
                    └─ opencode procesa "--help"
```

### 5.3 Por qué `readlink("/proc/self/exe")` si no se usa el resultado

La variable `dir` obtenida con `dirname()` no se usa para construir la ruta al binario real. Existe porque:

1. La plantilla original de bootstrappers (claude_helper.c, mimocode_helper.c) la usaba para resolver rutas relativas en otros contextos.
2. Se mantiene como boilerplate por si en el futuro se quiere hacer resolución relativa (ej: si el bootstrapper y el binario real están en el mismo directorio).
3. No hace daño (el compilador optimiza la variable no usada con `-O2`, pero `-O2` no elimina llamadas a funciones con side-effects como `readlink`). Podría eliminarse si se quiere reducir 3 líneas.

### 5.4 Qué pasa si `execv` falla

```c
execv(loader, new_argv);  // Si esto retorna, es porque falló

perror("execv");           // Imprime: "execv: <razón del error>"
free(new_argv);            // Libera memoria (buena práctica)
return 1;                  // Código de salida ≠ 0
```

Posibles errores de `execv`:
- `ENOENT` (2): El dynamic linker no existe → glibc no instalado
- `EACCES` (13): El dynamic linker no tiene permisos de ejecución
- `ENOEXEC` (8): El archivo no es un ejecutable válido

---

## 6. Mecanismo de versionado del instalador

### 6.1 Archivo VERSION

```
1.0.0
```

Una sola línea. Sin `v` prefijo (el tag de git sí lleva `v`).

**Regla de incremento:**

| Tipo de cambio          | Bump     | Ejemplo     |
|-------------------------|----------|-------------|
| Hotfix (bug menor)      | PATCH    | 1.0.0→1.0.1 |
| Nueva funcionalidad     | MINOR    | 1.0.0→1.1.0 |
| Cambio incompatible     | MAJOR    | 1.0.0→2.0.0 |

**Ejemplos de breaking changes (MAJOR):**
- Cambiar estructura de directorios (`$OT_DATA_DIR` cambia de ruta)
- Cambiar nombres de funciones exportadas en `lib/`
- Dejar de soportar `aarch64` o añadir `x86_64`

**Ejemplos de minor changes (MINOR):**
- Nuevo flag en `install.sh` (`--no-confirm`, `--skip-deps`)
- Añadir `proot` mode como alternativa
- Nuevo script (`status.sh`, `info.sh`)

**Ejemplos de patch (PATCH):**
- Corregir bug en `download.sh` (URL mal formada)
- Mejorar mensajes de error
- Actualizar documentación interna

### 6.2 Dónde se usa OT_VERSION

1. **`lib/env.sh:4`** — Definición: `readonly OT_VERSION="1.0.0"`
2. **`lib/logging.sh:31`** — Banner: `v${OT_VERSION}`
3. **`VERSION`** — Archivo raíz (para CI y scripts de release)

**Regla de sincronización:** `lib/env.sh` y `VERSION` deben coincidir SIEMPRE. El script de release lo verifica automáticamente.

---

## 7. Procedimiento para sacar una nueva release

### 7.1 Checklist pre-release

```bash
# 1. Verificar que VERSION y lib/env.sh coinciden
grep "OT_VERSION" lib/env.sh | grep -o '"[^"]*"' | tr -d '"'
cat VERSION
# Deben ser idénticos

# 2. Verificar sintaxis de todos los scripts
for f in install.sh uninstall.sh update.sh lib/*.sh; do
    bash -n "$f" || { echo "ERROR en $f"; exit 1; }
done
echo "Sintaxis OK"

# 3. Verificar independencia de core-termux
grep -rn "CORE_\|core-termux\|import.*\"@/" --include="*.sh" --include="*.c" . && {
    echo "ERROR: Referencia a core-termux detectada"
    exit 1
}
echo "Independencia OK"

# 4. Verificar que no hay archivos temporales
git status --short  # Debe estar limpio o solo mostrar cambios intencionales

# 5. Verificar que README.md refleja la versión correcta
grep "version-$(cat VERSION)" README.md || echo "ADVERTENCIA: README.md no muestra la versión actual"
```

### 7.2 Paso a paso del release

```bash
# 1. Asegurarse de estar en main y actualizado
git checkout main
git pull origin main

# 2. Verificar checklist pre-release (arriba)

# 3. Hacer commit de los cambios (si los hay)
git add -A
git commit -m "release: v$(cat VERSION)"

# 4. Crear tag con prefijo 'v'
git tag -a "v$(cat VERSION)" -m "Release v$(cat VERSION)"

# 5. Push a GitHub (commits + tags)
git push origin main
git push origin "v$(cat VERSION)"

# 6. Crear GitHub Release desde la CLI (o web)
gh release create "v$(cat VERSION)" \
    --title "opencode-termux v$(cat VERSION)" \
    --notes-file <(cat <<EOF
## Cambios en v$(cat VERSION)

### $(date +%Y-%m-%d)

- Descripción de los cambios aquí
- Cada línea un cambio relevante

### Instalación

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/v$(cat VERSION)/install.sh | bash
\`\`\`

### Verificación

\`\`\`bash
sha256sum install.sh
# <hash>
\`\`\`
EOF
)
```

### 7.3 Estructura recomendada de release notes

```markdown
## Cambios en v1.1.0

### 2026-07-15

#### Nuevo
- Añadido flag `--skip-deps` para instalación sin dependencias
- Nuevo script `status.sh` para verificar estado de instalación

#### Mejoras
- Mejorado mensaje de error cuando GitHub API no responde
- Reducido tiempo de timeout en curl a 30s

#### Correcciones
- Fix: `download.sh` no manejaba correctamente tags con formato `vX.Y.Z`
- Fix: `uninstall.sh` fallaba si `$PREFIX` no estaba definido

### Instalación
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/v1.1.0/install.sh | bash
\`\`\`
```

---

## 8. Procedimiento para actualizar dependencias

### 8.1 Cuándo revisar dependencias

| Frecuencia | Qué verificar |
|------------|---------------|
| Cada release de opencode-termux | Revisar si upstream cambió |
| Mensualmente | Revisar si paquetes Termux cambiaron nombre |
| Cuando un usuario reporta error | Diagnosticar si es problema de dependencia |

### 8.2 Actualizar el mapa de dependencias

En `lib/deps.sh:7-15` está el mapa:

```bash
declare -A OT_DEPS=(
    ["git"]="git"
    ["ripgrep"]="rg"
    ["python"]="python"
    ["clang"]="clang"
    ["jq"]="jq"
    ["nodejs-lts"]="node"
    ["curl"]="curl"
    ["tar"]="tar"
)
```

**Clave** = nombre del paquete en `pkg`.  
**Valor** = nombre del binario para verificar con `command -v`.

**Para cambiar una dependencia:**

1. Verificar que el nuevo paquete existe en Termux: `pkg search <nombre>`
2. Verificar el binario que proporciona: `pkg list-installed <paquete> | grep bin/`
3. Actualizar el mapa en `lib/deps.sh`
4. Actualizar la tabla de dependencias en `README.md`

### 8.3 Actualizar nombre de tarball de OpenCode

Si `anomalyco/opencode` cambia el nombre de su asset de release:

1. Ir a https://github.com/anomalyco/opencode/releases/latest
2. Ver el nombre exacto del tarball para `linux-arm64`
3. Actualizar `TARBALL_NAME` en `lib/env.sh:34`
4. Verificar que la URL construida en `lib/download.sh:22` funciona

### 8.4 Actualizar ruta del dynamic linker glibc

Si Termux cambia la ubicación de glibc (poco probable pero posible):

1. Verificar la nueva ruta con: `find $PREFIX -name "ld-linux-aarch64.so.1" 2>/dev/null`
2. Actualizar `GLIBC_LOADER`, `GLIBC_LIB_PATH`, `GLIBC_LIBC` en `lib/env.sh:19-22`
3. Actualizar las mismas rutas en:
   - `src/opencode_helper.c:22-24` (rutas hardcodeadas en C)
   - `lib/compile.sh:39-41` (rutas en el heredoc C embebido)
4. Verificar compilación: `bash install.sh` en un Termux limpio

---

## 9. Pruebas locales (sin publicar)

### 9.1 Prueba de sintaxis (offline)

```bash
for f in install.sh uninstall.sh update.sh lib/*.sh; do
    bash -n "$f" || echo "FAIL: $f"
done
```

### 9.2 Prueba de independencia

```bash
grep -rn "CORE_\|core-termux\|import.*\"@/" --include="*.sh" --include="*.c" . && echo "FAIL" || echo "PASS"
```

### 9.3 Prueba del modo clonado (simulación local)

```bash
cd opencode-termux
SCRIPT_DIR="$(pwd)"

# Simular source de libs
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Probar funciones individuales
show_banner
check_architecture
# NO ejecutar install_glibc/install_user_deps si no estás en Termux real

echo "Modo clonado: PASS"
```

### 9.4 Prueba en Termux real (dispositivo o emulador)

```bash
# 1. Clonar el repo local
git clone https://github.com/retired64/opencode-termux.git /tmp/opencode-termux-test
cd /tmp/opencode-termux-test

# 2. Ejecutar instalación (modo cloned)
bash install.sh

# 3. Verificar
opencode --version
opencode --help

# 4. Probar actualización
bash update.sh

# 5. Probar desinstalación
bash uninstall.sh

# 6. Verificar que quedó limpio
which opencode && echo "FAIL: opencode sigue instalado" || echo "PASS: opencode eliminado"
ls ~/.local/share/opencode-termux 2>/dev/null && echo "FAIL: datos no eliminados" || echo "PASS: datos limpios"
ls ~/.cache/opencode-termux 2>/dev/null && echo "FAIL: cache no eliminado" || echo "PASS: cache limpio"

# 7. Probar reinstalación después de desinstalar
bash install.sh
opencode --version

# 8. Limpiar
bash uninstall.sh
rm -rf /tmp/opencode-termux-test
```

### 9.5 Prueba del modo standalone (simulación)

```bash
# Simular curl pipe
cat install.sh | bash -

# En un entorno sin lib/ al lado, debería activar _standalone_bootstrap
# y descargar las libs desde GitHub raw
```

---

## 10. CI/CD: GitHub Actions explicado

### 10.1 Workflow: `.github/workflows/ci.yml`

Se ejecuta en cada push y PR a `main`. Tres jobs paralelos:

```yaml
jobs:
  shellcheck:      # Analiza calidad del código bash
  test-syntax:     # Verifica que bash -n no encuentra errores
  test-structure:  # Verifica que existen todos los archivos requeridos
```

### 10.2 ShellCheck

```bash
shellcheck install.sh uninstall.sh update.sh lib/*.sh
```

Reglas relevantes que ShellCheck verifica:
- SC2086: Variables sin comillas (siempre usar `"$var"`)
- SC2164: `cd` sin `|| exit` (no aplica, usamos `workdir`)
- SC2155: `readonly` y `local` en la misma línea (separar)
- SC1091: `source` de archivo que podría no existir (ignorado porque verificamos existencia antes)

### 10.3 Si el CI falla

| Error común | Causa | Solución |
|-------------|-------|----------|
| `Syntax error in install.sh` | Faltó un `"` o `fi`/`done` | Revisar la línea indicada |
| `SC2086: Double quote to prevent...` | Variable sin comillas | Envolver en `"$var"` |
| `Missing VERSION` | No se hizo checkout completo | Verificar `.gitignore` (VERSION no debe estar ignorado) |
| `shellcheck: command not found` | Ubuntu no lo tiene | El CI lo instala con `apt-get` |

### 10.4 Añadir nuevos jobs (futuro)

```yaml
# Ejemplo: test de compilación del C en un contenedor Termux simulado
test-bootstrapper-compile:
  runs-on: ubuntu-latest
  container:
    image: termux/termux-docker:aarch64
  steps:
    - uses: actions/checkout@v4
    - name: Compile bootstrapper
      run: |
        pkg install clang -y
        clang -O2 -o /tmp/opencode src/opencode_helper.c
        file /tmp/opencode
        test -x /tmp/opencode
```

---

## 11. Puntos de fallo y monitoreo

### 11.1 Tabla de riesgos

| Componente              | Riesgo | Señal de fallo | Acción |
|-------------------------|--------|----------------|--------|
| `glibc-repo`            | Medio | `pkg install glibc-repo` falla | Verificar URL del repo en Termux community |
| `glibc`                 | Bajo  | `ld-linux-aarch64.so.1` no existe | Revisar si Termux reorganizó glibc |
| GitHub API              | Medio | `get_latest_version()` retorna vacío | Verificar rate limiting, probar con token |
| Tarball name            | Medio | Descarga 404 | Revisar nombre exacto en GitHub Releases |
| Paquete renombrado      | Bajo  | `pkg install` falla con "not found" | Actualizar `OT_DEPS` en `deps.sh` |
| OpenCode deja de publicar arm64 | Bajo | 404 persistente | Añadir soporte proot o contactar upstream |
| `$PREFIX` no definido   | Bajo  | Scripts fallan con variable vacía | Fallback en `lib/env.sh`: `${PREFIX:-/data/...}` |

### 11.2 Script de health check para el mantenedor

```bash
#!/bin/bash
# health-check.sh — Ejecutar periódicamente para verificar que todo sigue funcionando

echo "=== opencode-termux health check ==="

# 1. GitHub API responde
echo -n "GitHub API: "
curl -fsSL -o /dev/null -w "%{http_code}" https://api.github.com/repos/anomalyco/opencode/releases/latest
echo ""

# 2. Tarball existe
VERSION=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo -n "Tarball ($VERSION): "
curl -fsSL -o /dev/null -w "%{http_code}" "https://github.com/anomalyco/opencode/releases/download/${VERSION}/opencode-linux-arm64.tar.gz"
echo ""

# 3. ShellCheck instalado (local)
echo -n "ShellCheck: "
command -v shellcheck &>/dev/null && echo "OK" || echo "NOT INSTALLED"

# 4. Bash syntax
echo -n "Bash syntax: "
for f in install.sh uninstall.sh update.sh lib/*.sh; do
    bash -n "$f" || { echo "FAIL: $f"; exit 1; }
done
echo "OK"

# 5. No core-termux refs
echo -n "Independence: "
grep -rn "CORE_\|core-termux\|import.*\"@/" --include="*.sh" --include="*.c" . && echo "FAIL" || echo "OK"

echo "=== Health check complete ==="
```

---

## 12. Cómo modificar el bootstrapper C

### 12.1 Archivos a modificar

Si necesitas cambiar la lógica del bootstrapper, hay **3 lugares** que deben mantenerse sincronizados:

| # | Archivo | Línea(s) | Qué contiene |
|---|---------|----------|--------------|
| 1 | `src/opencode_helper.c` | Todo | Código fuente canónico que se compila en modo clonado |
| 2 | `lib/compile.sh:38-73` | Heredoc `OPENCODE_HELPER_EOF` | Código embebido usado como fallback en modo standalone |
| 3 | `guia-instalacion-manual-opencode-glibc.md` (en core-termux) | Sección 6.1 | Documentación del análisis línea por línea |

### 12.2 Ejemplo: añadir una variable de entorno

Si OpenCode necesita `OPENCODE_CONFIG_DIR=/path`:

```c
// En src/opencode_helper.c, después del setenv existente:
setenv("OPENCODE_CONFIG_DIR", "/data/data/com.termux/files/home/.config/opencode", 1);
```

Luego replicar el mismo cambio en `lib/compile.sh:42` (dentro del heredoc).

### 12.3 Ejemplo: cambiar ruta del binario real

Si `$OT_DATA_DIR` cambia de `~/.local/share/opencode-termux` a `~/.opencode-termux`:

1. `lib/env.sh`: Cambiar `OT_DATA_DIR` y `OT_BIN_DIR`
2. `src/opencode_helper.c:24`: Cambiar `real_bin` hardcodeado
3. `lib/compile.sh:41`: Cambiar `real_bin` en el heredoc
4. `uninstall.sh`: Actualizar `OT_DATA_DIR` inline
5. `README.md`: Actualizar tabla de paths

### 12.4 Compilación de prueba del C

```bash
# Probar compilación local
clang -O2 -o /tmp/opencode-test src/opencode_helper.c

# Verificar que compila sin warnings
clang -O2 -Wall -Wextra -o /tmp/opencode-test src/opencode_helper.c

# Verificar símbolos
nm /tmp/opencode-test | grep -E "unsetenv|setenv|execv|readlink"

# Verificar tamaño
ls -lh /tmp/opencode-test

# Limpiar
rm /tmp/opencode-test
```

---

## 13. Script de release automatizado

Guarda este script como `scripts/release.sh` en el futuro. Por ahora, ejecuta manualmente:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
TAG="v${VERSION}"

echo "=== opencode-termux release: ${TAG} ==="
echo ""

# 1. Verificar limpieza del repo
if [[ -n $(git status --porcelain) ]]; then
    echo "ERROR: Hay cambios sin commitear"
    git status --short
    exit 1
fi

# 2. Verificar que VERSION y lib/env.sh coinciden
ENV_VERSION=$(grep "OT_VERSION" lib/env.sh | grep -o '"[^"]*"' | tr -d '"')
if [[ "$VERSION" != "$ENV_VERSION" ]]; then
    echo "ERROR: VERSION ($VERSION) != lib/env.sh OT_VERSION ($ENV_VERSION)"
    exit 1
fi

# 3. Bash syntax check
echo "→ Verificando sintaxis bash..."
for f in install.sh uninstall.sh update.sh lib/*.sh; do
    bash -n "$f" || { echo "ERROR: Syntax error in $f"; exit 1; }
done
echo "  OK"

# 4. Independence check
echo "→ Verificando independencia de core-termux..."
if grep -rn "CORE_\|core-termux\|import.*\"@/" --include="*.sh" --include="*.c" . >/dev/null 2>&1; then
    echo "ERROR: Referencia a core-termux detectada"
    grep -rn "CORE_\|core-termux\|import.*\"@/" --include="*.sh" --include="*.c" .
    exit 1
fi
echo "  OK"

# 5. ShellCheck (si está instalado)
if command -v shellcheck &>/dev/null; then
    echo "→ Ejecutando ShellCheck..."
    shellcheck install.sh uninstall.sh update.sh lib/*.sh || true
fi

# 6. Confirmar
echo ""
echo "Versión a publicar: ${TAG}"
echo "Contenido del tag anterior:"
git describe --tags --abbrev=0 2>/dev/null || echo "  (primer release)"
echo ""
echo "Últimos commits:"
git log --oneline -5
echo ""
read -rp "¿Publicar release ${TAG}? [s/N]: " confirm
if [[ ! "$confirm" =~ ^[sSyY]$ ]]; then
    echo "Cancelado"
    exit 0
fi

# 7. Tag y push
echo "→ Creando tag ${TAG}..."
git tag -a "${TAG}" -m "Release ${TAG}"

echo "→ Pushing a origin..."
git push origin main
git push origin "${TAG}"

# 8. Crear GitHub Release (si gh está instalado)
if command -v gh &>/dev/null; then
    echo "→ Creando GitHub Release..."
    gh release create "${TAG}" \
        --title "opencode-termux ${TAG}" \
        --notes "Ver [CHANGELOG](https://github.com/retired64/opencode-termux/blob/main/CHANGELOG.md) para detalles."
    echo "  Release creada: https://github.com/retired64/opencode-termux/releases/tag/${TAG}"
else
    echo ""
    echo "Release tag creada. Crea la release manualmente en:"
    echo "  https://github.com/retired64/opencode-termux/releases/new?tag=${TAG}"
fi

echo ""
echo "=== Release ${TAG} completado ==="
echo ""
echo "URL del instalador:"
echo "  https://raw.githubusercontent.com/retired64/opencode-termux/${TAG}/install.sh"
```

---

## 14. Script de verificación pre-release

```bash
#!/bin/bash
# Guardar como scripts/verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ERRORS=0

check() {
    local desc="$1"; shift
    if "$@" &>/dev/null; then
        echo "  ✔ $desc"
    else
        echo "  ✖ $desc"
        ((ERRORS++))
    fi
}

echo "=== opencode-termux pre-release verification ==="
echo ""

echo "── Estructura ──"
check "VERSION readable" test -f VERSION
check "LICENSE present" test -f LICENSE
check "README.md present" test -f README.md
check "install.sh present" test -f install.sh
check "uninstall.sh present" test -f uninstall.sh
check "update.sh present" test -f update.sh
check "src/opencode_helper.c present" test -f src/opencode_helper.c
check "lib/env.sh present" test -f lib/env.sh
check "lib/colors.sh present" test -f lib/colors.sh
check "lib/logging.sh present" test -f lib/logging.sh
check "lib/deps.sh present" test -f lib/deps.sh
check "lib/download.sh present" test -f lib/download.sh
check "lib/compile.sh present" test -f lib/compile.sh
check ".github/workflows/ci.yml present" test -f .github/workflows/ci.yml

echo ""
echo "── Sintaxis bash ──"
check "install.sh syntax" bash -n install.sh
check "uninstall.sh syntax" bash -n uninstall.sh
check "update.sh syntax" bash -n update.sh
check "lib/env.sh syntax" bash -n lib/env.sh
check "lib/colors.sh syntax" bash -n lib/colors.sh
check "lib/logging.sh syntax" bash -n lib/logging.sh
check "lib/deps.sh syntax" bash -n lib/deps.sh
check "lib/download.sh syntax" bash -n lib/download.sh
check "lib/compile.sh syntax" bash -n lib/compile.sh

echo ""
echo "── Independencia ──"
check "No CORE_ refs" test -z "$(grep -rn 'CORE_' --include='*.sh' --include='*.c' . 2>/dev/null || true)"
check "No core-termux refs" test -z "$(grep -rn 'core-termux' --include='*.sh' --include='*.c' . 2>/dev/null || true)"
check "No import @/ refs" test -z "$(grep -rn 'import.*\"@/' --include='*.sh' . 2>/dev/null || true)"

echo ""
echo "── Versionado ──"
VERSION=$(cat VERSION)
ENV_VERSION=$(grep "OT_VERSION" lib/env.sh | grep -o '"[^"]*"' | tr -d '"')
if [[ "$VERSION" == "$ENV_VERSION" ]]; then
    echo "  ✔ VERSION ($VERSION) == lib/env.sh OT_VERSION ($ENV_VERSION)"
else
    echo "  ✖ VERSION ($VERSION) != lib/env.sh OT_VERSION ($ENV_VERSION)"
    ((ERRORS++))
fi

echo ""
echo "── Bootstrapper C ──"
check "Has unsetenv LD_PRELOAD" grep -q 'unsetenv("LD_PRELOAD")' src/opencode_helper.c
check "Has setenv GODEBUG" grep -q 'netdns=cgo' src/opencode_helper.c
check "Has real_bin path" grep -q 'opencode-termux/bin/opencode' src/opencode_helper.c
check "Has execv call" grep -q 'execv(loader' src/opencode_helper.c

echo ""
echo "── Permisos ──"
check "install.sh executable" test -x install.sh
check "uninstall.sh executable" test -x uninstall.sh
check "update.sh executable" test -x update.sh

echo ""
echo "=========================================="
if [[ $ERRORS -eq 0 ]]; then
    echo "✔ VERIFICACIÓN COMPLETA - Listo para release"
else
    echo "✖ Se encontraron $ERRORS error(es)"
fi
```

---

## Apéndice: Comandos rápidos para el mantenedor

```bash
# Verificar todo antes de commit
bash scripts/verify.sh

# Ver sintaxis de todos los scripts
for f in install.sh uninstall.sh update.sh lib/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done

# Verificar independencia
grep -rn "CORE_\|core-termux\|import.*\"@/" --include="*.sh" --include="*.c" . || echo "Limpio"

# Verificar que VERSION y lib/env.sh coinciden
diff <(cat VERSION) <(grep "OT_VERSION" lib/env.sh | grep -o '"[^"]*"' | tr -d '"') && echo "OK" || echo "MISMATCH"

# Hacer release
bash scripts/release.sh

# Ver sólo los archivos del proyecto (sin .git)
find . -type f -not -path './.git/*' | sort

# Contar líneas totales del proyecto
find . -type f -not -path './.git/*' -name "*.sh" -o -name "*.c" -o -name "*.yml" -o -name "*.md" | xargs wc -l | tail -1
```

---

> **Documento generado para el mantenedor de `opencode-termux`.**  
> Cubre el ciclo completo de desarrollo, prueba, versionado y publicación.
