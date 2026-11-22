#!/usr/bin/env python3
"""
dots - lay out dotfiles from a repo. Everything is described in dots.toml, which is looked for
next to this script and then one folder up (so dots/dots.py works with dots.toml in the repo root).

  dots.py check  [group...]   changes nothing: status + diff (exit 1 if there is something to apply)
  dots.py apply  [group...]   lay out; a diff and a question for every difference
  dots.py delete [group...]   remove our symlinks (copies stay)
  dots.py list                groups from dots.toml and what they resolve to on this machine
  dots.py init                write a starter dots.toml in the current folder
  dots.py <alias>             an alias from [aliases] = apply of those groups

  -c, --config FILE           use another config (or $DOTS_CONFIG); source folders are relative to that file

A group = a folder of the repo + where it goes + how:
  link    symlinks into the repo
  seed    copied once; afterwards the file lives its own life (tools may edit it);
          if the repo version changes you get a diff and can merge it (3-way) into your file
  mirror  copied; the repo wins, every difference is shown

Before anything is replaced, the old file goes to <backup_dir>/<date_time>/.
Testing in a sandbox: DOTS_HOME=/tmp/h DOTS_SYSTEM_ROOT=/tmp/r DOTS_HOST=name ./dots.py check
Needs Python 3.11+ (tomllib), no other dependencies.
"""
import difflib
import fnmatch
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit("dots.py needs Python 3.11+ (tomllib)")
import tomllib

# --- environment -------------------------------------------------------------

# DOTS_HOME / DOTS_SYSTEM_ROOT replace $HOME and / (for testing in a sandbox)
HOME = Path(os.environ.get("DOTS_HOME") or Path.home())
ROOT = Path(os.environ.get("DOTS_SYSTEM_ROOT") or "/")
HOST = os.environ.get("DOTS_HOST") or socket.gethostname()

DEFAULT_IGNORE = ["README*", "LICENSE*", "COPYING*", ".stow-local-ignore", ".gitkeep"]
# where not to look when searching for orphaned symlinks
DEFAULT_PRUNE = [".git", "node_modules", ".cache", "cache", "Cache", "mozilla", ".mozilla",
                 "chromium", "google-chrome", "BraveSoftware"]
KINDS = ("link", "seed", "mirror")
PENDING = {"new", "stale", "conflict", "updated", "differs"}  # check exits with 1 if any of these exist

# filled in by load()
CONFIG = None
REPO = None
REPO_PATHS = set()
GROUPS = []
ALIASES = {}
HOOKS = []
SETTINGS = {}
IGNORE_TOP = DEFAULT_IGNORE
PRUNE = set(DEFAULT_PRUNE)
HOST_EXCLUDE = []
BACKUP_ROOT = HOME / ".dots_bak"  # replaced in load(): ~/<repo folder>_bak unless [settings] backup_dir is set
STATE = HOME / ".local/state/dots"  # the "previous seed" of every copy file lives here (merge base)


@dataclass(frozen=True)
class Group:
    name: str
    source: str       # folder in the repo
    root: Path        # where to lay it out
    kind: str         # link   - symlink to the repo
                      # seed   - copy; the file lives on its own afterwards, edits by tools are fine
                      # mirror - copy; the repo wins, every difference is shown
    sudo: bool = False
    default: bool = True      # part of a bare `apply` / `check`
    hosts: tuple = ()         # only on these hostnames (empty = everywhere)
    exclude: tuple = ()       # globs relative to the source folder
    description: str = ""


# --- helpers -----------------------------------------------------------------

COLOR = sys.stdout.isatty() and "NO_COLOR" not in os.environ
STATS = Counter()
VERBOSE = False
CHANGED = []  # (group, path relative to the group's target) of everything we wrote - for hooks
_bak = None   # backup folder of this run (created on the first backup)


class Quit(Exception):
    pass


def die(msg):
    sys.exit(f"dots: {msg}")


def c(code, s):
    return f"\033[{code}m{s}\033[0m" if COLOR else str(s)


