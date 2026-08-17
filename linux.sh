#!/usr/bin/env bash
# Pop!_OS (COSMIC desktop) machine setup — Linux port of macos.sh.
# Idempotent-ish: safe to re-run. Requires sudo.
#
# Differences from the macOS version, and why:
#   - Finder/Dock/defaults-write settings: dropped, no macOS equivalent.
#   - Path Finder: dropped, using the default file manager.
#   - Raycast: dropped. COSMIC already ships a Super-key launcher and a
#     native tiling window manager (Super+Y toggles tiling, Super+H/J/K/L
#     focus, Super+Shift+H/J/K/L move, Super+M maximize, Super+F11
#     fullscreen) — no separate app or config needed.
#   - Ice (menu bar manager): dropped, no equivalent concept on Linux.
#   - System Tweaks (Siri/Spotlight-indexing/Game Center): dropped, not
#     applicable. Kept the "locate" setup via plocate, which is a real
#     Linux equivalent.
#   - Colima: dropped. On native Linux, Docker Engine runs directly
#     without a VM layer, so we install docker.io instead.
#   - Ghostty cmd+... keybinds remapped to super+... (no Cmd key on Linux).
#   - yq/starship/fzf/k9s/lazygit/coursier aren't in Ubuntu's apt repos
#     (or apt's fzf is too old for `fzf --zsh`), so those are pulled from
#     upstream GitHub releases into ~/.local/bin instead of brew.
#   - Ubuntu's fd-find/bat packages ship as `fdfind`/`batcat` (name
#     clashes with existing packages), so aliases/symlinks bridge the gap.

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Terminal — Ghostty
# ─────────────────────────────────────────────────────────────

if ! command -v ghostty >/dev/null 2>&1; then
  echo "Install Ghostty first (e.g. via its PPA or a Flatpak) — see https://ghostty.org" >&2
fi

mkdir -p ~/.local/share/fonts
if ! fc-list | grep -qi "JetBrainsMono Nerd Font Mono"; then
  tmpdir=$(mktemp -d)
  nf_version=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${nf_version}/JetBrainsMono.tar.xz" -o "$tmpdir/jbm-nf.tar.xz"
  mkdir -p "$tmpdir/jbm-nf" && tar xf "$tmpdir/jbm-nf.tar.xz" -C "$tmpdir/jbm-nf"
  find "$tmpdir/jbm-nf" -iname "*.ttf" -exec cp {} ~/.local/share/fonts/ \;
  fc-cache -f ~/.local/share/fonts >/dev/null
  rm -rf "$tmpdir"
fi

mkdir -p ~/.config/ghostty
cat > ~/.config/ghostty/config <<'EOF'
# Font
font-family = JetBrainsMono Nerd Font Mono
font-size = 14
font-feature = -calt
font-feature = -liga

# Theme
theme = Catppuccin Mocha

# Window
window-padding-x = 12
window-padding-y = 12
background-opacity = 0.95
background-blur = true

# Behaviour
scrollbar = never
copy-on-select = false
confirm-close-surface = false
mouse-hide-while-typing = true

# Shell integration
shell-integration = zsh
shell-integration-features = cursor,sudo,title

# Quick Terminal (Super+` from anywhere)
quick-terminal-position = top
quick-terminal-screen = main
quick-terminal-animation-duration = 0.15
keybind = global:super+grave_accent=toggle_quick_terminal

# Splits
keybind = super+d=new_split:right
keybind = super+shift+d=new_split:down
keybind = super+shift+h=goto_split:left
keybind = super+shift+l=goto_split:right
keybind = super+shift+k=goto_split:top
keybind = super+shift+j=goto_split:bottom

# SSH terminfo fix
term = xterm-256color
EOF

# ─────────────────────────────────────────────────────────────
# APT packages
# ─────────────────────────────────────────────────────────────

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  zsh vim-gtk3 xclip tmux btop ripgrep eza bat zoxide httpie \
  git-delta plocate python3-pip docker.io fd-find \
  build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev \
  libxmlsec1-dev libffi-dev liblzma-dev jq wget

mkdir -p ~/.local/bin

# Ubuntu's fd-find/bat packages install as fdfind/batcat (name clashes
# with unrelated existing packages) — bridge to the expected names.
ln -sf /usr/bin/batcat ~/.local/bin/bat

# ─────────────────────────────────────────────────────────────
# Binaries not in apt (or apt's version too old) — latest GitHub release
# ─────────────────────────────────────────────────────────────

fetch_gh_release_binary() {
  # $1=repo $2=asset-filename-template (with {version} placeholder, no v-prefix if $3=strip)
  local repo="$1" version
  version=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
  echo "$version"
}

if [ ! -x ~/.local/bin/starship ]; then
  curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir ~/.local/bin -y
