git clone --bare https://github.com/tom-rb/dotfiles.git $HOME/.cfg

# Alias to git comands for dotfile repo
function dotg {
   /usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME $@
}

mkdir -p .config-backup
dotg checkout
if [ $? = 0 ]; then
  echo "Checked out config.";
  else
    echo "Backing up pre-existing dot files.";
    dotg checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | xargs -I{} mv {} .config-backup/{}
fi;
dotg checkout
dotg config status.showUntrackedFiles no
