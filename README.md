# vapenyk dotfiles

Arch Linux - Hyprland

## install

```bash
sudo pacman -S git python
git clone https://github.com/vapenyk/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./dots/dots.py apply pkg     # symlinks for the package manager
~/.local/bin/pkg sync --exclude intel-ultra-125h ly-tty       # install packages
./dots/dots.py check         # what will change (changes nothing)
./dots/dots.py apply         # lay out everything, a diff + question for every difference
```

After `git pull` run `./dots/dots.py apply` again.

## tools

- **[dots](./dots/README.md)** — lays the folders above out: symlinks, copies, diffs, 3-way merge, hooks. A single Python file driven by `dots.toml`. [MIT](./dots/LICENSE.md)
- **[pkg](./pkg/README.md)** — a single-file, declarative package manager wrapper, inspired by pacdef/metapac. [MIT](./pkg/LICENSE.md)

`pkg sync` also installs Superwhisper via its official install script (`pkg/.config/pkg/scripts/after-sync.sh`).

## Asus VIVOBOOK 15 OLED S5506

Add a kernel parameter for xe graphics.

Add `i915.force_probe=!7d55 xe.force_probe=7d55`

## thanks

[codeberg.org/zacoons/dots](https://codeberg.org/zacoons/dots) for inspiration.

## license

[MIT](LICENSE.md)
