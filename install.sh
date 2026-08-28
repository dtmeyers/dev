#!/usr/bin/env bash
#
# install.sh — sets up the "dev" terminal IDE on a fresh Raspberry Pi
#
#   yazi (file manager) + mdcat (markdown preview) + Claude Code,
#   arranged as a split tmux session launched by the `dev` command.
#
# Safe to re-run: every step is skipped if already done, and any config
# file that already exists is backed up before being replaced.
#
# Usage:  bash install.sh
#

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yazi"
BIN_DIR="$HOME/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"
FLAVOR="catppuccin-mocha"

info()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$1"; }
ok()    { printf '\033[1;32m  ok\033[0m %s\n' "$1"; }

backup() {
  [ -f "$1" ] && cp "$1" "$1.$STAMP.bak" && warn "backed up $(basename "$1") -> $(basename "$1").$STAMP.bak"
  return 0
}

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this as root. It installs into your home directory." >&2
  exit 1
fi

# ---------------------------------------------------------------- 1. packages
info "Installing system packages"
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config libssl-dev \
  tmux git curl unzip file
ok "build toolchain, OpenSSL headers, tmux"

# libssl-dev is what mdcat's openssl-sys crate needs; pkg-config is what
# finds it. Without both, the cargo build fails at the build-script stage.

# ------------------------------------------------------------------- 2. swap
info "Checking swap"
SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')
if [ "$SWAP_MB" -lt 1024 ]; then
  warn "only ${SWAP_MB}MB swap; Rust linking can be OOM-killed on small Pis."
  read -rp "  Increase swap to 2GB? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    sudo dphys-swapfile swapoff
    sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
    sudo dphys-swapfile setup
    sudo dphys-swapfile swapon
    ok "swap increased to 2GB"
  fi
else
  ok "${SWAP_MB}MB swap available"
fi

# ------------------------------------------------------------------- 3. rust
info "Installing Rust"
if command -v rustup >/dev/null 2>&1; then
  ok "rustup already present ($(rustc -V))"
else
  if dpkg -l rustc 2>/dev/null | grep -q '^ii'; then
    warn "apt's rustc is installed ($(rustc -V 2>/dev/null || echo 'version unknown'))."
    warn "It is usually too old to build mdcat, and having both on PATH causes"
    warn "confusing failures depending on which one resolves first."
    read -rp "  Remove the apt rustc and cargo packages? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      sudo apt-get remove -y rustc cargo
      ok "apt rustc and cargo removed"
    else
      warn "keeping apt's rustc; rustup will be installed alongside it"
      warn "if the mdcat build fails, check 'which -a rustc' — ~/.cargo/bin must come first"
    fi
  fi
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  ok "rustup installed"
fi
export PATH="$HOME/.cargo/bin:$PATH"

# ------------------------------------------------------------------ 4. mdcat
info "Installing mdcat"
if command -v mdcat >/dev/null 2>&1; then
  ok "mdcat already installed"
else
  # --no-default-features drops remote-image support, which needs system TLS
  # and is useless in a preview pane that only ever sees local files.
  cargo install mdcat --no-default-features -j 1
  ok "mdcat installed"
fi

# Which colour flag this build uses has changed across mdcat 2.x releases.
if mdcat --help 2>&1 | grep -q -- '--ansi'; then
  MDCAT_FLAG="--ansi"
else
  MDCAT_FLAG="--terminal=ansi"
  warn "this mdcat has no --ansi; falling back to --terminal=ansi"
fi
ok "using mdcat $MDCAT_FLAG"

# ------------------------------------------------------------------- 5. yazi
info "Installing yazi"
if command -v yazi >/dev/null 2>&1; then
  ok "yazi already installed ($(yazi --version 2>/dev/null | head -1))"
