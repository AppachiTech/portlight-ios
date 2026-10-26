#!/usr/bin/env bash
# Runs the demo SSH server (see Dockerfile) on this Mac, reachable from a
# phone on the same Wi-Fi.
#
#   demo-server.sh up [--with-claude]   build and start it
#   demo-server.sh key 'ssh-ed25519 …'  allow a public key (from Portlight)
#   demo-server.sh status               show how to connect
#   demo-server.sh down                 stop and remove it
#
# Key login only. Stop it when you're done recording.
set -euo pipefail
cd "$(dirname "$0")"

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
  local keys
  keys=$(docker exec "$NAME" sh -c 'grep -c . /home/dev/.ssh/authorized_keys 2>/dev/null; true' | head -1)
  keys=${keys:-0}
  cat <<EOF
Demo server is running.

  Host:      $(lan_ip)
  Port:      $PORT
  Username:  dev
  Log in with a key: $keys allowed so far.

Host key fingerprints, to compare with what Portlight shows:
$(docker exec "$NAME" sh -c 'for f in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub; do ssh-keygen -lf "$f"; done' | sed 's/^/  /')
EOF
}

case "${1:-}" in
  up)
    claude=0
    [ "${2:-}" = "--with-claude" ] && claude=1
    docker build --build-arg WITH_CLAUDE=$claude -t "$IMAGE" .
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    # The volume keeps allowed keys across restarts.
    docker run -d --name "$NAME" --hostname atlas \
      -p "$PORT:22" -v portlight-demo-keys:/home/dev/.ssh "$IMAGE" >/dev/null
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
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
