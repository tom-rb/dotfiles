# ZSH
- Config prompt theme and git-info https://github.com/zimfw/zimfw/tree/master/modules/git-info
- Check all color implementations (solarized zsh in ubuntu and wsl) http://mayccoll.github.io/Gogh/
- Save session https://github.com/yonchu/dotfiles/blob/master/.zsh/.zlogin
- Checkout PRs searching in cmd line http://lebenplusplus.de/2019/04/04/check-out-your-github-pull-request-with-an-interactive-shell-menu/
- Find files by name or content with fzf and grep https://sidneyliebrand.io/blog/how-fzf-and-ripgrep-improved-my-workflow
- Aliases/bindings para iniciar sessões tmux (main, cliente, etc) mais facilmente.

# Tmux
- Check tmux plugins in wsl and Ubuntu
  - Implement "tmux-copycat" with smart use of tmux capture-pane and tac
- Substituir as window flags por symbols/colors nas tabs
- Inspirations: https://github.com/rothgar/awesome-tmux https://github.com/samoshkin/tmux-config (internal ssh tmux)
- Pelo deploy, fazer o tmux independente do zsh, ie. poder lancar o tmux sem precisar ter o zsh.env preparado.

# VIM
- Use C-a to navigate in vim panes and interoperate with tmux
- Some solution for #include with less typing
- Salve automatically (when losing focus? there's vim-auto-save plugin)
- Move .vim to ~/.config and ~/.local/share

# Deploy
- Install tmux by downloading tarball and making (needs libevent-dev and libncurses-dev)
- Subtree (or module?) the colorsdir repo https://github.com/seebi/dircolors-solarized
