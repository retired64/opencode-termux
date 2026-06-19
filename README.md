# opencode-termux

**OpenCode installer for Termux (native glibc + C bootstrapper)**

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](VERSION)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Arch](https://img.shields.io/badge/arch-aarch64-orange)](#requirements)

Instala [OpenCode](https://github.com/anomalyco/opencode) de forma nativa en Termux (Android) usando glibc y un bootstrapper C compilado con Clang. Sin contenedores, sin proot, sin overhead.

---

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash
```

O si prefieres revisar el script antes de ejecutarlo:

```bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh -o install.sh
less install.sh
bash install.sh
```

---

## Requirements

- **Termux** instalado desde [F-Droid](https://f-droid.org/) (NO Google Play)
- Arquitectura **aarch64** (ARM64)
- Conexión a internet

Todo lo demás (glibc, clang, git, ripgrep, python, nodejs, etc.) se instala automáticamente.

---

## How it works

OpenCode se distribuye como un binario enlazado contra **glibc**, pero Termux usa **Bionic** (la libc de Android). Para ejecutar OpenCode necesitamos un puente:

```
$PREFIX/bin/opencode               ← Bootstrapper C (compilado nativo, Bionic)
    │
    │  execv()
    ▼
$PREFIX/glibc/lib/ld-linux-aarch64.so.1  ← Dynamic linker glibc
    │
    │  --library-path $PREFIX/glibc/lib
    ▼
~/.local/share/opencode-termux/bin/opencode  ← Binario real OpenCode (glibc)
```

El bootstrapper C (`src/opencode_helper.c`, 52 líneas) se compila con Clang en el momento de la instalación. Es un binario nativo de Android (Bionic) que limpia variables de entorno conflictivas y carga el binario real de OpenCode a través del dynamic linker de glibc.

---

## Commands

### Install

```bash
# Método 1: curl pipe (recomendado)
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash

# Método 2: clonar y ejecutar
git clone https://github.com/retired64/opencode-termux.git
cd opencode-termux
bash install.sh
```

### Update

```bash
cd opencode-termux
bash update.sh
```

### Uninstall

```bash
# Si clonaste el repo
cd opencode-termux
bash uninstall.sh

# O directamente desde GitHub
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/uninstall.sh | bash
```

---

## File structure

```
opencode-termux/
├── .github/workflows/ci.yml   # CI: ShellCheck + syntax check
├── src/
│   └── opencode_helper.c      # Bootstrapper C nativo
├── lib/
│   ├── env.sh                 # Constantes y rutas (namespace OT_*)
│   ├── colors.sh              # Definiciones de colores ANSI
│   ├── logging.sh             # Funciones de logging + banner
│   ├── deps.sh                # Instalación de dependencias
│   ├── download.sh            # Descarga de OpenCode desde GitHub Releases
│   └── compile.sh             # Compilación del bootstrapper
├── install.sh                 # Instalador principal
├── uninstall.sh               # Desinstalador
├── update.sh                  # Actualizador
├── VERSION                    # Versión del instalador
├── LICENSE                    # MIT
└── README.md                  # Este archivo
```

---

## Paths

| Element | Path |
|---------|------|
| Bootstrapper | `$PREFIX/bin/opencode` |
| Binary | `~/.local/share/opencode-termux/bin/opencode` |
| Version file | `~/.local/share/opencode-termux/.version` |
| Cache | `~/.cache/opencode-termux/` |
| glibc loader | `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` |
| glibc libs | `$PREFIX/glibc/lib/` |

---

## Troubleshooting

### `opencode: command not found`

El bootstrapper no está en el PATH. Reinstala:

```bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash
```

### `execv: No such file or directory`

Falta glibc o el binario de OpenCode:

```bash
pkg install glibc-repo -y && pkg install glibc -y
ls -la ~/.local/share/opencode-termux/bin/opencode
```

### SSL certificate errors

```bash
pkg install ca-certificates -y
ls -la /data/data/com.termux/files/usr/etc/tls/cert.pem
```

### DNS resolution errors

```bash
echo "nameserver 8.8.8.8" > $PREFIX/etc/resolv.conf
echo "nameserver 8.8.4.4" >> $PREFIX/etc/resolv.conf
```

---

## Dependencies installed

| Package | Binary | Purpose |
|---------|--------|---------|
| glibc-repo | (repo) | Adds glibc package repository |
| glibc | ld-linux-aarch64.so.1 | Dynamic linker + glibc libraries |
| clang | clang | Compiles the C bootstrapper |
| git | git | Required by OpenCode |
| ripgrep | rg | Required by OpenCode |
| python | python | Required by OpenCode |
| nodejs-lts | node | Required by OpenCode |
| jq | jq | JSON parsing |
| curl | curl | Binary download |
| tar | tar | Tarball extraction |

---

## License

MIT © 2026 [retired64](https://github.com/retired64)

OpenCode is developed by [anomalyco](https://github.com/anomalyco/opencode) and distributed under its own license.
# opencode-termux
