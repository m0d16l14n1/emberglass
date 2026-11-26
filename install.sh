#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# emberglass installer (Linux, systemd).
#   sudo ./install.sh [install]      install or update; also puts the widget on your Plasma panel and/or the module
#                                    in your Waybar config when it finds them (--no-desktop skips that)
#   sudo ./install.sh uninstall      take everything out again (panel widget and Waybar module too)
#   ./install.sh status              is it running, what does it show
# Options: --prefix DIR (default /usr/local), --no-desktop. NixOS: use the flake module (README.md).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ACTION=install; PREFIX=/usr/local; DESKTOP=1
DESTDIR=${DESTDIR:-}                         # packaging / tests: install into a staging root, start nothing
while [ $# -gt 0 ]; do
  case "$1" in
    install|uninstall|remove|status) ACTION=$1 ;;
    --prefix) PREFIX=${2:?--prefix DIR}; shift ;;
    --no-desktop) DESKTOP=0 ;;
    -h|--help) sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac; shift
done
[ "$ACTION" = remove ] && ACTION=uninstall
BIN=$DESTDIR$PREFIX/bin; LIB=$DESTDIR$PREFIX/lib/emberglass; PLASMOIDS=$DESTDIR$PREFIX/share/plasma/plasmoids
UNIT=$DESTDIR/etc/systemd/system/emberglass.service; ID=org.emberglass.sensors
live() { [ -z "$DESTDIR" ]; }
say() { echo "==> $*"; }

if [ "$ACTION" = status ]; then
  systemctl --no-pager status emberglass.service 2>/dev/null | head -3 || true; echo
  exec sh "$PREFIX/bin/emberglass" show
fi
if live; then
  [ "$(id -u)" = 0 ] || { echo "Run it with sudo: sudo ./install.sh $ACTION"; exit 1; }
  [ -e /etc/NIXOS ] && { echo "NixOS: add the emberglass flake module to your configuration instead (README.md, 'NixOS')."; exit 1; }
  [ -d /run/systemd/system ] || { echo "emberglass needs systemd (the sampler is a systemd service)."; exit 1; }
fi

# as_user CMD...: run in the desktop session of the user who called sudo (Plasma / Waybar steps)
as_user() {
  [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] || return 1
  uid=$(id -u "$SUDO_USER"); home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  runuser -u "$SUDO_USER" -- env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}
desktop() {  # $1 = add | remove
  live && [ $DESKTOP = 1 ] || return 0
  [ -n "${SUDO_USER:-}" ] || { echo "    (not run through sudo: add the widget yourself, see below)"; return 0; }
  if as_user busctl --user --no-pager status org.kde.plasmashell >/dev/null 2>&1; then as_user sh "$1" panel "$2" || true; fi
  home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  if [ -f "$home/.config/waybar/config.jsonc" ] || [ -f "$home/.config/waybar/config" ]; then as_user sh "$1" waybar "$2" || true; fi
  return 0
}

if [ "$ACTION" = uninstall ]; then
  [ -f "$BIN/emberglass" ] && desktop "$BIN/emberglass" remove
  live && systemctl disable --now emberglass.service 2>/dev/null || true
  rm -rf "$UNIT" "$BIN/emberglass" "$LIB" "$PLASMOIDS/$ID"
  live && { systemctl daemon-reload; rm -rf /run/emberglass; }
  say "emberglass removed"
  exit 0
fi

# install
command -v python3 >/dev/null 2>&1 || { echo "emberglass needs python3 (install it with your package manager)."; exit 1; }
live && ! ls /sys/class/hwmon/*/name >/dev/null 2>&1 && echo "    note: no hwmon sensors on this machine; the panel will show memory and load only"
mkdir -p "$BIN" "$LIB" "$PLASMOIDS" "$(dirname "$UNIT")"
install -m 0755 "$HERE/emberglass-sampler" "$LIB/emberglass-sampler"
install -m 0755 "$HERE/emberglass" "$BIN/emberglass"
rm -rf "$PLASMOIDS/$ID"; cp -R "$HERE/plasma/$ID" "$PLASMOIDS/$ID"; chmod -R a+rX "$PLASMOIDS/$ID"
sed "s|@LIBDIR@|$PREFIX/lib/emberglass|g" "$HERE/systemd/emberglass.service" > "$UNIT"; chmod 0644 "$UNIT"
say "installed: $BIN/emberglass, $LIB/emberglass-sampler, $PLASMOIDS/$ID, $UNIT"
live || exit 0
command -v restorecon >/dev/null 2>&1 && restorecon -RF "$BIN/emberglass" "$LIB" "$PLASMOIDS/$ID" "$UNIT" 2>/dev/null || true
systemctl daemon-reload
systemctl enable emberglass.service >/dev/null 2>&1
systemctl restart emberglass.service
i=0; while [ ! -s /run/emberglass/detail.txt ] && [ $i -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
echo; sh "$BIN/emberglass" show || true; echo
desktop "$BIN/emberglass" add
cat <<EOF

Done. The sampler runs as emberglass.service and writes to /run/emberglass.
  KDE Plasma: right-click the panel > Add Widgets > "Emberglass" (or: emberglass panel add)
  Waybar:     emberglass waybar add
  MangoHud:   emberglass hud
  Terminal:   emberglass watch
EOF
