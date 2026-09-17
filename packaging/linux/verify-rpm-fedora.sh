#!/usr/bin/env bash
#
# Installs the built .rpm on a real Fedora system and launches it. Meant to run
# *inside* a Fedora container, with dist/ mounted at /dist:
#
#   docker run --rm -v "$PWD/dist:/dist:ro" -v "$PWD/packaging/linux:/pkg:ro" \
#     fedora:41 bash /pkg/verify-rpm-fedora.sh
#
# Why this exists: the .rpm targets Fedora/RHEL, so testing it on Ubuntu proves
# almost nothing. Doing this found a real bug — the package installed happily
# and then aborted at launch with "Couldn't open libGLESv2.so.2", because
# libepoxy dlopen()s the GL libraries and no dependency generator can see that.
# A dev box hides it, since the GL stack is already there as a build dependency.
#
# Pass criteria: dnf resolves every dependency unaided, and the installed
# binary is still running after it has had time to open a window.
set -euo pipefail

echo "== $(cat /etc/fedora-release)"

# Fail on a slow mirror instead of hanging for half an hour.
printf 'timeout=30\nretries=2\n' >> /etc/dnf/dnf.conf

echo "== installing the package"
dnf install -y "$@" /dist/*.rpm
rpm -q dula-authenticator

echo "== the GL stack must have arrived via our own Requires"
for so in libEGL.so.1 libGLESv2.so.2; do
  ldconfig -p | grep -q "${so}" || {
    echo "MISSING: ${so} — the package's Requires did not pull it in" >&2
    exit 1
  }
  echo "   present: ${so}"
done

echo "== launching the installed binary"
dnf install -y -q xorg-x11-server-Xvfb dbus-x11 gnome-keyring
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
export DISPLAY=:99
eval "$(dbus-launch --sh-syntax)"
# Throwaway keyring passphrase for a disposable container; protects nothing.
eval "$(echo -n 'verify-ephemeral' | gnome-keyring-daemon --unlock --components=secrets)"
export GNOME_KEYRING_CONTROL
sleep 1

dula-authenticator > /tmp/run.log 2>&1 &
pid=$!
sleep 20
if ! kill -0 "${pid}" 2>/dev/null; then
  echo "FAILED: the app exited instead of staying up" >&2
  tail -20 /tmp/run.log >&2
  exit 1
fi
kill "${pid}" 2>/dev/null || true
echo "OK: the .rpm installs and runs on Fedora"
