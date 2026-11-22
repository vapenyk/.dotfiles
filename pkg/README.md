# pkg

You describe which packages you want — `pkg` installs everything itself.

No 200-line scripts. No "did I install this thing via flatpak or pacman?". Just package files and one command.

```
pkg sync
```

That's it.

---

## What it does

- Installs packages via **pacman**, **paru** (AUR), **flatpak**, **uv**, **apt**
- Checks what's already installed — doesn't reinstall unnecessarily
- Runs your scripts before and after installation
- Shows what will change before doing anything
- Removes what you've deleted from the config

---

## Requirements

- Python 3.11+
- Arch Linux — for pacman/paru/uv backends
- Ubuntu/Debian — for the apt backend

---

## Installation

```bash
# download the pkg file from this repository, then:
install -Dm755 pkg ~/.local/bin/pkg
```

Or just copy the `pkg` file anywhere in your `$PATH`.

---

## Quick start

```bash
# Step 1 — create a config
pkg init

# Step 2 — write what you want to install
$EDITOR ~/.config/pkg/packages/base.toml

# Step 3 — install everything
pkg sync
```

Done. Now in more detail.

---

## How it works

All files live in two places:

```
~/.config/pkg/               ← you edit this
├── backends.toml            ← pacman, apt, flatpak, etc. settings
├── packages/                ← your package lists
│   ├── base.toml
│   ├── apps.toml
│   └── work.toml            ← you can add any files
└── scripts/                 ← scripts that run during sync
    ├── before-sync.sh
    ├── after-sync.sh
    └── after-neovim.sh      ← can be for a specific package

~/.local/share/pkg/          ← pkg writes here itself, don't touch
└── installed.toml           ← list of what pkg has already installed
```

---

## Package files

Each `.toml` file in `packages/` is a **group**. The filename = the group name.

Inside you specify which backend to use for installation:

```toml
# ~/.config/pkg/packages/base.toml

[group]
display     = "Base tools"
description = "Everything you need in the terminal"
priority    = 10              # lower = installed first

[pacman]
packages = [
  "git",
  "neovim",
  "ripgrep",
  "bat",
  "fzf",
  "btop",
]

[paru]
packages = [
  "maplemono-nf-unhinted",   # AUR package
]

[uv]
packages = [
  "terminaltexteffects",     # Python CLI tool
]
```

```toml
# ~/.config/pkg/packages/apps.toml

[group]
display  = "GUI apps"
priority = 40

[flatpak]
packages = [
  "org.telegram.desktop",
  "md.obsidian.Obsidian",
  "com.github.tchx84.Flatseal",
]
```

```toml
# ~/.config/pkg/packages/system.toml
# example for Ubuntu/Debian

[group]
display  = "System packages"
priority = 5

[apt]
packages = [
  "git",
  "curl",
  "neovim",
  "ripgrep",
  "bat",
  "fzf",
  "btop",
  "build-essential",
]
```

You can mix any backends in a single file. `priority` determines the order — groups with a lower number are installed first.

---

## Commands

### `pkg sync` — install everything

The main command. Looks at all groups, checks what's already installed, installs everything that's missing.

```bash
pkg sync
```

```bash
# Install only specific groups
pkg sync base apps

# Install everything except flatpak
pkg sync --exclude flatpak

# Continue even if something fails to install
pkg sync --skip-errors

# Stop if a hook script exits with an error
pkg sync --strict-hooks
```

Under the hood, instead of 30 separate `pacman -S pkg` calls, it makes one:

```
sudo pacman -S git neovim ripgrep bat fzf btop ...
```

---

### `pkg diff` — see what will change

Doesn't touch the system. Just shows what will be installed on the next `sync`.

```bash
pkg diff

# Check only specific groups
pkg diff base apps

# Exclude a group
pkg diff --exclude flatpak
```

Example output:

```
  Will install:
  + [pacman] bat
  + [pacman] fzf
  + [flatpak] org.telegram.desktop

  Not in config (run prune to remove):
  - [pacman] micro
```

Handy to run after editing configs — to verify everything looks right before the actual installation.

---

### `pkg prune` — remove leftovers

Finds packages that `pkg` once installed but that are no longer in the config. Asks one by one — remove or skip.

```bash
pkg prune
```

```
  3 package(s) no longer in config:

  - [pacman] micro
  - [pacman] nano
  - [flatpak] com.protonvpn.www

  Remove [pacman] micro? [y/N] y
  ✓ [pacman] micro removed
  Remove [pacman] nano? [y/N] n
  → Skipping nano
  Remove [flatpak] com.protonvpn.www? [y/N] y
  ✓ [flatpak] com.protonvpn.www removed

  ✓ Pruned 2, skipped 1.
```

**Important:** packages you installed manually via `pacman -S` or `apt install` are not touched. `prune` only sees what `pkg` itself installed.

