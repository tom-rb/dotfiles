FROM amazonlinux:2 AS base

# Install shadow-utils to have useradd
RUN yum -y install sudo shadow-utils
COPY tests/shunit2 /usr/bin/shunit2

# Create non-root user and allow sudo without passwords for certain commands
RUN useradd -u 1234 amy \
  && echo 'amy ALL = NOPASSWD: /usr/bin/yum, /usr/bin/make, /usr/bin/chsh' > /etc/sudoers.d/amy \
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

# With tmux installed
FROM with-zsh AS with-tmux
RUN sudo yum -y install tmux