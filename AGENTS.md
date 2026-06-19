> Este archivo es deliberadamente corto. La profundidad vive en `docs/`. Leelos según la tarea — ver sección 5.

---

## 1. Qué es este proyecto (resumen de 30 segundos)

**opencode-termux** instala el CLI **OpenCode** (`anomalyco/opencode`, binario glibc) dentro de **Termux** en Android (**aarch64 únicamente**), donde no hay glibc nativo. La solución: instalar glibc vía `pkg`, descargar el binario real de OpenCode, y compilar un **bootstrapper en C** (`src/opencode_helper.c`) que se instala como `$PREFIX/bin/opencode` y reejecuta el binario real bajo el loader de glibc.

`opencode` en el PATH del usuario **no es OpenCode** — es un wrapper C de ~40 líneas.

Para arquitectura completa, los 3 modos de instalación, convenciones de código y bugs históricos → **`docs/architecture.md`**.

---

## 2. Filosofía del proyecto

Cuando haya más de una forma válida de resolver algo, este proyecto prioriza en este orden:

1. **Compatibilidad con Termux** por sobre portabilidad genérica a Linux — las rutas, el shebang y los workarounds (`$TMPDIR` en vez de `/tmp`, etc.) existen porque Termux rompe supuestos estándar de Linux.
2. **Simplicidad** sobre elegancia — preferir un `if/elif/else` explícito y repetitivo (como los 3 modos de bootstrap) antes que una abstracción genérica difícil de seguir.
3. **Dependencias mínimas** — todo lo que se pueda resolver con bash + coreutils + `pkg`, se resuelve así. No se introduce una dependencia nueva (Python, Node, librería externa) para una tarea que bash ya cubre.
4. **Robustez sobre micro-optimización** — preferir código que falle ruidosamente y con buen diagnóstico (ver bug histórico de `pkg install` silenciado en `docs/architecture.md`) antes que código "elegante" que pueda fallar en silencio.
5. **Bash explícito y portable dentro de lo razonable** — evitar bashismos innecesarios cuando un POSIX simple alcanza, pero sin sacrificar legibilidad por portabilidad teórica que este proyecto no necesita (solo corre en Termux/bash, nunca en `sh`).

Si una tarea no especifica cómo resolver algo, resolvé en esa dirección y dejalo explícito en el commit/PR.

---

## 3. Zonas de modificación

### 🟢 Zonas seguras — modificables con libertad si la tarea lo pide
- `lib/*.sh` (cualquier lib existente o nueva)
- `install.sh`, `update.sh`
- `docs/*.md`

### 🟡 Zonas críticas — modificar solo si la tarea específicamente lo requiere, y siempre siguiendo el runbook correspondiente
- `VERSION` y `OT_VERSION` (deben cambiar juntos — runbook 13.5 en `docs/runbooks.md`)
- `lib/env.sh` (fuente de verdad de rutas — cualquier cambio dispara el runbook 13.4)
- `uninstall.sh` (autocontenido, no sincroniza solo — hay que actualizarlo a mano)
- `src/opencode_helper.c` (canónico, pero requiere sincronización obligatoria — runbook 13.1)

### 🔴 Zonas extremadamente sensibles — no tocar salvo que la tarea sea explícitamente sobre esto, y revisar dos veces antes de commitear
- `lib/compile.sh::write_embedded_helper()` (heredoc embebido — debe ser idéntico byte a byte a `src/opencode_helper.c`)
- Rutas del loader glibc (`GLIBC_LOADER`, `GLIBC_LIB_PATH`) y su uso en `opencode_helper.c` — un error aquí rompe **toda** instalación existente, no solo las nuevas.
- La lógica de `execv()` dentro del helper C — es la única razón de ser del binario; un bug ahí no falla con error, falla con un crash o ejecución silenciosa del binario equivocado.

---

## 4. Invariantes del sistema

Estas condiciones deben ser ciertas **siempre**, en cualquier estado del repo, en cualquier modo de instalación. Si un cambio las rompe, el cambio está mal, sin excepción:

1. `opencode` en el PATH del usuario (`$PREFIX/bin/opencode`) **siempre** es el bootstrapper C, nunca el binario real de OpenCode.
2. El binario real de OpenCode **siempre** vive en `OT_BIN_DIR` (`$OT_DATA_DIR/bin/opencode`), nunca en el PATH directamente.
3. El modo **standalone** (`curl | bash`) debe funcionar **sin ningún repo clonado localmente** — no puede depender de `src/` ni de ningún archivo que solo exista en modo cloned.
4. Los modos **cloned**, **flat** y **standalone** deben producir un bootstrapper funcionalmente idéntico — ninguno es "el modo de segunda clase".
5. `lib/env.sh` es la **única** fuente de verdad para rutas y constantes del lado bash. Ningún otro `.sh` define su propia copia de una ruta que ya existe en `env.sh`.
6. `src/opencode_helper.c` es la **única** fuente canónica del helper C. El heredoc en `compile.sh` es una copia derivada, nunca al revés.
7. Ninguna lib en `lib/` sourcea otra lib internamente — el orden de carga lo decide siempre quien invoca (`install.sh` / `update.sh`).
8. Todo mensaje visible al usuario está en español.

---

## 5. Mapa de documentación — qué leer según la tarea

| Tarea | Leer obligatoriamente |
|---|---|
| Entender arquitectura, los 3 modos de bootstrap, convenciones de código, bugs históricos, variables de entorno | `docs/architecture.md` |
| Ejecutar un cambio concreto (editar el helper C, agregar dependencia, agregar lib, cambiar rutas, bump de versión) | `docs/runbooks.md` |
| Diagnosticar un fallo, evaluar riesgos conocidos, entender qué NO hace el proyecto | `docs/troubleshooting.md` |

No asumas contenido de `docs/*.md` sin abrirlo — este índice resume, no sustituye.

---

## 6. Definición de terminado

Un cambio se considera completo **únicamente** si se cumplen todas las condiciones aplicables:

- [ ] `shellcheck lib/*.sh install.sh update.sh uninstall.sh` no reporta errores nuevos.
- [ ] `bash install.sh` (modo clonado) corre sin errores de principio a fin.
- [ ] `opencode --help` funciona después de la instalación.
- [ ] `bash update.sh` corre sin errores (si el cambio pudo afectar descarga/compilación).
- [ ] `bash uninstall.sh` limpia todo lo que `install.sh` creó.
- [ ] Si se tocó `src/opencode_helper.c`: el heredoc de `compile.sh` quedó sincronizado (ver runbook 13.1) y ambos binarios compilan con el mismo hash.
- [ ] Si se tocó `lib/env.sh`: se revisaron `uninstall.sh` y `opencode_helper.c` por rutas duplicadas (ver runbook 13.4).
- [ ] Si se cambió versión: `VERSION` y `OT_VERSION` coinciden.
- [ ] Ninguna invariante de la sección 4 quedó violada.

Si alguna casilla no aplica a la tarea, decilo explícitamente en el resumen del cambio — no la omitas en silencio.

