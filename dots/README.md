# dots

You describe which folders go where — `dots` lays everything out itself.

No stow. No 300-line `install.sh`. Just folders in your repo, one `dots.toml` and one command.

```
dots.py apply
```

That's it.

---

## What it does

- Puts files from your repo into place — as **symlinks** or as **copies**, you choose per folder
- Shows a diff before touching anything, and asks
- Backs up every file it replaces
- For files that other programs keep editing: remembers what the repo looked like last time, so a change in the repo can be **merged** into your live file without losing what the program added
- Cleans up links that point to files you renamed or removed from the repo
- Runs your commands after `apply`, skips files per machine, writes system files with sudo

---

## Requirements

- Python 3.11+ (`tomllib` — nothing to install)
- `git` — only for the `merge` option
- `sudo` — only for groups with `sudo = true`
- `nvim` or `vimdiff` — only for the `e` option

---

## Installation

It's a single file.

```bash
# download dots.py from this repository, then:
chmod +x dots.py
```

Put it into the root of your dotfiles repo, or into a subfolder such as `dots/`.
`dots.py` looks for `dots.toml` **next to itself, then one folder up**, so `dots/dots.py` finds the `dots.toml` in the repo root.

It works on a repo, so it is not meant to go into `$PATH`. If you want a short command, make an alias:

```bash
alias dots='~/dotfiles/dots/dots.py'
```

> The examples below write `./dots.py`; adjust the path if you keep it in a subfolder.

---

## Quick start

```bash
cd ~/my-dotfiles

# Step 1 — create a config
./dots.py init

# Step 2 — put files where they should end up
mkdir -p main/.config/nvim
cp -r ~/.config/nvim/. main/.config/nvim/

# Step 3 — see what will happen (changes nothing)
./dots.py check

# Step 4 — do it
./dots.py apply
```

Done. A file that already exists and is identical to the repo's is replaced by a symlink without asking.
A file that differs shows a diff and asks.

Now in more detail.

---

## How it works

```
~/dotfiles/                  ← your repo
├── dots/
│   ├── dots.py              ← the tool (not laid out anywhere)
│   ├── README.md
│   └── LICENSE.md
├── dots.toml                ← you edit this: groups, aliases, hooks, hosts
├── main/                    ← one folder per group, mirrors its target
│   └── .config/ghostty/config      →  ~/.config/ghostty/config
├── copy/
└── system/
    └── etc/sysctl.d/99-local.conf  →  /etc/sysctl.d/99-local.conf

~/<repo-folder>_bak/<date_time>/ ← old files, before they were replaced
~/.local/state/dots/base/    ← dots writes here itself, don't touch
```

A folder in the repo mirrors its target: `main/.config/foo` → `~/.config/foo`.
`dots` links or copies **files**, not whole directories, so programs can put their own files next to yours.

---

## Groups

A group is a folder of the repo + where it goes + how. It is described in `dots.toml`:

```toml
[groups.main]
description = "what I edit myself"
target = "~"                  # "~" = home, "/..." = filesystem root
mode   = "link"

[groups.copy]
description = "starter files that tools keep editing"
target = "~"
mode   = "seed"

[groups.system]
target  = "/"
mode    = "mirror"
sudo    = true
default = false               # only when named: ./dots.py apply system
```

### Modes

| Mode | What happens |
|------|--------------|
| `link` | A symlink into the repo. Edit the file in `~` or in the repo — it's the same file. |
| `seed` | Copied **once**. After that the file lives its own life: programs may edit it, and local edits are not reported while the repo version is unchanged. |
| `mirror` | Copied; the repo wins, every difference is shown. |

Use `link` for what you edit yourself, `seed` for what programs rewrite (so their junk never lands in git), `mirror` for files that must match the repo exactly.

### All keys of a group

| Key | What it does |
|-----|--------------|
| `target` | Where the folder is laid out (required). `~` is home, `/...` is the filesystem root |
| `mode` | `link`, `seed` or `mirror` (required) |
| `source` | Folder in the repo. Default: the group's name |
| `sudo` | Write with sudo (for `/etc`, `/var`, …) |
| `default` | `false` = only when the group is named explicitly |
| `hosts` | Only on these hostnames |
| `exclude` | Globs relative to the group's folder. A folder name covers everything inside it |
| `description` | Shown by `dots.py list` |

