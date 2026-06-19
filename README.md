# opencode-termux

**Run OpenCode natively on Termux (Android). No proot, no containers, no emulation.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](VERSION)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Arch](https://img.shields.io/badge/arch-aarch64-orange)](#requirements)

[OpenCode](https://github.com/anomalyco/opencode) is an AI coding agent that ships as a glibc-linked binary, which is a problem on Android since Termux runs on Bionic, not glibc. This project installs OpenCode on Termux the native way: it pulls in glibc through `pkg`, downloads the official OpenCode release, and compiles a small C bootstrapper that bridges the two libc's at runtime. No proot, no chroot, no Docker, no performance penalty. Just OpenCode running directly on your phone or tablet.

If you've been searching for **how to install OpenCode on Termux**, **run an AI coding agent on Android**, or **get a glibc binary working on Termux**, this is built for exactly that.

---

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash
```

Prefer to read the script before running it? Totally fair:

```bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh -o install.sh
less install.sh
bash install.sh
```

---

## Requirements

- **Termux** installed from [F-Droid](https://f-droid.org/), not the Play Store build (it's outdated and unmaintained)
- **aarch64 (ARM64)** device, the only architecture OpenCode ships for on Android
- An internet connection for the initial setup

Everything else (glibc, clang, git, ripgrep, python, Node.js, etc.) gets installed automatically.

---

## How it works

OpenCode is distributed as a binary linked against **glibc**, but Termux runs on **Bionic**, the libc Android ships with. To bridge that gap, the installer compiles a small C bootstrapper that gets placed in your `$PATH` as `opencode`:

```
$PREFIX/bin/opencode                       ← C bootstrapper (native Bionic binary)
    │
    │  execv()
    ▼
$PREFIX/glibc/lib/ld-linux-aarch64.so.1    ← glibc dynamic linker
    │
    │  --library-path $PREFIX/glibc/lib
    ▼
~/.local/share/opencode-termux/bin/opencode ← Real OpenCode binary (glibc)
```

The bootstrapper (`src/opencode_helper.c`, ~50 lines) is compiled with Clang at install time. It's a native Bionic binary that strips out conflicting environment variables (`LD_PRELOAD`, `LD_LIBRARY_PATH`) and hands off execution to the real OpenCode binary through the glibc dynamic linker. The result: typing `opencode` in any Termux session just works, like it would on a regular Linux box.

---

## Commands

### Install

```bash
# Method 1: curl pipe (fastest)
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash

# Method 2: clone and run
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
# If you cloned the repo
cd opencode-termux
bash uninstall.sh

# Or directly from GitHub
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/uninstall.sh | bash
```

---

## File structure

```
opencode-termux/
├── .github/workflows/ci.yml   # CI: ShellCheck + syntax check
├── src/
│   └── opencode_helper.c      # Native C bootstrapper
├── lib/
│   ├── env.sh                 # Constants and paths (OT_* namespace)
│   ├── colors.sh               # ANSI color definitions
│   ├── logging.sh              # Logging helpers + banner
│   ├── deps.sh                 # Dependency installation
│   ├── download.sh             # Downloads OpenCode from GitHub Releases
│   └── compile.sh              # Compiles the bootstrapper
├── install.sh                  # Main installer
├── uninstall.sh                # Uninstaller
├── update.sh                   # Updater
├── VERSION                     # Installer version
├── LICENSE                     # MIT
└── README.md                   # This file
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

The bootstrapper isn't in your `$PATH`. Reinstall:

```bash
curl -fsSL https://raw.githubusercontent.com/retired64/opencode-termux/main/install.sh | bash
```

### `execv: No such file or directory`

Either glibc or the OpenCode binary is missing:

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
| glibc-repo | (repo) | Adds the glibc package repository |
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

## FAQ

**Does this work on Termux from the Play Store?**
No. Use the [F-Droid build](https://f-droid.org/) instead. The Play Store version is deprecated and missing packages this installer relies on.

**Does this work on x86_64 or 32-bit ARM?**
Not yet. OpenCode only publishes `aarch64` (ARM64) releases, so that's the only architecture supported here.

**Is this a fork or wrapper of OpenCode itself?**
No. This repo doesn't modify OpenCode at all. It just handles the glibc/Bionic bridging so the official binary runs unmodified on Android.

**Will this slow down OpenCode compared to a regular Linux machine?**
No meaningful overhead. There's no proot, no containerization layer, and no translation step at runtime. The bootstrapper just hands off execution once via `execv()`.

---

## License

MIT © 2026 [retired64](https://github.com/retired64)

OpenCode is developed by [anomalyco](https://github.com/anomalyco/opencode) and distributed under its own license.