def title(s):
    print(f"\n{c(1, f'=== {s} ===')}")


def label(p):
    try:
        return "~/" + str(p.relative_to(HOME))
    except ValueError:
        return str(p)


def where(p):
    return "~" if p == HOME else label(p)


def under_home(p):
    return p == HOME or HOME in p.parents


STYLE = {"ok": (2, "ok"), "new": (32, "new"), "stale": (33, "stale"), "drift": (34, "drift"),
         "conflict": (31, "CONFLICT"), "updated": (33, "UPDATED"), "differs": (31, "DIFFERS"),
         "error": (31, "ERROR")}


def say(status, dst, note=""):
    STATS[status] += 1
    if status == "ok" and not VERBOSE:
        return
    col, word = STYLE[status]
    print(f"  {c(col, f'{word:9}')} {label(dst)}" + (c(2, f"  {note}") if note else ""))


def done(text):
    STATS[text] += 1
    print(f"    {c(32, '->')} {text}")


def is_link(p):
    try:
        return p.is_symlink()
    except OSError:
        return False


def link_target(p):
    """Where a symlink points (absolute path, not resolved) or None."""
    try:
        t = os.readlink(p)
    except OSError:
        return None
    return Path(os.path.normpath(os.path.join(p.parent, t)))


def inside_repo(p):
    return p is not None and any(r in p.parents for r in REPO_PATHS)


def is_ours(p):
    """Symlink p is ours: it points into a source folder of the repo, or to nowhere inside the repo
    (the file was removed/renamed). Links to other repo files (scripts/ ...) are left alone."""
    t = link_target(p)
    if not inside_repo(t):
        return False
    return not t.exists() or any(r / g.source in t.parents for r in REPO_PATHS for g in GROUPS)


def parent_in_repo(p):
    """A parent directory is a symlink into the repo (stow-folded): writing through it would clobber the repo file."""
    return any(is_link(q) and inside_repo(link_target(q)) for q in p.parents)