A file can belong to one group only — if two groups lay out the same path, `dots` stops and tells you.
A typo in a key, or a wrong `mode`, stops it with a message that names the section.

---

## Commands

### `dots.py check` — see what will change

Doesn't touch anything. Shows the status of every file and a diff for every difference.
Exit code is `1` if there is something to apply — handy for scripts.

```bash
./dots.py check

# Only specific groups
./dots.py check main copy
```

```
=== main  (main/ symlinks -> ~) ===
  new       ~/.config/ghostty/config
  ok        ~/.config/mpv/mpv.conf

=== copy  (copy/ copies -> ~) ===
  drift     ~/.config/foo/settings.conf  edited locally, repo seed unchanged - that's fine

=== summary ===
  new: 1, drift: 1   (ok: 1)
  this was only a check; to apply: ./dots.py apply
```

| Status | Meaning |
|--------|---------|
| `ok` | Already in place |
| `new` | Will be created (or an identical file will become a symlink) |
| `stale` | An old link into the repo — will be relinked, or replaced by a copy if the file moved to a `seed`/`mirror` group; also a link to a file that is no longer in the repo (will be removed) |
| `drift` | `seed` file edited locally, repo version unchanged — **fine**, nothing to do |
| `UPDATED` | The repo version changed since the last `apply` — a diff "previous → new" is shown |
| `DIFFERS` | The file exists and differs from the repo, and `dots` has no earlier version to compare with |
| `CONFLICT` | A real file (or a foreign symlink) sits where a link should be |
| `ERROR` | Something it can't fix alone, e.g. a directory in the way |

`check` exits with `1` if any of `new`, `stale`, `UPDATED`, `DIFFERS`, `CONFLICT` exist.

---

### `dots.py apply` — lay everything out

The main command. Does what `check` shows, and asks about every difference.

```bash
./dots.py apply

# Only specific groups
./dots.py apply main
```

For `seed` and `mirror` files you choose what to do:

| Key | What it does | When offered |
|-----|--------------|--------------|
| `y` | Take the repo version (your old file goes to the backup) | always |
| `m` | **Merge** the repo's changes into your file (3-way, `git merge-file`) | `UPDATED` |
| `e` | Open in `nvim -d` / `vimdiff` and decide hunk by hunk | always |
| `l` | Show the diff again | `UPDATED` |
| `n` | Skip (it will ask again next time) | always |
| `i` | Keep my file, treat this repo version as accepted | `UPDATED`; `DIFFERS` in `seed` groups |
| `q` | Quit | always |

For a `link` conflict the choices are `y` (replace with a symlink, old file → backup), `n`, `q`.

If stdin is not a terminal (a script, a pipe), nothing is asked: new files and stale links are fixed, everything that needs a decision is skipped.

Before anything is replaced, the old file goes to `~/<repo-folder>_bak/<date_time>/` (`<repo-folder>` is the name of the folder that holds `dots.toml`, e.g. `~/.dotfiles` → `~/.dotfiles_bak`).
A replaced symlink is saved as a text file `name.symlink` with its target. Files outside of `~` go to `_<group>/`.

Links to files that are no longer in any group (renamed, removed, excluded for this machine) are removed.
`check` only reports them.

---

### `dots.py delete` — remove the links

```bash
./dots.py delete
./dots.py delete main
```

Removes the symlinks of `link` groups (and links to files that are gone from the repo). `seed` copies stay. `mirror` copies under `~` are removed only if they are identical to the repo.
It never touches anything outside of `~`.

---

### `dots.py list` — what is configured

Shows every group, where it goes, how many files it has on this machine, and the aliases and hooks.

```bash
./dots.py list
```

```
  config: /home/user/dotfiles/dots.toml
  host:   laptop

  main       link    main/ -> ~             16 files
             what I edit myself
  system     mirror  system/ -> /            2 files   (sudo; only when named)

  aliases: links = main pkg copy
```

Handy to check someone else's config, or to see why a group is `OFF on this host`.

---

### `dots.py init` — create a config from scratch

Writes a commented starter `dots.toml` into the current folder.

```bash
./dots.py init
```

It won't overwrite an existing file.

---

### Aliases and `-c`

```toml
[aliases]
links = ["main", "copy"]
```

