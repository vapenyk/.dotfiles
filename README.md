# vapenyk dotfiles

Arch Linux - Hyprland

## install

```bash
sudo pacman -S git python base-devel
git clone https://github.com/vapenyk/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dots/dots.py apply pkg     # symlinks for the package manager (first run only)
~/.local/bin/pkg sync --exclude intel-ultra-125h ly-tty       # install packages + lay out the rest
reboot
```

`pkg sync` ends with `after-sync.sh`, which runs `dots apply all`, enables services, clones/updates mshell and runs `mise install`. If `dots` needs a decision on a file, run `./dots/dots.py apply` by hand.

After the reboot, in the Hyprland session (gh and rbw need the keyring and pinentry):

```bash
~/.dotfiles/scripts/post-install.sh   # rbw, gh, agent skills, MCP servers, ollama model
```

Before that, put these notes in Bitwarden (key on the first line): `penpot-mcp-token`, `context7-api-key`.

After `git pull` run `./dots/dots.py apply all` again (or just `pkg sync`).

## tools

- **[dots](./dots/README.md)** — lays the folders above out: symlinks, copies, diffs, 3-way merge, hooks. A single Python file driven by `dots.toml`. [MIT](./dots/LICENSE.md)
- **[pkg](./pkg/README.md)** — a single-file, declarative package manager wrapper, inspired by pacdef/metapac. [MIT](./pkg/LICENSE.md)

System files (`system/`, currently the ollama override) are applied to `/` with sudo as part of `apply all`.

## Asus VIVOBOOK 15 OLED S5506

Add a kernel parameter for xe graphics.

Add `i915.force_probe=!7d55 xe.force_probe=7d55`

## thanks

[codeberg.org/zacoons/dots](https://codeberg.org/zacoons/dots) for inspiration.

## license

[MIT](LICENSE.md)