def read_live(dst, sudo=False):
    """File content (a symlink is read through its target) or None if the file does not exist."""
    try:
        return dst.read_bytes()
    except (FileNotFoundError, NotADirectoryError):
        return None
    except PermissionError:
        if not sudo:
            raise
    r = subprocess.run(["sudo", "cat", str(dst)], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def show_diff(a, b, la, lb):
    """Colored unified diff of two byte strings (a may be None)."""
    if (a and b"\0" in a) or b"\0" in b:
        print("    (binary file, differs)")
        return
    A = (a or b"").decode(errors="replace").splitlines(keepends=True)
    B = b.decode(errors="replace").splitlines(keepends=True)
    lines = list(difflib.unified_diff(A, B, la, lb))
    if not lines:
        print(c(2, "    (only invisible bytes differ)"))
    for line in lines:
        line = line.rstrip("\n")
        col = 36 if line.startswith("@@") else 2 if line[:3] in ("---", "+++") else \
            32 if line[0] == "+" else 31 if line[0] == "-" else 0
        print("    " + (c(col, line) if col else line))


OPTS = {
    "y": "take the repo version (old one -> backup)",
    "m": "merge: apply the repo's changes to my file",
    "e": "open in vimdiff and decide hunk by hunk",
    "l": "show diff 'mine <-> repo'",
    "n": "skip (will ask again next time)",
    "i": "keep my file, treat this repo version as accepted",
    "q": "quit",
}


def ask(opts, labels=None):
    if not sys.stdin.isatty():
        print(c(2, "    (not interactive - skipping)"))
        return "n"
    text = {**OPTS, **(labels or {})}
    print("    " + "   ".join(f"[{o}] {text[o]}" for o in opts))
    while True:
        try:
            a = input("    > ").strip().lower()
        except EOFError:
            raise Quit
        if a == "q":
            raise Quit
        if a in opts:
            return a


# --- config ------------------------------------------------------------------

TEMPLATE = """\
# dots.toml - tells dots.py what to lay out and where.
#
# Paths: "~" is your home, "/..." is the filesystem root.
# Source folders are relative to this file and mirror their target:
#   main/.config/foo  ->  ~/.config/foo

[settings]
# backup_dir = "~/<repo-folder>_bak"    # old files go here before they are replaced (default: ~/<name of the repo folder>_bak)
# state_dir  = "~/.local/state/dots"    # remembered previous version of copied files (merge base)
# ignore     = ["README*", "LICENSE*"]  # top-level files of a source folder that are not laid out
# difftool   = "nvim -d"                # for manual conflict resolution ($DIFFTOOL wins)

# mode:  link   - symlink into the repo (same file in the repo and in ~)
#        seed   - copied once; afterwards the file lives its own life, repo changes are offered as a merge
#        mirror - copied; the repo wins, every difference is shown
[groups.main]
description = "what I edit myself"
target = "~"
mode = "link"

[groups.copy]
description = "starter files that tools keep editing"
target = "~"
mode = "seed"

# [groups.system]
# target = "/"
# mode = "mirror"
# sudo = true               # write with sudo
# default = false           # only when named: ./dots.py apply system
# hosts = ["myhost"]        # only on this machine (hostname)
# exclude = ["etc/foo/*"]   # globs relative to the group folder
# source = "system"         # folder name in the repo, default = group name

# [aliases]
# links = ["main", "copy"]  # ./dots.py links  ==  ./dots.py apply main copy

# after apply, run a command if any matching file was changed
# [[hook]]
# match = ".config/fontconfig/*"    # glob relative to the group's target (string or list)
# group = "main"                    # optional
# run = ["fc-cache", "-f"]

# per-machine exclusions: globs "group/path"
# [hosts.laptop]
# exclude = ["main/.config/mpv/*"]
"""

TOP_KEYS = {"settings", "groups", "aliases", "hook", "hosts"}
SETTINGS_KEYS = {"backup_dir", "state_dir", "ignore", "prune", "difftool"}
GROUP_KEYS = {"description", "source", "target", "mode", "sudo", "default", "hosts", "exclude"}
HOOK_KEYS = {"match", "group", "run", "description"}


def keys_ok(where_, d, allowed):
    bad = sorted(set(d) - allowed)
    if bad:
        die(f"{where_}: unknown key(s): {', '.join(bad)} (allowed: {', '.join(sorted(allowed))})")


def as_list(where_, v):
    v = [v] if isinstance(v, str) else v
    if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
        die(f"{where_}: expected a string or a list of strings")
    return v


def expand(where_, s):
    """'~' = HOME, an absolute path lives under ROOT (both can be replaced for testing)."""
    if s == "~" or s.startswith("~/"):
        return HOME / s[2:]
    if s.startswith("/"):
        return ROOT / s.lstrip("/")
    die(f"{where_}: path must start with ~ or /, got {s!r}")


def config_path(arg):
    given = arg or os.environ.get("DOTS_CONFIG")
    if given:
        p = Path(given).expanduser()
        if not p.is_file():
            die(f"config not found: {p}")
        return p
    # next to dots.py, then one folder up (so dots/dots.py finds dots.toml in the repo root);
    # both the real path and the path it was called by (dots.py may be a symlink)
    scripts = (Path(__file__).resolve(), Path(os.path.abspath(__file__)))
    bases = []
    for d in [s.parent for s in scripts] + [s.parent.parent for s in scripts]:
        if d not in bases:
            bases.append(d)
    for base in bases:
        if (base / "dots.toml").is_file():
            return base / "dots.toml"
    die("dots.toml not found next to dots.py or one folder up. "
        "Create a starter one in your repo with: dots.py init")


def load(arg):
    global CONFIG, REPO, REPO_PATHS, GROUPS, ALIASES, HOOKS, SETTINGS, IGNORE_TOP, PRUNE, HOST_EXCLUDE
    global BACKUP_ROOT, STATE
    CONFIG = config_path(arg)
    try:
        raw = tomllib.loads(CONFIG.read_text())
    except tomllib.TOMLDecodeError as e:
        die(f"{CONFIG}: {e}")
    keys_ok(str(CONFIG), raw, TOP_KEYS)

    REPO = CONFIG.resolve().parent
    REPO_PATHS = {REPO, Path(os.path.abspath(CONFIG)).parent}

    SETTINGS = raw.get("settings", {})
    keys_ok("[settings]", SETTINGS, SETTINGS_KEYS)
    BACKUP_ROOT = expand("[settings] backup_dir", SETTINGS.get("backup_dir", f"~/{REPO.name}_bak"))
    STATE = expand("[settings] state_dir", SETTINGS.get("state_dir", "~/.local/state/dots"))
    IGNORE_TOP = as_list("[settings] ignore", SETTINGS.get("ignore", DEFAULT_IGNORE))
    PRUNE = set(DEFAULT_PRUNE) | set(as_list("[settings] prune", SETTINGS.get("prune", [])))

    GROUPS = []
    for name, o in raw.get("groups", {}).items():
        w = f"[groups.{name}]"
        keys_ok(w, o, GROUP_KEYS)
        if "target" not in o:
            die(f"{w}: target is required")
        if o.get("mode") not in KINDS:
            die(f"{w}: mode must be one of {', '.join(KINDS)} (got {o.get('mode')!r})")
        source = o.get("source", name)
        if Path(source).is_absolute() or ".." in Path(source).parts:
            die(f"{w}: source must be a folder inside the repo, got {source!r}")
        GROUPS.append(Group(
            name=name, source=source, root=expand(f"{w} target", o["target"]), kind=o["mode"],
            sudo=bool(o.get("sudo", False)) and ROOT == Path("/") and os.geteuid() != 0,
            default=bool(o.get("default", True)),
            hosts=tuple(as_list(f"{w} hosts", o.get("hosts", []))),
            exclude=tuple(as_list(f"{w} exclude", o.get("exclude", []))),
            description=str(o.get("description", ""))))
    if not GROUPS:
        die(f"{CONFIG}: no [groups.*] defined")
    names = {g.name for g in GROUPS}

    ALIASES = {}
    for a, lst in raw.get("aliases", {}).items():
        lst = as_list(f"[aliases] {a}", lst)
        if a in names or a in ("apply", "check", "delete", "list", "init", "help"):
            die(f"[aliases] {a}: name is taken")
        bad = [x for x in lst if x not in names]
        if bad:
            die(f"[aliases] {a}: no such group: {' '.join(bad)}")
        ALIASES[a] = lst

    HOOKS = []
    for i, h in enumerate(raw.get("hook", []), 1):
        w = f"[[hook]] #{i}"
        keys_ok(w, h, HOOK_KEYS)
        if "match" not in h or "run" not in h:
            die(f"{w}: match and run are required")
        run = shlex.split(h["run"]) if isinstance(h["run"], str) else as_list(f"{w} run", h["run"])
        if not run:
            die(f"{w}: run is empty")
        if h.get("group") and h["group"] not in names:
            die(f"{w}: no such group: {h['group']}")
        HOOKS.append({"match": as_list(f"{w} match", h["match"]), "group": h.get("group"), "run": run})

    host = raw.get("hosts", {}).get(HOST, {})
    keys_ok(f"[hosts.{HOST}]", host, {"exclude"})
    HOST_EXCLUDE = as_list(f"[hosts.{HOST}] exclude", host.get("exclude", []))


def active(g):
    return not g.hosts or HOST in g.hosts


def matches(path, patterns):
    """Glob match; a pattern naming a directory also covers everything inside it."""
    return any(fnmatch.fnmatch(path, p) or fnmatch.fnmatch(path, p.rstrip("/") + "/*") for p in patterns)


# --- files, backup, writing --------------------------------------------------

def pairs(g):
    """All files of a group: (file in the repo, where it should end up)."""
    base = REPO / g.source
    if not active(g) or not base.is_dir():
        return
    for src in sorted(base.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(base)
        if len(rel.parts) == 1 and any(fnmatch.fnmatch(rel.name, p) for p in IGNORE_TOP):
            continue
        r = rel.as_posix()
        if matches(r, g.exclude) or matches(f"{g.name}/{r}", HOST_EXCLUDE):
            continue
        yield src, g.root / rel


def changed(g, dst):
    CHANGED.append((g, dst.relative_to(g.root).as_posix()))


def backup(g, dst):
    """Put the current dst into <backup_dir>/<date_time>/... (a symlink is saved as text with its target)."""
    global _bak
    if _bak is None:
        _bak = BACKUP_ROOT / time.strftime("%Y-%m-%d_%H%M%S")
    rel = dst.relative_to(HOME) if under_home(dst) else Path(f"_{g.name}") / dst.relative_to(g.root)
    out = _bak / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    if is_link(dst):
        Path(f"{out}.symlink").write_text(f"{os.readlink(dst)}\n")
    elif g.sudo:
        data = read_live(dst, True)
        if data is not None:
            out.write_bytes(data)
    elif dst.is_file():
        shutil.copy2(dst, out)


def put(g, dst, data, mode):
    """Write a file in one piece, atomically (a program watching its config never sees half a file)."""
    if g.sudo:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td) / "f"
            tmp.write_bytes(data)
            subprocess.run(["sudo", "install", f"-Dm{mode:o}", str(tmp), str(dst)], check=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_name(f".{dst.name}.dots-tmp")
        tmp.write_bytes(data)
        tmp.chmod(mode)
        os.replace(tmp, dst)  # if dst was a symlink, the symlink itself is replaced, not the file in the repo
    changed(g, dst)


def relink(g, src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(f".{dst.name}.dots-tmp")
    if is_link(tmp) or tmp.exists():
        tmp.unlink()
    tmp.symlink_to(src)
    os.replace(tmp, dst)
    changed(g, dst)


def save_base(bpath, data):
    bpath.parent.mkdir(parents=True, exist_ok=True)
    bpath.write_bytes(data)


# --- link --------------------------------------------------------------------

def handle_link(g, src, dst, apply):
    if parent_in_repo(dst):
        return say("error", dst, "parent dir is a symlink into the repo (stow folding), fix it by hand")
    if is_link(dst):
        tgt = link_target(dst)
        if tgt == src or (tgt.exists() and tgt.samefile(src)):
            return say("ok", dst)
        if inside_repo(tgt):  # old link into the repo (stow, moved folders) - relink it ourselves
            say("stale", dst, "old link into the repo -> relinking")
            if apply:
                relink(g, src, dst)
            return
        return conflict_link(g, src, dst, apply, f"symlink -> {tgt}")
    if not dst.exists():
        say("new", dst)
        if apply:
            relink(g, src, dst)
        return
    if dst.is_dir():
        return say("error", dst, "there is a directory in its place")
    if dst.read_bytes() == src.read_bytes():  # identical file - replace it with a symlink without asking
        say("new", dst, "identical file -> replacing with a symlink")
        if apply:
            relink(g, src, dst)
        return
    conflict_link(g, src, dst, apply, "")


def conflict_link(g, src, dst, apply, note):
    say("conflict", dst, note)
    show_diff(read_live(dst), src.read_bytes(), "mine", "repo")
    if not apply:
        return
    a = ask("ynq")
    if a == "y":
        backup(g, dst)
        relink(g, src, dst)
        return done("replaced with a symlink")
    done("skipped")


# --- seed, mirror ------------------------------------------------------------

def handle_copy(g, src, dst, apply):
    seed = src.read_bytes()
    mode = 0o755 if src.stat().st_mode & 0o111 else 0o644
    bpath = STATE / "base" / g.name / dst.relative_to(g.root)
    base = bpath.read_bytes() if bpath.is_file() else None

    if parent_in_repo(dst):
        return say("error", dst, "parent dir is a symlink into the repo (stow folding), fix it by hand")
    note = ""
    try:
        if is_link(dst) and inside_repo(link_target(dst)):
            # symlink into the repo (after stow / after moving the file between groups):
            # the content is in the repo anyway, nothing to lose
            say("stale", dst, "symlink into the repo -> replacing with a real copy")
            if apply:
                backup(g, dst)
                put(g, dst, seed, mode)
                save_base(bpath, seed)
            return
        if is_link(dst):
            note = f"symlink -> {link_target(dst)}"
        live = read_live(dst, g.sudo)
    except IsADirectoryError:
        return say("error", dst, "there is a directory in its place")

    if live is None:
        say("new", dst, "first copy")
        if apply:
            put(g, dst, seed, mode)
            save_base(bpath, seed)
        return
    if live == seed:
        say("ok", dst)
        if apply and base != seed:
            save_base(bpath, seed)
        return
    if base == seed and g.kind == "seed":
        return say("drift", dst, "edited locally, repo seed unchanged - that's fine")

    if base is not None and base != seed:
        say("updated", dst, note or "repo seed changed since last time")
        show_diff(base, seed, "previous seed", "new seed")
        opts = "ymelniq"
    else:
        say("differs", dst, note or "file already exists and differs from the repo")
        show_diff(live, seed, "mine", "repo")
        opts = "yeniq" if g.kind == "seed" else "yenq"
    if apply:
        resolve_copy(g, dst, seed, mode, bpath, base, live, opts)


def resolve_copy(g, dst, seed, mode, bpath, base, live, opts):
    while True:
        a = ask(opts)
        if a == "n":
            return done("skipped")
        if a == "i":
            save_base(bpath, seed)
            return done("file kept, repo version accepted")
        if a == "l":
            show_diff(live, seed, "mine", "repo")
            continue
        if a == "y":
            new, how = seed, "replaced with the repo file"
        elif a == "m":
            new, how = merge_3way(live, base, seed), "merged"
        else:
            new, how = edit_vimdiff(dst, live, seed), "assembled by hand"
        if new is None:
            continue
        if new == live:
            if a == "m":
                save_base(bpath, seed)
                return done("repo changes were already in the file - version accepted")
            print(c(2, "    (file unchanged)"))
            continue
        if a != "y":
            print("    result compared to your file:")
            show_diff(live, new, "mine", "result")
            if ask("ynq", {"y": "apply the result", "n": "back to the choice"}) != "y":
                continue
        backup(g, dst)
        put(g, dst, new, mode)
        save_base(bpath, seed)
        return done(how)


def merge_3way(live, base, seed):
    """git merge-file: apply to my file what changed in the repo. Returns bytes or None."""
    if shutil.which("git") is None:
        print("    git not found - merge unavailable")
        return None
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        (td / "live").write_bytes(live)
        (td / "base").write_bytes(base)
        (td / "repo").write_bytes(seed)
        r = subprocess.run(["git", "merge-file", "-p", "-L", "mine", "-L", "previous seed", "-L", "new seed",
                            td / "live", td / "base", td / "repo"], capture_output=True)
        if r.returncode > 127:
            print("    git merge-file failed:", r.stderr.decode(errors="replace").strip())
            return None
        merged = td / "merged"
        merged.write_bytes(r.stdout)
        if r.returncode == 0:
            return r.stdout
        print(f"    merge conflicts: {r.returncode} - opening the editor, remove the markers <<<<<<< ======= >>>>>>>")
        while True:
            editor = shlex.split(os.environ.get("VISUAL") or os.environ.get("EDITOR") or "vi")
            subprocess.run(editor + [str(merged)])
            data = merged.read_bytes()
            if not re.search(rb"^(<{7}|>{7}) ", data, re.M):
                return data
            if ask("ynq", {"y": "open the editor again", "n": "abandon the merge"}) == "y":
                continue
            return None


def edit_vimdiff(dst, live, seed):
    """Left: a copy of my file (the one we edit), right: the repo version. Returns the bytes after editing."""
    tool = os.environ.get("DIFFTOOL") or SETTINGS.get("difftool") or ("nvim -d" if shutil.which("nvim") else "vimdiff")
    with tempfile.TemporaryDirectory() as td:
        mine, repo = Path(td) / f"live_{dst.name}", Path(td) / f"repo_{dst.name}"
        mine.write_bytes(live)
        repo.write_bytes(seed)
        try:
            subprocess.run(shlex.split(tool) + [str(mine), str(repo)])
        except FileNotFoundError:
            print(f"    {tool} not found; set DIFFTOOL")
            return None
        return mine.read_bytes()


# --- orphaned symlinks -------------------------------------------------------

def find_orphans(everything):
    """Symlinks into the repo that no group has anymore (the file was removed or renamed)."""
    known, roots = set(), {HOME}
    for g, lst in everything:
        for _, dst in lst:
            known.add(dst)
            if under_home(g.root):
                parts = dst.relative_to(HOME).parts
                if len(parts) > 1:
                    roots.add(HOME / parts[0] / parts[1] if parts[0] == ".local" and len(parts) > 2
                              else HOME / parts[0])
    found = []
    for root in sorted(roots):
        for dirpath, dirnames, filenames in os.walk(root):
            depth = len(Path(dirpath).relative_to(root).parts)
            dirnames[:] = [] if root == HOME or depth >= 6 else \
                [d for d in dirnames if d not in PRUNE and not is_link(Path(dirpath) / d)]
            for name in filenames + [d for d in os.listdir(dirpath) if is_link(Path(dirpath) / d)]:
                p = Path(dirpath) / name
                if p not in known and is_link(p) and is_ours(p) and p not in found:
                    found.append(p)
    return sorted(found)


# --- commands ----------------------------------------------------------------

def cmd_run(selected, everything, apply):
    handlers = {"link": handle_link, "seed": handle_copy, "mirror": handle_copy}
    for g, lst in everything:
        if g not in selected:
            continue
        kind = "symlinks" if g.kind == "link" else "copies"
        title(f"{g.name}  ({g.source}/ {kind} -> {where(g.root)})")
        if not active(g):
            print(c(2, f"  not enabled on host {HOST!r} (hosts = {', '.join(g.hosts)}), skipped"))
            continue
        for src, dst in lst:
            handlers[g.kind](g, src, dst, apply)
    if any(under_home(g.root) for g in selected):
        orphans = find_orphans(everything)
        if orphans:
            title("orphaned symlinks")
        for p in orphans:
            say("stale", p, "no such file in the repo anymore -> removing the link" if apply
                else "no such file in the repo anymore")
            if apply:
                p.unlink()


def cmd_delete(selected, everything):
    title("removing links")
    for g, lst in everything:
        if g not in selected or not under_home(g.root):  # never delete outside of ~
            continue
        for src, dst in lst:
            if g.kind == "link" and is_link(dst) and (link_target(dst) == src):
                dst.unlink()
                print(f"  {c(31, 'rm')} {label(dst)}")
            elif g.kind == "mirror" and dst.is_file() and not is_link(dst) \
                    and dst.read_bytes() == src.read_bytes():
                dst.unlink()
                print(f"  {c(31, 'rm')} {label(dst)}  (copy, identical to the repo)")
    for p in find_orphans(everything):
        p.unlink()
        print(f"  {c(31, 'rm')} {label(p)}  (orphaned)")


def cmd_list(everything):
    print(f"\n  config: {CONFIG}\n  host:   {HOST}\n")
    for g, lst in everything:
        flags = []
        if g.sudo:
            flags.append("sudo")
        if not g.default:
            flags.append("only when named")
        if g.hosts:
            flags.append("hosts: " + ", ".join(g.hosts))
        if not active(g):
            flags.append(c(33, "OFF on this host"))
        print(f"  {c(1, f'{g.name:10}')} {g.kind:7} {g.source}/ -> {where(g.root):12} {len(lst):3} files"
              + (c(2, f"   ({'; '.join(flags)})") if flags else ""))
        if g.description:
            print(c(2, f"  {'':10} {g.description}"))
    if ALIASES:
        print("\n  aliases: " + "; ".join(f"{a} = {' '.join(v)}" for a, v in ALIASES.items()))
    if HOOKS:
        print("\n  hooks:")
        for h in HOOKS:
            print(f"    {', '.join(h['match'])}" + (f" [{h['group']}]" if h["group"] else "")
                  + f"  ->  {shlex.join(h['run'])}")


def cmd_init(arg):
    p = Path(arg).expanduser() if arg else Path.cwd() / "dots.toml"
    if p.exists():
        die(f"{p} already exists")
    p.write_text(TEMPLATE)
    print(f"written {p}\nnext: create the folders (e.g. main/.config/...), then run: dots.py check")


def run_hooks():
    todo = []
    for h in HOOKS:
        hit = [rel for g, rel in CHANGED
               if (not h["group"] or g.name == h["group"]) and matches(rel, h["match"])]
        if hit:
            todo.append((h, hit))
    if not todo:
        return
    title("hooks")
    for h, hit in todo:
        print(f"  {c(36, 'run')} {shlex.join(h['run'])}" + c(2, f"  ({len(hit)} changed)"))
        try:
            r = subprocess.run(h["run"])
            if r.returncode:
                print(c(31, f"    exit code {r.returncode}"))
        except FileNotFoundError:
            print(c(31, f"    command not found: {h['run'][0]}"))


def summary(apply):
    title("summary")
    keys = [k for k in STATS if k != "ok"]
    print("  " + (", ".join(f"{k}: {STATS[k]}" for k in keys) if keys else "everything in place")
          + f"   (ok: {STATS['ok']})")
    if _bak and _bak.exists():
        print(f"  backup of replaced files: {c(1, _bak)}")
    if not apply and sum(STATS[k] for k in PENDING):
        print(c(2, "  this was only a check; to apply: ./dots.py apply"))


def main():
    global VERBOSE
    args, cfg_arg, it = [], None, iter(sys.argv[1:])
    for a in it:
        if a in ("-c", "--config"):
            cfg_arg = next(it, None)
            if not cfg_arg:
                die(f"{a} needs a file")
        else:
            args.append(a)
    cmd, names = (args or ["help"])[0], args[1:]
    if cmd == "init":
        return cmd_init(cfg_arg)
    if cmd in ("help", "-h", "--help"):
        return print(__doc__)
    load(cfg_arg)
    if cmd in ALIASES:  # ./dots.py links  ==  ./dots.py apply <groups of the alias>
        cmd, names = "apply", ALIASES[cmd]
    elif cmd not in ("apply", "check", "delete", "list"):
        return print(__doc__)

    names = [x for n in names for x in ALIASES.get(n, [n])]
    known = {g.name for g in GROUPS}
    bad = [n for n in names if n not in known]
    if bad:
        die(f"no such group: {' '.join(bad)} (available: {' '.join(g.name for g in GROUPS)})")
    selected = [g for g in GROUPS if (g.name in names if names else g.default)]
    everything = [(g, list(pairs(g))) for g in GROUPS]

    seen = {}
    for g, lst in everything:
        for _, dst in lst:
            if dst in seen:
                die(f"{label(dst)} is laid out by two groups: {seen[dst]} and {g.name} "
                    f"(a file must live in one place; use exclude to resolve it)")
            seen[dst] = g.name

    if cmd == "list":
        return cmd_list(everything)
    VERBOSE = cmd == "check"
    try:
        if cmd == "delete":
            return cmd_delete(selected, everything)
        cmd_run(selected, everything, apply=cmd == "apply")
    except Quit:
        print("\n  quit")
    if cmd == "apply":
        run_hooks()
    summary(cmd == "apply")
    if cmd == "check" and sum(STATS[k] for k in PENDING):
        sys.exit(1)


if __name__ == "__main__":
    main()