fi

if [ ! -x ~/.local/bin/fzf ]; then
  v=$(fetch_gh_release_binary junegunn/fzf)
  tmpdir=$(mktemp -d)
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/${v}/fzf-${v#v}-linux_amd64.tar.gz" -o "$tmpdir/fzf.tar.gz"
  tar xzf "$tmpdir/fzf.tar.gz" -C "$tmpdir" fzf
  mv "$tmpdir/fzf" ~/.local/bin/fzf && chmod +x ~/.local/bin/fzf
  rm -rf "$tmpdir"
fi

if [ ! -x ~/.local/bin/k9s ]; then
  v=$(fetch_gh_release_binary derailed/k9s)
  tmpdir=$(mktemp -d)
  curl -fsSL "https://github.com/derailed/k9s/releases/download/${v}/k9s_Linux_amd64.tar.gz" -o "$tmpdir/k9s.tar.gz"
  tar xzf "$tmpdir/k9s.tar.gz" -C "$tmpdir" k9s
  mv "$tmpdir/k9s" ~/.local/bin/k9s && chmod +x ~/.local/bin/k9s
  rm -rf "$tmpdir"
fi

if [ ! -x ~/.local/bin/lazygit ]; then
  v=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -oP '"tag_name":\s*"v\K[^"]+')
  tmpdir=$(mktemp -d)
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${v}/lazygit_${v}_linux_x86_64.tar.gz" -o "$tmpdir/lazygit.tar.gz"
  tar xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit
  mv "$tmpdir/lazygit" ~/.local/bin/lazygit && chmod +x ~/.local/bin/lazygit
  rm -rf "$tmpdir"
fi

if [ ! -x ~/.local/bin/yq ]; then
  v=$(fetch_gh_release_binary mikefarah/yq)
  curl -fsSL "https://github.com/mikefarah/yq/releases/download/${v}/yq_linux_amd64" -o ~/.local/bin/yq
  chmod +x ~/.local/bin/yq
fi

if [ ! -x ~/.local/bin/cs ]; then
  curl -fL "https://github.com/coursier/coursier/releases/latest/download/cs-x86_64-pc-linux.gz" | gzip -d > ~/.local/bin/cs
  chmod +x ~/.local/bin/cs
fi

# ─────────────────────────────────────────────────────────────
# Shell — zsh + Oh My Zsh + Starship
# ─────────────────────────────────────────────────────────────

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
  git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

cat > ~/.zshrc <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  z
  sudo
  copypath
  copyfile
)

source $ZSH/oh-my-zsh.sh

# PATH
export PATH="$HOME/.local/bin:$HOME/.local/share/coursier/bin:$PATH"

# Editor
export EDITOR=vim
export VISUAL=vim

# Aliases
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --style=plain --paging=never'
alias fd='fdfind'
alias fdd='fd'
alias grep='rg'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias df='df -h'
alias du='du -sh'
alias reload='source ~/.zshrc'

# fzf vim-style
export FZF_DEFAULT_OPTS='--layout=reverse --border --bind=ctrl-j:down,ctrl-k:up'

# Starship
eval "$(starship init zsh)"

# Zoxide (replaces cd with smart jumping)
eval "$(zoxide init zsh --cmd cd)"

# fzf
eval "$(fzf --zsh)"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

# SDKMAN — must be last
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
EOF

mkdir -p ~/.config
cat > ~/.config/starship.toml <<'EOF'
format = "$username@$hostname $directory$git_branch$git_status$character"

[username]
show_always = true
style_user = "bold green"
style_root = "bold red"
format = "[$user]($style)"

[hostname]
ssh_only = false
style = "bold green"
format = "[@$hostname]($style) "

[directory]
style = "bold blue"
truncation_length = 3
truncate_to_repo = false
format = "[$path]($style) "

[git_branch]
symbol = ""
style = "bold purple"
format = "[$symbol$branch]($style) "

[git_status]
style = "bold red"
format = '([\[$all_status$ahead_behind\]](bold red) )'

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[nodejs]
symbol = "node "
style = "bold green"

[python]
symbol = "py "
style = "bold yellow"

[rust]
symbol = "rs "
style = "bold red"

[golang]
symbol = "go "
style = "bold cyan"
EOF

sudo chsh -s "$(command -v zsh)" "$USER"

# ─────────────────────────────────────────────────────────────
# Launcher / window snapping
# ─────────────────────────────────────────────────────────────
# No app to install: COSMIC ships a Super-key launcher (Raycast/Spotlight
# replacement) and a native tiling window manager out of the box.
#   Super              Launcher
#   Super+Y            Toggle tiling for this workspace
#   Super+H/J/K/L       Focus left/down/up/right
#   Super+Shift+H/J/K/L Move window left/down/up/right
#   Super+M            Maximize
#   Super+F11          Fullscreen
#   Super+G            Toggle window floating (escape the tile layout)
#   Super+O            Toggle tiling split orientation

