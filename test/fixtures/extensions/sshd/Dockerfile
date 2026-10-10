# A Linux host reached over real SSH, for ssh_docker_exthost_test.dart: sshd,
# a user `dev` (key only), and what the project's debuggers run (python3,
# node). The test puts its throwaway key in /home/dev/.ssh.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server python3 nodejs git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd \
 && useradd -m -s /bin/bash dev && mkdir -p /home/dev/.ssh && chown dev:dev /home/dev/.ssh && chmod 700 /home/dev/.ssh \
 && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
CMD ["/usr/sbin/sshd", "-D", "-e"]
