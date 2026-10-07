#!/usr/bin/env bash
# Runs the remote server's Linux builds (tool/build_remote_server.dart) in
# Docker, on the distributions remote hosts commonly run, x64 and arm64: each
# has to start, answer `initialize` as the app expects, and list a folder.
# The other architecture runs emulated (QEMU, or Rosetta in Docker Desktop).
#
#   tool/test_remote_server.sh [build/remote]
#
# Needs docker and python3. CI runs it before building the apps
# (.github/workflows/release.yml).
set -euo pipefail

dir=$(cd "${1:-build/remote}" && pwd)
version=$(cat "$dir/VERSION")
images=(ubuntu:20.04 ubuntu:24.04 debian:bookworm-slim rockylinux:8)
failed=0

# What the answers have to say, checked by python3: argv is the machine
# (uname -m) and VERSION, stdin the server's output.
check=$(cat <<'EOF'
import json, sys
machine, version = sys.argv[1:]
answers = {}
for line in sys.stdin:
    line = line.strip()
    if line.startswith('{'):
        message = json.loads(line)
        if 'id' in message:
            answers[message['id']] = message
hello = answers.get(1, {}).get('result')
if not hello:
    sys.exit(f'no answer to initialize: {answers.get(1)}')
platform = hello['platform']
arch = {'x86_64': 'x64', 'aarch64': 'arm64'}[machine]
if platform['os'] != 'linux' or platform['arch'] != arch:
    sys.exit(f'says it runs on {platform}, not linux {arch}')
if not version.startswith(hello['version'].replace('+', '.') + '-'):
    sys.exit(f'says it is {hello["version"]}, VERSION is {version}')
listing = answers.get(2, {}).get('result')
if not isinstance(listing, list) or not listing:
    sys.exit(f'no listing of /etc: {answers.get(2)}')
print(f"protocol {hello['protocol']}, {platform}, {len(listing)} entries in /etc")
EOF
)

for image in "${images[@]}"; do
  for platform in linux/amd64 linux/arm64; do
    docker pull -q --platform "$platform" "$image" > /dev/null
  done
done

for arch in x64 arm64; do
  case $arch in
    x64) platform=linux/amd64 machine=x86_64 ;;
    arm64) platform=linux/arm64 machine=aarch64 ;;
  esac
  binary="$dir/baocode-server-linux-$arch"
  if [ ! -f "$binary" ]; then
    echo "No $binary: build it first (dart run tool/build_remote_server.dart)" >&2
    exit 1
  fi
  for image in "${images[@]}"; do
    printf '%-8s %-22s ' "$arch" "$image"
    # The app's first requests, then a moment for the answers before stdin
    # ends (which ends the server, as a closed connection does).
    if ! output=$(
      {
        echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
        echo '{"jsonrpc":"2.0","id":2,"method":"fs/list","params":{"root":"/etc","path":"/etc"}}'
        sleep 3
      } | docker run --rm -i --platform "$platform" \
        -v "$binary:/usr/local/bin/baocode-server:ro" \
        "$image" baocode-server --data /tmp/baocode-server 2>&1
    ); then
      echo "FAIL: the server exited with an error"
      echo "$output" | sed 's/^/    /'
      failed=1
      continue
    fi
    if result=$(python3 -c "$check" "$machine" "$version" <<<"$output" 2>&1); then
      echo "ok: $result"
    else
      echo "FAIL"
      echo "$output" | sed 's/^/    /' | head -20
      failed=1
    fi
  done
done

exit $failed