---

### `pkg status` — system state

Shows all backends (available or not) and how many packages from each group are already installed.

```bash
pkg status
```

```
Backends
──────────────────────────────────────────────────
  [pacman]    ✓ ok   Official Arch repos
  [paru]      ✓ ok   AUR helper
  [flatpak]   ✓ ok   Flatpak / Flathub
  [uv]        ✓ ok   Python CLI tools
  [apt]       ✗ missing   Ubuntu/Debian packages

Groups
──────────────────────────────────────────────────
  base        12/12  installed   Base tools
  apps        3/5    installed   GUI apps
  work        0/8    installed   Work tools

Paths
  Config: /home/user/.config/pkg
  State:  /home/user/.local/share/pkg/installed.toml
```

---

### `pkg list` — list installed packages

Shows everything `pkg` is tracking, grouped by backend.

```bash
pkg list
```

```
Installed
──────────────────────────────────────────────────

  pacman  (8)
    • bat
    • btop
    • fzf
    • git
    • neovim
    • ripgrep

  flatpak  (2)
    • md.obsidian.Obsidian
    • org.telegram.desktop

  Total: 10 across 2 backends
```

---

### `pkg groups` — list groups

Shows all available groups from the `packages/` folder.

```bash
pkg groups
```

```
Groups
──────────────────────────────────────────────────

  base    priority=10   12 pkgs  [pacman, paru, uv]
    Base tools

  apps    priority=40   5 pkgs   [flatpak]
    GUI apps

  work    priority=50   8 pkgs   [apt, uv]
    Work tools
```

---

### `pkg init` — create a config from scratch

Creates all folders and files with default content.

```bash
pkg init

# Overwrite existing files
pkg init --force
```

After `pkg init` you'll have a ready-to-use config — just edit the package lists.

---

## Hooks (scripts)

You can run your own scripts at any point during the installation process. Drop a `.sh` file into `~/.config/pkg/scripts/` and it runs automatically.

### Execution order

```
before-sync.sh
  └── before-pacman.sh         before installing packages via pacman
        └── before-neovim.sh   before installing a specific package
              [neovim installs]
        └── after-neovim.sh    immediately after installation
  └── after-pacman.sh          after all pacman packages
after-sync.sh
```

