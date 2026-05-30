FROM ubuntu AS base

RUN apt update && apt install -y sudo
COPY tests/shunit2 /usr/bin/shunit2

# Create non-root user and allow sudo without passwords for certain commands
RUN useradd -u 1234 amy \
  && echo 'amy ALL = NOPASSWD: /usr/bin/apt-get, /usr/bin/make, /usr/bin/chsh, /usr/bin/sed' > /etc/sudoers.d/amy \
  && chmod 0440 /etc/sudoers.d/amy \
  && mkdir -p /home/amy \
  && chown amy /home/amy

WORKDIR /home/amy
USER amy

# Install basic packages
FROM base AS with-basics
RUN sudo apt-get install -y wget tar gzip

# With git installed
FROM with-basics AS with-git
RUN sudo apt-get install -y git

# With zsh installed
FROM with-git AS with-zsh
RUN sudo apt-get install -y zsh

# With tmux installed
FROM with-zsh AS with-tmux
RUN sudo apt-get install -y tmux

# With asdf installed, for exercising the pi installer's node bootstrap.
# Installs only the asdf binary (no node) to ~/.local/bin — a real deploy's
# location — and deliberately leaves it OFF PATH. Putting it on PATH is deploy's
# activate_asdf job, which the pi system test drives, so this stage reproduces
# the real cross-module situation. curl is used by the asdf nodejs plugin.
# node's prebuilt binaries also need libatomic, which the pi installer now
# installs via the package manager — so we deliberately omit it here to exercise
# that path. Keep ASDF_VERSION in sync with the version pinned in
# asdf/install_asdf.sh.
FROM with-tmux AS with-asdf
ARG ASDF_VERSION=0.16.7
RUN sudo apt-get install -y curl
RUN mkdir -p "$HOME/.local/bin" \
  && wget -nv -O /tmp/asdf.tar.gz \
       "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-amd64.tar.gz" \
  && tar -xzf /tmp/asdf.tar.gz -C "$HOME/.local/bin" asdf \
  && rm /tmp/asdf.tar.gz