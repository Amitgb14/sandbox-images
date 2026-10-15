#!/bin/sh
# smoke.sh IMAGE: checks a built workstation image in a container — the
# programs are there, nothing is setuid, and the desktop starts and serves VNC
# on loopback as the sandbox user.
#
# What it cannot check in a container: running a Flatpak app. bubblewrap needs
# to mount /proc in a fresh namespace, which a container does not allow; a
# Firecracker guest does. See docs/workstation.md, "Checking on a real host".
#
#   ENGINE   docker or podman (default: whichever is installed, docker first)
set -eu

image=${1:?usage: smoke.sh IMAGE}
engine=${ENGINE:-$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)}
name=sandbox-workstation-smoke-$$

fail() { echo "smoke: FAIL: $*" >&2; exit 1; }
cleanup() { "$engine" rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "smoke: programs"
"$engine" run --rm --user 1001:1001 "$image" sh -c '
  for p in sandbox-desktop Xvnc startxfce4 xfwm4 xfce4-panel xfdesktop thunar \
           chromium xfce4-terminal mousepad ristretto evince file-roller flatpak \
           openbox xterm; do
    command -v "$p" >/dev/null || { echo "missing: $p"; exit 1; }
  done
  flatpak list --system --app --columns=application | grep -qx com.github.PintaProject.Pinta \
    || { echo "missing: Pinta"; exit 1; }
  test -s /usr/share/sandbox-workstation/flathub.flatpakrepo || { echo "missing: flathub.flatpakrepo"; exit 1; }
' || fail "a program is missing"

echo "smoke: flatpak has a system bus to ask"
# The container, like the guest, has no system bus; the wrapper starts one.
"$engine" run --rm --user 1001:1001 "$image" sh -c '
  [ "$(command -v flatpak)" = /usr/local/bin/flatpak ] || { echo "flatpak is not the wrapper"; exit 1; }
  flatpak --version >/dev/null && flatpak --version >/dev/null
  n=$(pgrep -u 1001 -c -x dbus-daemon)
  [ "$n" -eq 1 ] || { echo "$n private system buses"; exit 1; }
  dbus-send --bus="unix:path=/tmp/runtime-1001/flatpak-system-bus" --dest=org.freedesktop.DBus \
    --print-reply / org.freedesktop.DBus.Peer.Ping >/dev/null || { echo "the bus does not answer"; exit 1; }
' || fail "flatpak would have no system bus"

echo "smoke: no setuid or setgid files"
n=$("$engine" run --rm "$image" sh -c 'find / -xdev -type f -perm /6000 2>/dev/null | wc -l')
[ "$n" -eq 0 ] || fail "$n setuid or setgid files"

echo "smoke: the desktop starts"
"$engine" run -d --name "$name" --user 1001:1001 "$image" sandbox-desktop >/dev/null
i=0
until "$engine" exec "$name" sh -c '
  printf "" | timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/5900; head -c 4 <&3" | grep -q RFB
' 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { "$engine" logs "$name" >&2; fail "no VNC server on 127.0.0.1:5900"; }
  sleep 1
done

# Give the session a moment, then look for its parts, all as the sandbox user.
sleep 5
"$engine" exec "$name" sh -c '
  for p in Xvnc xfwm4 xfce4-panel xfdesktop; do
    pgrep -u 1001 -x "$p" >/dev/null || { echo "not running: $p"; exit 1; }
  done
  if pgrep -u 0 -x Xvnc >/dev/null; then echo "Xvnc runs as root"; exit 1; fi
  # Loopback only.
  if grep -q " 00000000:170C " /proc/net/tcp ||
     grep -q " 00000000000000000000000000000000:170C " /proc/net/tcp6 2>/dev/null; then
    echo "5900 listens beyond loopback"; exit 1
  fi
' || { "$engine" logs "$name" >&2; fail "the desktop is not right"; }

echo "smoke: starting it again reuses the running desktop"
# As Studio's Desktop tab does each time it connects.
"$engine" exec "$name" sh -c '
  sandbox-desktop >/tmp/again.log 2>&1 & again=$!
  sleep 5
  kill -0 $again 2>/dev/null || { echo "the second start did not stay up"; cat /tmp/again.log; exit 1; }
  grep -q "already running" /tmp/again.log || { echo "the second start did not say so"; cat /tmp/again.log; exit 1; }
  n=$(pgrep -u 1001 -c -x xfce4-session)
  [ "$n" -eq 1 ] || { echo "$n desktop sessions"; exit 1; }
  kill $again
' || fail "a second start is not right"

echo "smoke: ok"