else
  ARCH="$(uname -m)"
  case "$ARCH" in
    aarch64) TARGET="aarch64-unknown-linux-gnu" ;;
    armv7l)  TARGET="" ;;   # no prebuilt; must compile
    x86_64)  TARGET="x86_64-unknown-linux-gnu" ;;
    *)       TARGET="" ;;
  esac

  INSTALLED=0
  if [ -n "$TARGET" ]; then
    info "  trying prebuilt binary for $TARGET"
    URL=$(curl -fsSL https://api.github.com/repos/sxyazi/yazi/releases/latest \
          | grep -o "https://[^\"]*yazi-${TARGET}\.zip" | head -1) || true
    if [ -n "${URL:-}" ]; then
      TMP=$(mktemp -d)
      if curl -fsSL "$URL" -o "$TMP/yazi.zip" && unzip -q "$TMP/yazi.zip" -d "$TMP"; then
        mkdir -p "$BIN_DIR"
        find "$TMP" -type f \( -name yazi -o -name ya \) -exec install -m755 {} "$BIN_DIR"/ \;
        rm -rf "$TMP"
        INSTALLED=1
        ok "installed prebuilt yazi + ya"
      fi
    fi
  fi

  if [ "$INSTALLED" -eq 0 ]; then
    warn "no prebuilt binary; compiling from source (this takes a while on a Pi)"
    cargo install --locked yazi-fm yazi-cli -j 1
    ok "yazi compiled and installed"
  fi
fi

export PATH="$BIN_DIR:$PATH"

# --------------------------------------------------------- 6. version syntax
# Yazi renamed several config keys in 25.5.31. Detect which set to write.
YAZI_VER="$(yazi --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")"
if printf '%s\n25.5.31\n' "$YAZI_VER" | sort -V | head -1 | grep -q '^25\.5\.31$'; then
  MGR_KEY="mgr"; MATCH_KEY="url"; PKG_CMD="pkg add"
else
  MGR_KEY="manager"; MATCH_KEY="name"; PKG_CMD="pack -a"
  warn "yazi $YAZI_VER is pre-25.5.31; using legacy config keys"
fi
ok "yazi $YAZI_VER — using [$MGR_KEY] and '$MATCH_KEY ='"

# ---------------------------------------------------------------- 7. plugins
info "Installing yazi plugins and flavor"
mkdir -p "$CONFIG_DIR"
ya $PKG_CMD yazi-rs/plugins:piper       2>/dev/null || warn "piper may already be installed"
ya $PKG_CMD "yazi-rs/flavors:$FLAVOR"   2>/dev/null || warn "$FLAVOR may already be installed"

# ----------------------------------------------------------------- 8. config
info "Writing yazi config"

backup "$CONFIG_DIR/yazi.toml"
cat > "$CONFIG_DIR/yazi.toml" <<EOF
# parent / current / preview  — weights, not percentages
[$MGR_KEY]
ratio = [1, 2, 5]

[plugin]
prepend_previewers = [
  { $MATCH_KEY = "*.md", run = 'piper -- mdcat --columns=\$w $MDCAT_FLAG "\$1"' },
]
EOF
ok "yazi.toml"

backup "$CONFIG_DIR/theme.toml"
cat > "$CONFIG_DIR/theme.toml" <<EOF
[flavor]
dark = "$FLAVOR"

# ANSI 4 is unreadable on a black background on most Pi palettes;
# lightblue is ANSI 12. Delete this block if the flavor handles it.
[filetype]
rules = [
  { $MATCH_KEY = "*/", fg = "lightblue" },
]
EOF
ok "theme.toml"

backup "$CONFIG_DIR/keymap.toml"
cat > "$CONFIG_DIR/keymap.toml" <<EOF
# Capital C hands the hovered file straight to Claude Code and returns
# to yazi on exit. \$0 = hovered file, \$@ = selected files.
[[$MGR_KEY.prepend_keymap]]
on = "C"
run = 'shell --block "claude \\"\$0\\""'
desc = "Open Claude Code on hovered file"
EOF
ok "keymap.toml"

# ------------------------------------------------------------------- 9. tmux
info "Configuring tmux"
backup "$HOME/.tmux.conf"
touch "$HOME/.tmux.conf"
if ! grep -q 'allow-passthrough' "$HOME/.tmux.conf"; then
  cat >> "$HOME/.tmux.conf" <<'EOF'

