# Dockerfile for OpenClaw testing with systemd support
FROM ubuntu:24.04

# Install systemd, SSH, sudo, and essential packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && \
    apt-get install -y -qq systemd systemd-sysv curl ca-certificates openssh-server sudo && \
    echo 'root:root' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up environment
ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

STOPSIGNAL SIGRTMIN+9

# Run systemd directly
CMD ["/lib/systemd/systemd"]
