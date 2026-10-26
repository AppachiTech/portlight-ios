# A throwaway SSH server for demos and screenshots: a made-up host with a
# tidy prompt, a small sample project and the usual tools, so recordings
# never show a real server's name, address or history.
#
# Key login only, as user `dev`. Run it with demo/server/demo-server.sh.
FROM ubuntu:24.04

ARG WITH_CLAUDE=0
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server sudo git htop tmux vim less curl ca-certificates tree python3 \
 && if [ "$WITH_CLAUDE" = "1" ]; then \
      apt-get install -y --no-install-recommends nodejs npm \
      && npm install -g @anthropic-ai/claude-code; \
    fi \
 && rm -rf /var/lib/apt/lists/*

# Quiet logins: no Ubuntu MOTD, no "last login" line, one short welcome.
RUN rm -f /etc/update-motd.d/* /etc/legal \
 && printf 'Welcome to atlas, a demo server.\n' > /etc/motd

# Key-only SSH for one user. Host keys are made here, so the fingerprint
# stays the same until the image is rebuilt.
RUN useradd --create-home --shell /bin/bash dev \
 && passwd --lock dev \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
 && mkdir -p /run/sshd /home/dev/.ssh \
 && chmod 700 /home/dev/.ssh && chown dev:dev /home/dev/.ssh \
 && ssh-keygen -A \
 && printf '%s\n' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'PermitRootLogin no' \
      'AllowUsers dev' \
      'PrintLastLog no' \
      'AllowTcpForwarding no' \
      'X11Forwarding no' \
      > /etc/ssh/sshd_config.d/demo.conf

COPY --chown=dev:dev bashrc /home/dev/.bashrc.demo
COPY --chown=dev:dev make-sample-project.sh /tmp/make-sample-project.sh
RUN cat /home/dev/.bashrc.demo >> /home/dev/.bashrc && rm /home/dev/.bashrc.demo \
 && su dev -c 'bash /tmp/make-sample-project.sh' && rm /tmp/make-sample-project.sh

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