# --- Claude Code compatibility -----------------------------------------
# allow-passthrough lets notifications and the progress bar reach the outer
# terminal; the extended-keys lines let tmux tell Shift+Enter from Enter.
set -g allow-passthrough on
set -s extended-keys on
set -as terminal-features 'xterm*:extkeys'

# --- dev session bindings ----------------------------------------------
bind -N "dev cheatsheet"      I display-popup -E -w 74 -h 34 "dev --help | less"
bind -N "kill the dev session" X confirm-before -p "kill session? (y/n)" kill-session
EOF
  ok "tmux.conf updated"
else
  ok "tmux.conf already configured"
fi

# ----------------------------------------------------------- 10. dev launcher
info "Installing the dev launcher"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/dev" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

SESSION=dev

show_help() {
cat <<'HELP'
dev — yazi + Claude Code in one split tmux session

USAGE
  dev [directory]      start, or reattach if already running
  dev --help           this screen

  Both panes open in the directory you pass, so Claude Code's @ file
  completion is relative to it. Defaults to the current directory.
    dev ~/my-project

PANES                  prefix is Ctrl-b: press and release, then the key
  Ctrl-b  < >          switch panes (arrow keys)
  Ctrl-b  o            cycle to the next pane
  Ctrl-b  z            zoom the current pane fullscreen, again to undo
  Ctrl-b  Ctrl-arrow   resize by 1 column (hold Ctrl, repeatable)
  Ctrl-b  Alt-arrow    resize by 5 columns
  Ctrl-b  { }          swap the two panes

SESSION
  Ctrl-b  d            detach; both keep running in the background
  dev                  reattach afterwards
  Ctrl-b  X            kill the session, with a confirm prompt
  tmux kill-session -t dev     tear it down from outside

SCROLLING
  Ctrl-b  [            scroll mode: arrows and PgUp/PgDn, q to exit
  Ctrl-b  ?            tmux's own full keybinding list

YAZI
  c c                  copy full path of the hovered file
  c f                  copy filename only
  C                    open Claude Code on the hovered file
  h  l                 up a directory / into a directory
  q                    quit

  Ctrl-b I  reopens this screen from inside the session.
HELP
}

case "${1:-}" in
  -h|--help|help) show_help; exit 0 ;;
esac

cd "${1:-.}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -c "$PWD"
  tmux send-keys -t "$SESSION" 'yazi' C-m
  tmux split-window -h -p 60 -t "$SESSION" -c "$PWD"
  tmux send-keys -t "$SESSION" 'claude' C-m
fi
tmux attach -t "$SESSION"
LAUNCHER
chmod +x "$BIN_DIR/dev"
ok "dev installed to $BIN_DIR/dev"

# ------------------------------------------------------------ 11. claude code
info "Installing Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "claude already installed"
else
  # Native installer: no Node, no sudo, auto-detects arm64, lands in ~/.local/bin
  curl -fsSL https://claude.ai/install.sh | bash
  ok "Claude Code installed"
fi

# ------------------------------------------------------------------ 12. PATH
info "Checking PATH"
NEEDS_PATH=0
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) NEEDS_PATH=1 ;; esac
if [ "$NEEDS_PATH" -eq 1 ] && ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  warn "added ~/.local/bin to PATH in .bashrc"
fi
if ! grep -q '.cargo/env' "$HOME/.bashrc" 2>/dev/null; then
  echo '. "$HOME/.cargo/env"' >> "$HOME/.bashrc"
  warn "added cargo to PATH in .bashrc"
fi
ok "PATH configured"

cat <<EOF

$(printf '\033[1;32m')Done.$(printf '\033[0m')

Next steps:
  1.  exec bash                 reload PATH in this shell
  2.  claude                    authenticate once, in a browser
  3.  dev ~/somedir             launch it

Not handled by this script:
  Your ANSI colour palette lives in the terminal you SSH *from*, not on
  the Pi. If directories still look too dark, check colour 4 with:

    for i in {0..15}; do printf "\\e[38;5;\${i}m%3d " \$i; done; echo

  and fix it in that terminal's settings, or enable its
  "show bold text in bright colors" option.
EOF
