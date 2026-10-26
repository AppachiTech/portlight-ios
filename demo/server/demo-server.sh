#!/usr/bin/env bash
# Runs the demo SSH server (see Dockerfile) on this Mac, reachable from a
# phone on the same Wi-Fi.
#
#   demo-server.sh up [--with-claude] [--with-suvadu]
#                                       build and start it (PORT=2223 … for another port)
#   demo-server.sh key 'ssh-ed25519 …'  allow a public key (from Portlight)
#   demo-server.sh status               show how to connect
#   demo-server.sh down                 stop and remove it
#
# Key login only. Stop it when you're done recording.
set -euo pipefail
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$self")"

NAME=portlight-demo
IMAGE=portlight-demo
PORT=${PORT:-2222}

lan_ip() {
  ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<this Mac's IP>"
}

status() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "Not running. Start it with: $0 up"
    return
  fi
  local keys port
  # The port it was started with, which may differ from $PORT now.
  port=$(docker port "$NAME" 22/tcp | head -1 | sed 's/.*://')
  keys=$(docker exec "$NAME" sh -c 'grep -c . /home/dev/.ssh/authorized_keys 2>/dev/null; true' | head -1)
  keys=${keys:-0}
  cat <<EOF
Demo server is running.

  Host:      $(lan_ip)
  Port:      $port
  Username:  dev
  Log in with a key: $keys allowed so far.

Host key fingerprints, to compare with what Portlight shows:
$(docker exec "$NAME" sh -c 'for f in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub; do ssh-keygen -lf "$f"; done' | awk '{print "  " $2 " " $NF}')
EOF
}

case "${1:-}" in
  up)
    claude=0 suvadu=0
    for option in "${@:2}"; do
      case "$option" in
        --with-claude) claude=1 ;;
        --with-suvadu) suvadu=1 ;;
        *) echo "Unknown option $option (use --with-claude, --with-suvadu)" >&2; exit 1 ;;
      esac
    done
    docker build --build-arg WITH_CLAUDE=$claude --build-arg WITH_SUVADU=$suvadu -t "$IMAGE" .
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    # The volume keeps allowed keys across restarts.
    if ! docker run -d --name "$NAME" --hostname atlas \
      -p "$PORT:22" -v portlight-demo-keys:/home/dev/.ssh "$IMAGE" >/dev/null; then
      docker rm -f "$NAME" >/dev/null 2>&1 || true
      echo "Couldn't start it. If port $PORT is already in use, pick another: PORT=2223 $0 up" >&2
      exit 1
    fi
    docker exec "$NAME" sh -c 'touch /home/dev/.ssh/authorized_keys && chown -R dev:dev /home/dev/.ssh && chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/authorized_keys'
    status
    echo
    echo "Next: in Portlight, Keys → + → New Ed25519 key, copy its public key, then run:"
    echo "  $0 key 'ssh-ed25519 AAAA… iPhone'"
    ;;
  key)
    key="${2:-}"
    if ! printf '%s' "$key" | grep -Eq '^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/=]+( .*)?$'; then
      echo "Pass one public key line in quotes, e.g. $0 key 'ssh-ed25519 AAAA… iPhone'" >&2
      exit 1
    fi
    printf '%s\n' "$key" | docker exec -i "$NAME" sh -c 'cat >> /home/dev/.ssh/authorized_keys && chown dev:dev /home/dev/.ssh/authorized_keys'
    echo "Key added."
    status
    ;;
  status)
    status
    ;;
  down)
    docker rm -f "$NAME" >/dev/null 2>&1 && echo "Stopped." || echo "Wasn't running."
    ;;
  *)
    sed -n '2,11p' "$self" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
