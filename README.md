# dev

A terminal IDE for the Raspberry Pi, installed by one script.

`dev` is a tmux session with a file manager on the left and Claude Code on the
right. Yazi handles browsing and previews markdown inline via mdcat; Claude Code
gets the larger pane. One command starts both, and detaching leaves them running
so a dropped SSH connection doesn't cost you anything.

Built for working on a headless Pi over SSH, where VS Code is heavier than the
machine deserves.

```
┌─────────────┬──────────────────────────┐
│  parent     │                          │
│  ├─ files   │      Claude Code         │
│  └─ preview │                          │
└─────────────┴──────────────────────────┘
     yazi                40 / 60
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dtmeyers/dev/main/install.sh -o install.sh
less install.sh
bash install.sh
```

Then:

```bash
exec bash          # reload PATH
claude             # authenticate once, in a browser
dev ~/projects     # go
```

The script is idempotent. Re-run it any time; completed steps are skipped and
any config file it would overwrite is backed up to `<file>.<timestamp>.bak`
first.

## What it installs

| | |
|---|---|
| [tmux](https://github.com/tmux/tmux) | splits the terminal, keeps sessions alive across disconnects |
| [yazi](https://github.com/sxyazi/yazi) | file manager, from a prebuilt binary where one exists |
| [mdcat](https://github.com/swsnr/mdcat) | renders markdown in the preview pane |
| [piper](https://github.com/yazi-rs/plugins) | yazi plugin that pipes shell output into a preview |
| [Claude Code](https://code.claude.com/docs) | Anthropic's terminal coding agent |
| Rust | only as a build dependency for mdcat |

Plus config: `yazi.toml`, `theme.toml`, `keymap.toml`, additions to
`~/.tmux.conf`, and the `dev` launcher in `~/.local/bin`.

## Keys

`dev --help` prints the full cheatsheet. `Ctrl-b I` opens it in a popup from
inside the session.

| | |
|---|---|
| `Ctrl-b` arrow | switch panes |
| `Ctrl-b` `Ctrl`-arrow | resize by 1 column, repeatable |
| `Ctrl-b z` | zoom a pane fullscreen |
| `Ctrl-b d` | detach, leaving both running |
| `Ctrl-b X` | kill the session, with a confirm |
| `C` (in yazi) | open Claude Code on the hovered file |
| `c c` (in yazi) | copy the hovered file's full path |

You often won't need that last one — Claude Code's `@` references tab-complete
against the working directory, and both panes start in the same one.

## Requirements

Tested on Raspberry Pi OS (Bookworm, 64-bit) on a Pi 4 and Pi 5. Should work on
Debian and Ubuntu derivatives with one caveat noted below.

Claude Code needs a paid Anthropic plan — Pro, Max, Team, Enterprise, or a
Console account with API billing. It also wants 4GB+ RAM and arm64 or x64.

## Things to know before running it

**It pipes two remote installers into bash.** [rustup](https://sh.rustup.rs) and
[Claude Code](https://claude.ai/install.sh), both official upstream sources.
Standard practice for both projects, but you should know it's happening. Read
the script.

**It may offer to remove apt's Rust. If rustup isn't present but rustc was installed from apt, the script asks whether to remove rustc and cargo first. The distro version is usually too old to build mdcat, and having both on PATH causes failures that depend on which resolves first. Declining is fine — rustup installs alongside, but ~/.cargo/bin needs to come first in your PATH.

**Swap handling is Pi-specific.** The swap step uses `dphys-swapfile`, which
doesn't exist outside Raspberry Pi OS. On other distros that step will fail. The
prompt only appears if you have under 1GB of swap; Rust linking gets OOM-killed
on small Pis without it.

**Nothing runs as root.** Everything lands in `$HOME`. The script refuses to
start if you invoke it with sudo.

## Version drift

Yazi renamed several config keys in 25.5.31 (`manager` → `mgr`, `name` → `url`)
and mdcat has moved its colour flags around across 2.x. The script detects both
and writes whichever syntax your build wants. If yazi still complains at startup,
the error names the offending key — check it against the
[yazi docs](https://yazi-rs.github.io/docs/configuration/overview) for your
version.

## Colours

The theme is [catppuccin-mocha](https://github.com/yazi-rs/flavors) with one
override: directories use ANSI 12 rather than 4, since the default dark blue is
unreadable on a black background.

If it still looks wrong, the problem is upstream of the Pi. Your palette belongs
to the terminal you SSH *from*. Check it:

```bash
for i in {0..15}; do printf "\e[38;5;${i}m%3d " $i; done; echo
```

If 4 is illegible, fix it in that terminal's settings, or turn on its "show bold
text in bright colors" option. That fixes `ls`, `vim`, and git output too, not
just yazi.

## Uninstall

```bash
rm -rf ~/.config/yazi ~/.local/bin/dev
rm -f ~/.local/bin/yazi ~/.local/bin/ya
cargo uninstall mdcat
# remove the "Claude Code compatibility" and "dev session bindings"
# blocks from ~/.tmux.conf
```

Claude Code and Rust have their own uninstall paths: `claude uninstall` and
`rustup self uninstall`.

## License

MIT
