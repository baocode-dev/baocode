#!/bin/sh
# Connects for real to sshd containers (test/remote/ssh_e2e_test.dart): a
# password-only one (127.0.0.1:2221), a key-only one (:2222), and a jump
# host (:2223, password) in front of one with no port of its own (`inner`,
# key); and one for a bad network (:2224, key), which may shape its own
# traffic (netem: test/remote/ssh_resilience_e2e_test.dart). Builds the
# server from the sources for them. Needs Docker.
#
#   sh tool/ssh_e2e.sh          start them, run the tests, leave them up
#   sh tool/ssh_e2e.sh --up     start them only (for another machine to
#                               run the tests: BAOCODE_SSH_E2E_BIND=0.0.0.0
#                               to listen on the network, not this one only)
#   sh tool/ssh_e2e.sh --down   remove them
set -eu
cd "$(dirname "$0")/.."
work="${BAOCODE_SSH_E2E:-${TMPDIR:-/tmp}/baocode-ssh-e2e}"
containers="bao-e2e-pw bao-e2e-key bao-e2e-bastion bao-e2e-otp-bastion bao-e2e-inner bao-e2e-flaky"
bind="${BAOCODE_SSH_E2E_BIND:-127.0.0.1}"

if [ "${1:-}" = --down ]; then
  docker rm -f $containers >/dev/null 2>&1 || true
  docker network rm bao-e2e >/dev/null 2>&1 || true
  exit 0
fi

mkdir -p "$work"
[ -f "$work/testkey" ] || ssh-keygen -q -t ed25519 -N '' -f "$work/testkey" -C baocode-ssh-e2e
cat > "$work/pam_otp.c" <<'PAM'
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
  const struct pam_conv *conv = NULL;
  if (pam_get_item(pamh, PAM_CONV, (const void **)&conv) != PAM_SUCCESS || !conv)
    return PAM_AUTH_ERR;
  struct pam_message msg = { .msg_style = PAM_PROMPT_ECHO_OFF, .msg = "Verification code: " };
  const struct pam_message *pmsg = &msg;
  struct pam_response *resp = NULL;
  if (conv->conv(1, &pmsg, &resp, conv->appdata_ptr) != PAM_SUCCESS || !resp || !resp->resp)
    return PAM_AUTH_ERR;
  FILE *f = fopen("/run/otp_seq", "r+");
  if (!f) { free(resp->resp); free(resp); return PAM_AUTH_ERR; }
  long seq = 0;
  if (fscanf(f, "%ld", &seq) != 1) { fclose(f); free(resp->resp); free(resp); return PAM_AUTH_ERR; }
  char expected[32];
  snprintf(expected, sizeof(expected), "%ld", seq);
  int ok = strcmp(resp->resp, expected) == 0;
  if (ok) {
    rewind(f);
    fprintf(f, "%ld\n", seq + 1);
    fflush(f);
  }
  fclose(f);
  free(resp->resp);
  free(resp);
  return ok ? PAM_SUCCESS : PAM_AUTH_ERR;
}
PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
  return PAM_SUCCESS;
}
PAM
cat > "$work/Dockerfile" <<'DOCKER'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server iproute2 procps gcc libc6-dev libpam0g-dev \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd && rm -f /etc/ssh/ssh_host_*
COPY pam_otp.c /tmp/pam_otp.c
RUN mkdir -p /lib/security && gcc -fPIC -shared -o /lib/security/pam_otp.so /tmp/pam_otp.c -lpam \
 && rm -f /tmp/pam_otp.c
COPY start.sh /start.sh
RUN chmod +x /start.sh
CMD ["/start.sh"]
DOCKER
cat > "$work/start.sh" <<'START'
#!/bin/sh
# Host keys of its own: a container made again has others.
ssh-keygen -A >/dev/null
add_user() {
  u="$1"
  useradd -m -s /bin/bash "$u"
  if [ -n "${SSH_KEY:-}" ]; then
    home="/home/$u"
    mkdir -p "$home/.ssh" && echo "$SSH_KEY" > "$home/.ssh/authorized_keys"
    chown -R "$u" "$home/.ssh" && chmod 700 "$home/.ssh" && chmod 600 "$home/.ssh/authorized_keys"
  fi
}
add_user "$SSH_USER"
if [ -n "${SSH_EXTRA_USER:-}" ]; then
  add_user "$SSH_EXTRA_USER"
fi
if [ "${SSH_OTP:-}" = 1 ]; then
  echo "$SSH_USER:$SSH_PASSWORD" | chpasswd
  echo 100001 > /run/otp_seq
  printf 'auth required pam_unix.so\nauth required /lib/security/pam_otp.so\naccount required pam_unix.so\nsession required pam_unix.so\n' \
    > /etc/pam.d/sshd
  printf 'UsePAM yes\nKbdInteractiveAuthentication yes\nPasswordAuthentication no\nPubkeyAuthentication no\n' \
    > /etc/ssh/sshd_config.d/auth.conf
elif [ -n "${SSH_PASSWORD:-}" ]; then
  echo "$SSH_USER:$SSH_PASSWORD" | chpasswd
  printf 'PasswordAuthentication yes\nKbdInteractiveAuthentication no\nPubkeyAuthentication no\n' \
    > /etc/ssh/sshd_config.d/auth.conf
else
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/auth.conf
fi
exec /usr/sbin/sshd -D -e
START
docker build -q -t baocode-ssh-e2e "$work" >/dev/null

key="$(cat "$work/testkey.pub")"
docker rm -f $containers >/dev/null 2>&1 || true
docker network create bao-e2e >/dev/null 2>&1 || true
run() { docker run -d --network bao-e2e "$@" baocode-ssh-e2e >/dev/null; }
run --name bao-e2e-pw -p $bind:2221:22 -e SSH_USER=tester -e SSH_PASSWORD=pw-secret
run --name bao-e2e-key -p $bind:2222:22 -e SSH_USER=tester -e SSH_KEY="$key"
run --name bao-e2e-bastion -p $bind:2223:22 -e SSH_USER=ops -e SSH_PASSWORD=bastion-secret
run --name bao-e2e-otp-bastion -p $bind:2225:22 -e SSH_USER=ops -e SSH_PASSWORD=bastion-secret -e SSH_OTP=1
run --name bao-e2e-inner --network-alias inner -e SSH_USER=tester -e SSH_EXTRA_USER=fresh -e SSH_KEY="$key"
run --name bao-e2e-flaky --cap-add NET_ADMIN -p $bind:2224:22 -e SSH_USER=tester -e SSH_KEY="$key"

dart run tool/build_remote_server.dart --out "$work/remote"
[ "${1:-}" = --up ] && exit 0
BAOCODE_SSH_E2E="$work" BAOCODE_REMOTE_SERVER_DIR="$work/remote" \
  flutter test test/remote/ssh_e2e_test.dart test/remote/ssh_resilience_e2e_test.dart \
  --run-skipped -t ssh-e2e
