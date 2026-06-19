> Riesgos conocidos, deuda técnica y límites explícitos del proyecto.
> Leer antes de diagnosticar un fallo o de proponer una "mejora" que el proyecto ya descartó a propósito.

---

## 9. Riesgos y deuda técnica detectados (para priorizar al modificar)

1. **Doble fuente de verdad del helper C** (`docs/architecture.md` §6, runbook 13.1) — el mayor riesgo de bugs silenciosos. Cualquier fix al `.c` aplicado en un solo lugar deja el otro modo (clonado vs standalone) con comportamiento divergente sin que ningún test lo detecte.
2. **`TARBALL_NAME` fijo a `arm64`** y `check_architecture` exige `aarch64` exclusivamente — no hay soporte ni plan de soporte multi-arch. Si OpenCode upstream cambia el naming del asset de release, `download_opencode` fallará con un error genérico de descarga sin pista de la causa raíz.
3. **Sin verificación de integridad** del tarball descargado (no hay checksum/sha256 ni verificación de firma) — riesgo de supply-chain si GitHub Releases o el raw.githubusercontent del propio instalador son interceptados.
4. **`VERSION` (raíz) y `OT_VERSION` (`env.sh`) son dos literales independientes** — nada falla si quedan desincronizados, simplemente el banner mostraría una versión incorrecta. Ver runbook 13.5.
5. **`update.sh` no soporta modo standalone** — un usuario que instaló vía `curl | bash` no tiene `lib/` local y `update.sh` solo funciona clonando el repo. Esto no está comunicado en `install.sh` (el banner final solo dice `opencode --help`, no menciona cómo actualizar).
6. **Sin tests automatizados** (no hay `tests/`, CI, ni shellcheck corriendo en pipeline visible) — los `# shellcheck disable=SC2034` sueltos en `env.sh`/`colors.sh` sugieren que sí se corre shellcheck manualmente, pero no hay evidencia de CI.
7. **Credenciales/rate limit de GitHub API**: `get_latest_version()` llama a la API de GitHub sin token — sujeto al rate limit anónimo (60 req/hora por IP), que puede agotarse fácilmente en testing repetido.

---

## 12. Lo que este proyecto explícitamente NO hace (no asumir lo contrario, no "arreglarlo" sin que la tarea lo pida)

- No soporta arquitecturas distintas de `aarch64`.
- No tiene modo de instalación offline (siempre requiere red para `pkg`, GitHub API y GitHub Releases).
- No verifica checksums de lo que descarga.
- No tiene mecanismo de rollback si `compile_bootstrapper` falla después de que `download_opencode` ya sobrescribió el binario anterior.
- No empaqueta nada como paquete de Termux (`.deb`) — es siempre script + compilación local con `clang`.

Estos puntos no son omisiones accidentales reportables como "bugs" por defecto — son decisiones de alcance. Si una tarea pide explícitamente resolver uno de estos, hacelo; si no, no lo agregues como efecto colateral de otro cambio (viola la filosofía de simplicidad y dependencias mínimas de `AGENTS.md` §2).

---

## Guía rápida de diagnóstico

| Síntoma | Causa probable | Dónde mirar |
|---|---|---|
| `install.sh` dice "Todas las dependencias listas" pero `clang` no está instalado | Regresión del bug de scope de `declare -A` (ver `docs/architecture.md` §5, punto 3) | `lib/deps.sh::OT_DEPS` debe ser `declare -gA` |
| El script muere sin mensaje de error bajo `set -e` | Regresión del bug de post-incremento aritmético (`docs/architecture.md` §5, punto 4) | Buscar `((var++))` en el archivo tocado |
| Funciona en modo clonado pero falla en `curl \| bash` | Alguna lib nueva no fue agregada a `_standalone_bootstrap()` o falta su `source` en `_flat_bootstrap()` | Runbook 13.3, pasos 2-4 |
| El binario `opencode` ejecuta una versión vieja de OpenCode tras "actualizar" | El heredoc embebido en `compile.sh` quedó desincronizado del `src/opencode_helper.c` real, o `download_opencode` no sobrescribió `OPENCODE_REAL_BIN` | Runbook 13.1; revisar `OT_DATA_DIR/.version` |
| `pkg install` falla sin explicación visible | Posible regresión del fix de silenciado de salida (`docs/architecture.md` §5, punto 6) | Confirmar que no se reintrodujo `&>/dev/null` en `install_user_deps()` |
| `get_latest_version()` devuelve vacío intermitentemente | Rate limit anónimo de GitHub API agotado | Riesgo conocido #7 — no hay fix planeado, es una limitación aceptada |