# ─────────────────────────────────────────────────────────────
# locate
# ─────────────────────────────────────────────────────────────

sudo updatedb

# ─────────────────────────────────────────────────────────────
# Vim
# ─────────────────────────────────────────────────────────────

curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

mkdir -p ~/.vim/undodir

cat > ~/.vimrc <<'EOF'
call plug#begin('~/.vim/plugged')
Plug 'prabirshrestha/vim-lsp'
Plug 'mattn/vim-lsp-settings'
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-lsp.vim'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'preservim/nerdtree'
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'
Plug 'derekwyatt/vim-scala'
Plug 'itchyny/lightline.vim'
Plug 'catppuccin/vim', { 'as': 'catppuccin' }
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'jiangmiao/auto-pairs'
call plug#end()

set nocompatible
set number
set relativenumber
set cursorline
set scrolloff=8
set signcolumn=yes
set tabstop=2
set shiftwidth=2
set expandtab
set smartindent
set hlsearch
set incsearch
set ignorecase
set smartcase
set splitright
set splitbelow
set noswapfile
set nobackup
set undofile
set undodir=~/.vim/undodir
set clipboard=unnamedplus
set mouse=
set termguicolors
colorscheme catppuccin_mocha
set laststatus=2

let mapleader = " "

nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa!<CR>
nnoremap <leader>h :nohl<CR>
nnoremap <leader>e :NERDTreeToggle<CR>
nnoremap <leader>f :Files<CR>
nnoremap <leader>g :Rg<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
nnoremap <leader>d :LspDefinition<CR>
nnoremap <leader>r :LspReferences<CR>
nnoremap <leader>n :LspRename<CR>
nnoremap <leader>k :LspHover<CR>
nnoremap <leader>a :LspCodeAction<CR>
nnoremap <leader>x :LspDocumentDiagnostics<CR>
nnoremap [d :LspPreviousDiagnostic<CR>
nnoremap ]d :LspNextDiagnostic<CR>
nnoremap <leader>gs :Git<CR>
nnoremap <leader>gb :Git blame<CR>

if executable('metals')
  au User lsp_setup call lsp#register_server({
    \ 'name': 'metals',
    \ 'cmd': {server_info->['metals']},
    \ 'allowlist': ['scala'],
    \ })
endif

if executable('pyright-langserver')
  au User lsp_setup call lsp#register_server({
    \ 'name': 'pyright',
    \ 'cmd': {server_info->['pyright-langserver', '--stdio']},
    \ 'allowlist': ['python'],
    \ })
endif

inoremap <expr> <Tab>   pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <CR>    pumvisible() ? "\<C-y>" : "\<CR>"

autocmd FileType scala setlocal tabstop=2 shiftwidth=2
autocmd FileType python setlocal tabstop=4 shiftwidth=4
EOF

TERM=xterm-256color vim -es -u ~/.vimrc -c "PlugInstall --sync" -c "qa"

# ─────────────────────────────────────────────────────────────
# Git
# ─────────────────────────────────────────────────────────────

cat > ~/.gitconfig <<'EOF'
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    line-numbers = true
    side-by-side = true
    theme = Catppuccin-mocha

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default
EOF

# ─────────────────────────────────────────────────────────────
# Dev Stack — version managers
# ─────────────────────────────────────────────────────────────

if [ ! -d "$HOME/.pyenv" ]; then
  curl -fsSL https://pyenv.run | bash
fi
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
pyenv install -s 3.12.3
pyenv global 3.12.3

if [ ! -d "$HOME/.sdkman" ]; then
  curl -s "https://get.sdkman.io" | bash
fi
# shellcheck disable=SC1091
source "$HOME/.sdkman/bin/sdkman-init.sh"
yes | sdk install java 21.0.2-graalce
yes | sdk install scala
yes | sdk install sbt

# ─────────────────────────────────────────────────────────────
# Language servers
# ─────────────────────────────────────────────────────────────

~/.local/bin/cs install metals       # Scala LSP
python3 -m pip install --user --break-system-packages pyright  # Python LSP

# ─────────────────────────────────────────────────────────────
# GUI apps — DBeaver, Bruno, Ollama
# ─────────────────────────────────────────────────────────────

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub com.usebruno.Bruno io.dbeaver.DBeaverCommunity

if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sudo sh
fi

# ─────────────────────────────────────────────────────────────
# Docker (native, no Colima needed on Linux)
# ─────────────────────────────────────────────────────────────

sudo usermod -aG docker "$USER"
sudo systemctl enable --now docker

echo "Done. Log out/in (or reboot) for the default-shell and docker-group changes to apply."
