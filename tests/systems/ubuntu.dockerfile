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