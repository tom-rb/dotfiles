FROM amazonlinux:2 AS base

# Install shadow-utils to have useradd
RUN yum -y install sudo shadow-utils
COPY tests/shunit2 /usr/bin/shunit2

# Create non-root user and allow sudo without passwords for certain commands
RUN useradd -u 1234 amy \
  && echo 'amy ALL = NOPASSWD: /usr/bin/yum, /usr/bin/make, /usr/bin/chsh, /usr/bin/sed' > /etc/sudoers.d/amy \
  && chmod 0440 /etc/sudoers.d/amy \
  && mkdir -p /home/amy \
  && chown amy /home/amy

WORKDIR /home/amy
USER amy

# Install basic packages
FROM base AS with-basics
RUN sudo yum -y install wget tar gzip

# With git installed
FROM with-basics AS with-git
RUN sudo yum -y install git

# With zsh installed
FROM with-git AS with-zsh
RUN sudo yum -y install zsh

# With tmux installed.
# amazonlinux:2's package tmux is 1.8, which is older than the dotfiles' minimum
# (3.5a) — install_tmux_program would refuse and the wizard would bail. Build a
# modern tmux from source so this stage exercises the "tmux already installed"
# path the tests intend. Keep this in sync with TMUX_DESIRED_VERSION in
# tmux/install_tmux.sh so the pre-installed tmux satisfies the minimum.
FROM with-zsh AS with-tmux
ARG TMUX_VERSION=3.5a
USER root
RUN yum -y install gcc make bison wget tar gzip libevent-devel ncurses-devel \
  && cd /tmp \
  && wget -q "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" \
  && tar xf "tmux-${TMUX_VERSION}.tar.gz" \
  && cd "tmux-${TMUX_VERSION}" \
  && ./configure >/dev/null \
  && make -j"$(nproc)" >/dev/null \
  && make install >/dev/null \
  && cd /tmp && rm -rf "tmux-${TMUX_VERSION}" "tmux-${TMUX_VERSION}.tar.gz"
USER amy

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
RUN sudo yum -y install curl
RUN mkdir -p "$HOME/.local/bin" \
  && wget -nv -O /tmp/asdf.tar.gz \
       "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-amd64.tar.gz" \
  && tar -xzf /tmp/asdf.tar.gz -C "$HOME/.local/bin" asdf \
  && rm /tmp/asdf.tar.gz