```bash
./dots.py links            # = ./dots.py apply main copy
./dots.py check links      # an alias works as a group name too
```

Another config: `./dots.py -c ~/other/dots.toml check` (or `DOTS_CONFIG`). Source folders are then relative to that file.

---

## After `git pull`

Just run `./dots.py apply` again. New links are added by themselves.

For `seed` and `mirror` files `dots` remembers the version it laid out last time (`~/.local/state/dots/base/`). If the repo version changed since then, you get:

```
  UPDATED   ~/.config/foo/settings.conf  repo seed changed since last time
    --- previous seed
    +++ new seed
    ...
```

Press `m` and the repo's change is merged into your live file — everything a program added to it stays.
If both sides touched the same lines, your editor opens with conflict markers.

`dots` never copies a live file **back** into the repo. For a `seed` file that a program changed, do it by hand when you actually want it:

```bash
diff ~/.config/foo/settings.conf copy/.config/foo/settings.conf
cp   ~/.config/foo/settings.conf copy/.config/foo/settings.conf
```

---

## Moving a file between groups

```bash
git mv main/.config/mpv/mpv.conf copy/.config/mpv/mpv.conf
./dots.py apply
```

`main → copy`: the symlink is replaced by a real copy (the old link goes to the backup), no questions asked — the content is in the repo anyway.
Until you run `apply` the link in `~` is broken.

`copy → main`: an identical file becomes a symlink silently; a different one shows a diff and asks.

---

## Hooks

Run your own command after `apply`, if a matching file was actually changed.

```toml
[[hook]]
match = ".config/fontconfig/*"         # glob relative to the group's target; a string or a list
run   = ["fc-cache", "-f"]

[[hook]]
group = "system"                       # optional: only for this group
match = "etc/sysctl.d/*"
run   = ["sudo", "sysctl", "--system"]
```

- Runs once per hook per `apply`, no matter how many files changed
- Doesn't run on `check`, and doesn't run if nothing changed
- `run` is a list (or a string, split like a shell would)
- If the command fails or doesn't exist, you see it — `apply` is already done by then

---

## Hosts

The same repo on several machines.

```toml
# files you don't want on this machine — globs "group/path"
[hosts.laptop]
exclude = ["main/.config/mpv/*"]

# a whole group only on some machines
[groups.nvidia]
target = "/"
mode   = "mirror"
sudo   = true
hosts  = ["desktop"]
```

The host name is the machine's hostname (or `DOTS_HOST`). Links to files that are excluded on this machine are cleaned up like any other stale link.

---

## Settings

All optional.

```toml
[settings]
backup_dir = "~/my_backups"           # where replaced files go (default: ~/<repo-folder>_bak)
state_dir  = "~/.local/state/dots"    # remembered previous versions (merge base)
ignore     = ["README*", "LICENSE*"]  # top-level files of a group folder that are not laid out
prune      = ["my-big-folder"]        # extra folders skipped when looking for stale links
difftool   = "nvim -d"                # for `e` ($DIFFTOOL wins)
```

`ignore` replaces the default list (`README*`, `LICENSE*`, `COPYING*`, `.stow-local-ignore`, `.gitkeep`), so write it in full if you change it.

---

## Environment variables

```bash
DOTS_CONFIG        # path to dots.toml (same as -c)
DOTS_HOME          # replaces ~
DOTS_SYSTEM_ROOT   # replaces /
DOTS_HOST          # replaces the hostname
DIFFTOOL           # for the `e` option
VISUAL / EDITOR    # for merge conflicts
NO_COLOR           # no colors
```

Useful for trying a config without any risk:

```bash
DOTS_HOME=/tmp/h DOTS_SYSTEM_ROOT=/tmp/r DOTS_HOST=laptop ./dots.py check
```

---

## Typical workflow

```bash
# Edit a link file — it IS the repo file
$EDITOR ~/.config/ghostty/config
git commit -am "ghostty"

# Add a new file
cp ~/.config/foo/bar.conf main/.config/foo/bar.conf
./dots.py apply                  # the original becomes a symlink

# Moving to a new machine
git clone ... ~/dotfiles && cd ~/dotfiles
./dots.py check                  # what will happen
./dots.py apply

# After git pull
./dots.py apply                  # new links, a diff + merge for changed copies
```