Per-package hooks fire **only** if the package is actually being installed (i.e. it wasn't there before). If the package is already installed — the hook doesn't run.

### All available files

| File                  | When it runs                                                |
| --------------------- | ----------------------------------------------------------- |
| `before-sync.sh`      | Very first — before everything                              |
| `after-sync.sh`       | Very last — after everything                                |
| `before-{backend}.sh` | Before packages from that backend (e.g. `before-pacman.sh`) |
| `after-{backend}.sh`  | After packages from that backend                            |
| `before-{package}.sh` | Before a specific package (e.g. `before-neovim.sh`)         |
| `after-{package}.sh`  | After a specific package                                    |

For flatpak use the full app ID: `after-org.telegram.desktop.sh`

`before-sync.sh` and `after-sync.sh` run on **every** `pkg sync`, so write them to be safe to run repeatedly (check before you change something).

Scripts must be executable:

```bash
chmod +x ~/.config/pkg/scripts/after-neovim.sh
```

### Environment variables inside hooks

```bash
$PKG_EVENT        # event name, e.g. "after-neovim"
$PKG_CONFIG_DIR   # path to ~/.config/pkg
$PKG_DATA_DIR     # path to ~/.local/share/pkg
```

### Hook examples

**`after-sync.sh`** — enable a service after everything is installed:

```bash
#!/usr/bin/env bash
set -euo pipefail
systemctl is-enabled --quiet NetworkManager || sudo systemctl enable --now NetworkManager
```

**`after-neovim.sh`** — install plugin manager right after neovim:

```bash
#!/usr/bin/env bash
set -euo pipefail
lazy_path="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"
if [[ ! -d "$lazy_path" ]]; then
  git clone --filter=blob:none https://github.com/folke/lazy.nvim.git \
    --branch=stable "$lazy_path"
fi
```

**`after-org.telegram.desktop.sh`** — grant filesystem access:

```bash
#!/usr/bin/env bash
set -euo pipefail
flatpak override --user --filesystem=home org.telegram.desktop
```

**`before-paru.sh`** — warn that it'll take a while:

```bash
#!/usr/bin/env bash
echo "AUR packages are about to build. Go make some tea."
```

---

## backends.toml

Usually you don't need to touch this — `pkg init` creates a ready-made file. But if you want to add a custom backend or change flags — here's how it works:

```toml
[backends.pacman]
description    = "Official Arch repos"
check_cmd      = ["which", "pacman"]
install_pkg    = ["sudo", "pacman", "-S", "--noconfirm", "--needed"]
remove_pkg     = ["sudo", "pacman", "-Rns", "--noconfirm"]
list_installed = ["pacman", "-Qq"]
```

### All fields

| Field                 | What it does                                                                    |
| --------------------- | ------------------------------------------------------------------------------- |
| `check_cmd`           | Checks that the backend is available (exit 0 = present)                         |
| `install_self`        | How to install the backend itself if it's missing                               |
| `install_self_try`    | Try this first; if it fails — run the script                                    |
| `install_self_script` | A script in `scripts/` for complex installation (e.g. building paru from AUR)   |
| `after_install_self`  | Commands to run after the backend is installed (e.g. add Flathub remote)        |
| `update_cmd`          | Run once before installation if there's anything to install (e.g. `apt update`) |
| `install_pkg`         | Installation command prefix (package names are appended at the end)             |
| `remove_pkg`          | Removal command prefix                                                          |
| `list_installed`      | Outputs a list of installed packages — one per line                             |
| `list_strip_version`  | `true` if output is in `"name version"` format (strip the version)              |
| `install_one_by_one`  | `true` for backends that don't support batch installs (e.g. uv)                 |

### Ready-made backends

**pacman** (Arch):

```toml
[backends.pacman]
description    = "Official Arch repos"
check_cmd      = ["which", "pacman"]
install_pkg    = ["sudo", "pacman", "-S", "--noconfirm", "--needed"]
remove_pkg     = ["sudo", "pacman", "-Rns", "--noconfirm"]
list_installed = ["pacman", "-Qq"]
```

**paru** (AUR):

```toml
[backends.paru]
description         = "AUR helper"
check_cmd           = ["which", "paru"]
install_self_try    = ["sudo", "pacman", "-S", "--noconfirm", "--needed", "paru"]
install_self_script = "bootstrap-paru.sh"
install_pkg         = ["paru", "-S", "--noconfirm", "--needed"]
remove_pkg          = ["paru", "-Rns", "--noconfirm"]
list_installed      = ["pacman", "-Qq"]
```

**flatpak**:

```toml
[backends.flatpak]
description        = "Flatpak / Flathub"
check_cmd          = ["which", "flatpak"]
install_self       = ["sudo", "pacman", "-S", "--noconfirm", "--needed", "flatpak"]
after_install_self = [
  ["flatpak", "remote-add", "--if-not-exists", "flathub",
   "https://dl.flathub.org/repo/flathub.flatpakrepo"],
]
install_pkg    = ["flatpak", "install", "-y", "--noninteractive", "flathub"]
remove_pkg     = ["flatpak", "uninstall", "-y", "--noninteractive"]
list_installed = ["flatpak", "list", "--app", "--columns=application"]
```

**uv** (Python CLI tools):

```toml
[backends.uv]
description        = "Python CLI tools"
check_cmd          = ["which", "uv"]
install_self       = ["sudo", "pacman", "-S", "--noconfirm", "--needed", "uv"]
install_pkg        = ["uv", "tool", "install"]
remove_pkg         = ["uv", "tool", "uninstall"]
list_installed     = ["uv", "tool", "list", "--quiet"]
list_strip_version = true
install_one_by_one = true
```

**apt** (Ubuntu/Debian):

```toml
[backends.apt]
description    = "Ubuntu/Debian system packages"
check_cmd      = ["which", "apt"]
update_cmd     = ["sudo", "apt", "update", "-qq"]
install_pkg    = ["sudo", "apt", "install", "-y"]
remove_pkg     = ["sudo", "apt", "remove", "-y"]
list_installed = ["dpkg-query", "-f", "${Package}\n", "-W"]
```

---

## installed.toml

pkg records what it has installed in `~/.local/share/pkg/installed.toml`. This is a regular human-readable file:

```toml
[pacman]
packages = [
  "bat",
  "btop",
  "git",
  "neovim",
]

[flatpak]
packages = [
  "md.obsidian.Obsidian",
  "org.telegram.desktop",
]
```

The file is only used for `prune` — to distinguish packages installed by `pkg` from ones you installed manually. You can keep it under version control.

---

## Environment variables

```bash
PKG_CONFIG_DIR   # override ~/.config/pkg
PKG_DATA_DIR     # override ~/.local/share/pkg
```

Useful for testing without risk of breaking anything:

```bash
PKG_CONFIG_DIR=/tmp/testpkg pkg sync --skip-errors
```

---

## Typical workflow

```bash
# Want to add a package
$EDITOR ~/.config/pkg/packages/base.toml
pkg diff          # see what will change
pkg sync          # install

# Want to remove a package
$EDITOR ~/.config/pkg/packages/base.toml   # remove from the list
pkg prune         # pkg will ask what to delete

# Moving to a new machine
pkg init
# copy your backends.toml, packages/ and scripts/ into ~/.config/pkg
pkg sync          # everything is installed
```
