> Procedimientos ejecutables paso a paso. Referenciado desde `AGENTS.md`.
> Si tu tarea es "hacer X", buscá el runbook de X acá antes de improvisar el orden de los pasos.

---

## 13.1 Protocolo obligatorio: editar `src/opencode_helper.c`

El heredoc en `lib/compile.sh::write_embedded_helper()` (entre los marcadores `OPENCODE_HELPER_EOF`) debe ser **byte a byte idéntico** al contenido de `src/opencode_helper.c`. No hay generación automática — la sincronización es manual y el agente es responsable de hacerla en el mismo commit.

```bash
# Paso 1 — Editá SOLO src/opencode_helper.c (fuente canónica)
str_replace / edit en src/opencode_helper.c

# Paso 2 — Extraé el heredoc actual de compile.sh para comparar
sed -n '/cat >"\$tmp_src" <<.OPENCODE_HELPER_EOF./,/^OPENCODE_HELPER_EOF$/p' lib/compile.sh \
  | sed '1d;$d' > /tmp/embedded_current.c

# Paso 3 — Diff contra la fuente canónica
diff src/opencode_helper.c /tmp/embedded_current.c

# Paso 4 — Si hay diferencias, reemplazá el bloque heredoc completo en compile.sh
# con el contenido nuevo de src/opencode_helper.c (mismos marcadores EOF, no los toques)

# Paso 5 — Verificación final antes de commit: ambos deben compilar igual
clang -O2 -o /tmp/bin_canonico src/opencode_helper.c
clang -O2 -o /tmp/bin_embebido /tmp/embedded_current.c
diff <(md5sum /tmp/bin_canonico | cut -d' ' -f1) <(md5sum /tmp/bin_embebido | cut -d' ' -f1)
```

**Nunca** edites el heredoc de `compile.sh` directamente como fuente de verdad — siempre editá `src/opencode_helper.c` primero y propagá. Si el diff del Paso 3 no es vacío al final, el commit no está listo.

---

## 13.2 Runbook: agregar una dependencia nueva a `OT_DEPS`

1. Agregá la entrada `["paquete-pkg"]="binario-verificador"` en `lib/deps.sh::OT_DEPS`.
2. Confirmá que el nombre del paquete es el correcto para `pkg install` en Termux (no asumas que el nombre de Debian/Ubuntu es igual).
3. No hace falta tocar `install.sh` — `install_user_deps()` itera `OT_DEPS` dinámicamente.
4. Probá en limpio: `bash install.sh` en un entorno donde el paquete no esté instalado, confirmá que aparece "Instalando <paquete>..." y termina en "<paquete> instalado".

---

## 13.3 Runbook: agregar una lib nueva en `lib/`

1. Creá `lib/nueva.sh` con shebang Termux + include guard propio (`_OT_NUEVA_LOADED`). No le pongas `set -e`. No sourcees otras libs desde adentro.
2. En `install.sh`, agregá `source "${SCRIPT_DIR}/lib/nueva.sh"` en `_cloned_bootstrap()`.
3. Agregá `source "${SCRIPT_DIR}/nueva.sh"` en `_flat_bootstrap()`.
4. Agregá `"nueva.sh"` a la lista del loop `for lib in env.sh colors.sh logging.sh deps.sh download.sh compile.sh; do` dentro de `_standalone_bootstrap()`, y confirmá que `_flat_bootstrap` (que es lo que usa el modo standalone tras descargar) ya la sourcea por el paso 3.
5. Si las funciones de `nueva.sh` se necesitan en `update.sh`, agregá el `source "${SCRIPT_DIR}/lib/nueva.sh"` correspondiente ahí también (recordá: `update.sh` solo soporta modo clonado).
6. Corré `shellcheck lib/nueva.sh` antes de commitear.

---

## 13.4 Runbook: cambiar una ruta en `env.sh` (p. ej. mover `OT_DATA_DIR`)

1. Cambiá el valor en `lib/env.sh`.
2. Buscá toda referencia hardcodeada equivalente fuera de `env.sh`:
   ```bash
   grep -rn "opencode-termux" --include="*.sh" --include="*.c" .
   ```
3. Actualizá manualmente: `uninstall.sh` (recalcula la ruta inline) y, si la ruta afecta al binario real o al loader, `src/opencode_helper.c` **y** el heredoc embebido en `compile.sh` (runbook 13.1).
4. Corré `bash install.sh` en limpio y luego `bash uninstall.sh`, confirmando que ambos apuntan al mismo directorio final.

---

## 13.5 Runbook: bump de versión

1. Actualizá `VERSION` (raíz, texto plano, sin `v` prefijo, ej: `1.1.0`).
2. Actualizá `readonly OT_VERSION="1.1.0"` en `lib/env.sh` con el mismo valor.
3. Confirmá que ambos archivos coinciden: `diff <(cat VERSION) <(grep -oP '(?<=OT_VERSION=")[^"]+' lib/env.sh)` debe no devolver nada.
4. No hay changelog automatizado en este repo — si el proyecto lo requiere, actualizalo a mano.

---

## 13.6 Orden de prioridad cuando un cambio toca varias áreas a la vez

Si una tarea requiere tocar simultáneamente rutas (`env.sh`), el helper C y alguna lib, seguí este orden para minimizar estados intermedios rotos:

1. `lib/env.sh` primero (la fuente de verdad de rutas/constantes).
2. Libs de `lib/` que consumen esas variables (`deps.sh`, `download.sh`, `compile.sh`, etc.).
3. `src/opencode_helper.c` (fuente canónica del binario).
4. Sincronización del heredoc en `compile.sh` (runbook 13.1) — siempre el último paso, nunca en paralelo con el paso 3.
5. `uninstall.sh` (autocontenido, se actualiza al final porque no depende de nada de lo anterior pero sí debe reflejarlo).
6. Validación manual completa: `bash install.sh` (modo clonado) → `opencode --help` → `bash update.sh` → `bash uninstall.sh`.

---

## 14. Cómo testear cambios (no hay test runner — esto es manual)

No existe suite de tests. Para validar cambios, correr manualmente dentro de Termux (ARM64 real o emulado):

```bash
# Modo clonado (el más fácil de iterar)
bash install.sh

# Simular modo standalone (pipe) sin publicar a GitHub:
cat install.sh | bash

# Verificar shellcheck antes de cualquier PR
shellcheck lib/*.sh install.sh update.sh uninstall.sh

# Verificar que el helper C compila sin warnings
clang -O2 -Wall -Wextra -o /tmp/opencode_test src/opencode_helper.c
```

No hay entorno de CI conocido en el repo subido — si se agrega, debería como mínimo correr `shellcheck` sobre todos los `.sh` y compilar `src/opencode_helper.c` con `clang -O2 -Wall -Wextra` para detectar warnings.

---

## 15. Checklist antes de abrir PR / commit

- [ ] ¿Tocaste `src/opencode_helper.c`? → Corré el runbook 13.1 antes de commitear.
- [ ] ¿Agregaste una lib nueva en `lib/`? → Runbook 13.3 completo.
- [ ] ¿Tocaste rutas en `env.sh`? → Runbook 13.4 completo.
- [ ] ¿Usaste `((var++))` en código con `set -e` activo? → Cambialo a `var=$((var + 1))`.
- [ ] ¿El mensaje nuevo está en español y usa `log_*` en vez de `echo`?
- [ ] ¿Corriste `shellcheck` sobre los archivos modificados?
- [ ] Si cambiaste versión: runbook 13.5 completo.
- [ ] Repasá `AGENTS.md` §6 "Definición de terminado" antes de declarar la tarea cerrada.

