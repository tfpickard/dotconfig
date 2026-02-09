#!/usr/bin/env bash
# ==========================================================================
#  Dotfiles bootstrap — installs chezmoi + dependencies, then applies
#  Usage: curl -fsLS https://raw.githubusercontent.com/<you>/dotconfig/main/bootstrap.sh | bash
#         or: ./bootstrap.sh
# ==========================================================================
set -euo pipefail

DOTFILES_REPO="https://github.com/${GITHUB_USER:-$USER}/dotconfig.git"

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

# --------------------------------------------------------------------------
# OS detection
# --------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"

is_macos()  { [[ "$OS" == "Darwin" ]]; }
is_linux()  { [[ "$OS" == "Linux" ]]; }
has()        { command -v "$1" &>/dev/null; }

# --------------------------------------------------------------------------
# Package manager helpers
# --------------------------------------------------------------------------
install_homebrew() {
  if ! has brew; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if is_macos; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null || "$HOME/.linuxbrew/bin/brew" shellenv)"
    fi
  fi
}

install_with_brew() {
  local pkg="$1"
  if ! has "$pkg"; then
    info "Installing $pkg via brew..."
    brew install "$pkg"
  fi
}

install_with_apt() {
  local pkg="$1"
  local cmd="${2:-$1}"
  if ! has "$cmd"; then
    info "Installing $pkg via apt..."
    sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
  fi
}

# --------------------------------------------------------------------------
# Install chezmoi
# --------------------------------------------------------------------------
install_chezmoi() {
  if ! has chezmoi; then
    info "Installing chezmoi..."
    if has brew; then
      brew install chezmoi
    else
      sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi
  info "chezmoi $(chezmoi --version)"
}

# --------------------------------------------------------------------------
# Install core tools
# --------------------------------------------------------------------------
install_core_tools() {
  info "Installing core tools..."

  if is_macos || has brew; then
    install_homebrew
    local tools=(
      sheldon        # zsh plugin manager
      starship       # prompt
      fzf            # fuzzy finder
      fd             # better find
      bat            # better cat
      eza            # better ls
      ripgrep        # better grep
      zoxide         # better cd
      jq             # JSON processor
      tmux           # terminal multiplexer
      git-delta      # better git diffs
      pyenv          # python version manager
      nvm            # node version manager (via brew)
    )
    for tool in "${tools[@]}"; do
      brew install "$tool" 2>/dev/null || true
    done
  elif is_linux && has apt-get; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
      curl git tmux jq zsh fzf ripgrep bat

    # Install tools not in apt
    if ! has sheldon; then
      info "Installing sheldon..."
      curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
        | bash -s -- --repo rossmacarthur/sheldon --to "$HOME/.local/bin"
    fi
    if ! has starship; then
      info "Installing starship..."
      curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
    if ! has eza; then
      info "Installing eza..."
      cargo install eza 2>/dev/null || warn "eza requires cargo; skipping"
    fi
    if ! has zoxide; then
      curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    fi
    if ! has fd; then
      sudo apt-get install -y -qq fd-find 2>/dev/null && sudo ln -sf "$(which fdfind)" /usr/local/bin/fd || true
    fi
  fi
}

# --------------------------------------------------------------------------
# Set default shell to zsh
# --------------------------------------------------------------------------
set_default_shell() {
  if [[ "$(basename "$SHELL")" != "zsh" ]]; then
    local zsh_path
    zsh_path="$(which zsh)"
    if [[ -n "$zsh_path" ]]; then
      info "Setting default shell to zsh..."
      if grep -q "$zsh_path" /etc/shells; then
        chsh -s "$zsh_path" || warn "Could not change shell (try: sudo chsh -s $zsh_path $USER)"
      else
        warn "$zsh_path not in /etc/shells — adding it"
        echo "$zsh_path" | sudo tee -a /etc/shells
        chsh -s "$zsh_path" || warn "Could not change shell"
      fi
    fi
  fi
}

# --------------------------------------------------------------------------
# Create XDG directories
# --------------------------------------------------------------------------
setup_xdg() {
  mkdir -p \
    "${XDG_CONFIG_HOME:-$HOME/.config}/secrets" \
    "${XDG_DATA_HOME:-$HOME/.local/share}" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/zsh" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/zsh" \
    "$HOME/.local/bin"
}

# --------------------------------------------------------------------------
# Apply chezmoi
# --------------------------------------------------------------------------
apply_dotfiles() {
  info "Initializing chezmoi with dotfiles repo..."
  if [[ -d "$PWD/.chezmoiroot" ]] || [[ -f "$PWD/.chezmoiroot" ]]; then
    # Running from inside the repo
    chezmoi init --source="$PWD" --apply
  else
    chezmoi init --apply "$DOTFILES_REPO"
  fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
  info "Bootstrapping dotfiles..."
  info "OS: $OS | Arch: $ARCH"

  setup_xdg
  install_chezmoi
  install_core_tools
  set_default_shell
  apply_dotfiles

  # Initialize sheldon (download plugins)
  if has sheldon; then
    info "Initializing sheldon plugins..."
    sheldon lock 2>/dev/null || warn "sheldon lock failed — plugins will download on first shell start"
  fi

  info "Bootstrap complete! Open a new terminal or run: exec zsh"
}

main "$@"
