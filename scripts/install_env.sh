cd $HOME

# Install powerline fonts
sudo apt-get update
sudo apt-get install fonts-powerline

# Install ZSH
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

# Config dotfiles repo
curl -Lks  https://raw.githubusercontent.com/tom-rb/dotfiles/master/scripts/install_dotfiles.sh | /bin/bash

