FROM ubuntu:bionic

RUN apt update && apt install shunit2 sudo

# Create non-root user and allow sudo without passwords for certain commands
RUN useradd -u 1234 amy \
  && echo 'amy ALL = NOPASSWD: /usr/bin/apt-get, /usr/bin/chsh' > /etc/sudoers.d/amy \
  && chmod 0440 /etc/sudoers.d/amy

USER amy