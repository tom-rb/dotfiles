# Tmux commands
Prefix C-a

## Copying (yanks to system clipboard too)
### Normal mode
y               copies text from the command line to the clipboard
Y               copy the current working directory to the clipboard
### Copy mode
v               starts visual selection
y or Enter      yank and cancel
Y               yank, cancel, and paste in cmdline

## Search
Grep is used for searching. Searches are case insensitive.
/               regex search (strings work too)

### Predefined searches
These start "copycat mode" and jump to first match.
ctrl-f          simple file search
ctrl-g          jumping over git status files (best used after git status command)
alt-h           jumping over SHA-1/SHA-256 hashes (best used after git log command)
ctrl-u          url search (http, ftp and git urls)
ctrl-d          number search (mnemonic d, as digit)
alt-i           ip address search
These are enabled when you search with copycat:
n               jumps to the next match
N               jumps to the previous match

### Open highlighted things (TODO: a PR to tmux-open work with WSL)
o               open with the system default program. open for OS X or xdg-open for Linux.
Ctrl-o          open with the $EDITOR
Shift-s         search the highlighted selection directly inside a search engine (defaults to google).

## Plugin manager
I               install listed plugins
U               update listed plugins
