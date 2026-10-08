#!/usr/bin/env bash
# Runs the remote server's macOS builds (tool/build_remote_server.dart) on
# this Mac, as tool/test_remote_server.sh runs the Linux ones in Docker:
# each has to start, answer `initialize` as the app expects, and list a
# folder. On Apple silicon the x64 build runs under Rosetta.
#
#   tool/test_remote_server_macos.sh [build/remote]
#
# Needs python3. CI runs it where it builds the server
# (.github/workflows/release.yml).
set -euo pipefail

dir=$(cd "${1:-build/remote}" && pwd)
version=$(cat "$dir/VERSION")
data=$(mktemp -d)
trap 'rm -rf "$data"' EXIT
failed=0

# What the answers have to say, checked by python3: argv is the
# architecture and VERSION, stdin the server's output.
check=$(cat <<'EOF'
import json, sys
arch, version = sys.argv[1:]
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
if platform['os'] != 'darwin' or platform['arch'] != arch:
    sys.exit(f'says it runs on {platform}, not darwin {arch}')
if not version.startswith(hello['version'].replace('+', '.') + '-'):
    sys.exit(f'says it is {hello["version"]}, VERSION is {version}')
listing = answers.get(2, {}).get('result')
if not isinstance(listing, list) or not listing:
    sys.exit(f'no listing of /etc: {answers.get(2)}')
print(f"protocol {hello['protocol']}, {platform}, {len(listing)} entries in /etc")
EOF
)

for arch in x64 arm64; do
  binary="$dir/baocode-server-darwin-$arch"
  if [ ! -f "$binary" ]; then
    echo "No $binary: build it first (dart run tool/build_remote_server.dart)" >&2
    exit 1
  fi
  printf '%-8s ' "$arch"
  # As the upload leaves it on a host: executable, signed as built.
  chmod 755 "$binary"
  if ! output=$(
    {
      echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
      echo '{"jsonrpc":"2.0","id":2,"method":"fs/list","params":{"root":"/etc","path":"/etc"}}'
      sleep 3
    } | "$binary" --data "$data/$arch" 2>&1
  ); then
    echo "FAIL: the server exited with an error"
    echo "$output" | sed 's/^/    /'
    failed=1
    continue
  fi
  if result=$(python3 -c "$check" "$arch" "$version" <<<"$output" 2>&1); then
    echo "ok: $result"
  else
    echo "FAIL"
    echo "$output" | sed 's/^/    /' | head -20
    failed=1
  fi
done

exit $failed
