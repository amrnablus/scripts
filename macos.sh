#!/usr/bin/env bash
# macOS machine setup.
# Idempotent-ish: safe to re-run. Requires Homebrew (https://brew.sh) already installed.

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Finder
# ─────────────────────────────────────────────────────────────

defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
killall Finder || true

# ─────────────────────────────────────────────────────────────
# Path Finder (manual step)
# ─────────────────────────────────────────────────────────────
# Install from https://cocoatech.com, then set as default file browser via:
#   Path Finder → Preferences → General → "Set as Default File Browser"

# ─────────────────────────────────────────────────────────────
# Terminal — Ghostty
# ─────────────────────────────────────────────────────────────

brew install --cask ghostty
brew install --cask font-jetbrains-mono-nerd-font

mkdir -p ~/.config/ghostty
cat > ~/.config/ghostty/config <<'EOF'
# Font
font-family = JetBrainsMono Nerd Font Mono
font-size = 14
font-feature = -calt
font-feature = -liga

# Theme
theme = catppuccin Mocha

# Window
window-padding-x = 12
window-padding-y = 12
background-opacity = 0.95
background-blur = true
macos-titlebar-style = tabs

# Behaviour
scrollbar = never
copy-on-select = false
confirm-close-surface = false
mouse-hide-while-typing = true

# Shell integration
shell-integration = zsh
shell-integration-features = cursor,sudo,title

# Quick Terminal (Cmd+` from anywhere)
quick-terminal-position = top
quick-terminal-screen = main
quick-terminal-animation-duration = 0.15
keybind = global:cmd+grave_accent=toggle_quick_terminal

# Splits
keybind = cmd+d=new_split:right
keybind = cmd+shift+d=new_split:down
keybind = cmd+shift+h=goto_split:left
keybind = cmd+shift+l=goto_split:right
keybind = cmd+shift+k=goto_split:top
keybind = cmd+shift+j=goto_split:bottom

# SSH terminfo fix
term = xterm-256color
EOF

# ─────────────────────────────────────────────────────────────
# Shell — Oh My Zsh + Starship
# ─────────────────────────────────────────────────────────────

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

brew install starship fzf zoxide eza bat fd ripgrep

cat > ~/.zshrc <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  z
  macos
  sudo
  copypath
  copyfile
)

source $ZSH/oh-my-zsh.sh

# Editor
export EDITOR=vim
export VISUAL=vim

# Aliases
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --level=2 --icons'
alias cat='bat --style=plain --paging=never'
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

# ─────────────────────────────────────────────────────────────
# Dock
# ─────────────────────────────────────────────────────────────

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.15
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock showhidden -bool true
defaults write com.apple.dock tilesize -int 36
killall Dock || true

# ─────────────────────────────────────────────────────────────
# Raycast (manual steps)
# ─────────────────────────────────────────────────────────────

brew install --cask raycast
# Then:
#   - System Settings → Keyboard → Shortcuts → Spotlight → uncheck Cmd+Space
#   - Set Raycast hotkey to Cmd+Space
#   - Enable Window Management extension
#   - Enable Clipboard History → Cmd+Shift+V
#
# Window snapping keybindings:
#   Fullscreen    Ctrl+Alt+F
#   Left Half     Ctrl+Alt+H
#   Right Half    Ctrl+Alt+L
#   Top Half      Ctrl+Alt+K
#   Bottom Half   Ctrl+Alt+J
#   Center        Ctrl+Alt+C
#   Maximize      Ctrl+Alt+M

# ─────────────────────────────────────────────────────────────
# Menu Bar — Ice
# ─────────────────────────────────────────────────────────────

brew install --cask jordanbaird-ice
# Then enable "Launch at login" in Ice Settings.

# ─────────────────────────────────────────────────────────────
# System Tweaks
# ─────────────────────────────────────────────────────────────

# Disable Siri
defaults write com.apple.assistant.support 'Assistant Enabled' -bool false

# Disable Spotlight indexing (using Raycast instead)
sudo mdutil -a -i off

# Disable Game Center
defaults write com.apple.gamed Disabled -bool true

# Enable locate command
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.locate.plist
sudo /usr/libexec/locate.updatedb

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
set clipboard=unnamed
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

if executable('pyright')
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

vim +PlugInstall +qall

# ─────────────────────────────────────────────────────────────
# Git
# ─────────────────────────────────────────────────────────────

brew install git-delta lazygit

cat > ~/.gitconfig <<'EOF'
[core]
    pager = delta

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

brew install pyenv
pyenv install -s 3.12.3
pyenv global 3.12.3

curl -s "https://get.sdkman.io" | bash
# shellcheck disable=SC1091
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 21.0.2-graalce
sdk install scala
sdk install sbt

# ─────────────────────────────────────────────────────────────
# Language servers
# ─────────────────────────────────────────────────────────────

brew install coursier
cs install metals       # Scala LSP
pip install pyright     # Python LSP

# ─────────────────────────────────────────────────────────────
# Tools
# ─────────────────────────────────────────────────────────────

brew install jq yq wget httpie k9s btop tmux
brew install --cask dbeaver-community bruno

# ─────────────────────────────────────────────────────────────
# Docker / Colima
# ─────────────────────────────────────────────────────────────

brew install colima docker docker-compose
brew services start colima   # start on login

echo "Done. Log out/in (or reboot) for the shell/Dock/Finder changes to fully apply."
