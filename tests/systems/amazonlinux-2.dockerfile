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