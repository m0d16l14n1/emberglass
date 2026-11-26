#!/bin/sh
# emberglass on fake sysfs trees and a sample Waybar config (no root, nothing on the machine is touched).
#   sh tests/run.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { n=$1; shift; if "$@"; then pass=$((pass + 1)); echo "ok   $n"; else fail=$((fail + 1)); echo "FAIL $n"; fi; }
has() { grep -q "$2" "$T/out/$1"; }
hasnt() { ! grep -q "$2" "$T/out/$1"; }

tree() {  # $1 = full | nodie | zerodie | bare
  R=$T/root; rm -rf "$R" "$T/out"; mkdir -p "$R/proc" "$T/out"
  printf 'cpu  100 0 100 800 0 0 0 0 0 0\n' > "$R/proc/stat"
  printf 'MemTotal: 32000000 kB\nMemAvailable: 28000000 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$R/proc/meminfo"
  [ "$1" = bare ] && return
  h=$R/sys/class/hwmon/hwmon0; mkdir -p "$h"; echo macsmc_hwmon > "$h/name"
  i=1; for kv in Tp01:61000 Tp02:64000 Te01:55000 Tg01:58000; do
    echo "${kv%%:*}" > "$h/temp${i}_label"; echo "${kv#*:}" > "$h/temp${i}_input"; i=$((i + 1)); done
  echo "Total System Power" > "$h/power1_label"; echo 6100000 > "$h/power1_input"
  for p in 0:4464000:3000000 4:2964000:1000000; do
    d=$R/sys/devices/system/cpu/cpufreq/policy${p%%:*}; mkdir -p "$d"; q=${p#*:}
    echo "${q%%:*}" > "$d/cpuinfo_max_freq"; echo "${q#*:}" > "$d/scaling_cur_freq"; done
  b=$R/sys/class/power_supply/macsmc-battery; mkdir -p "$b"; echo Battery > "$b/type"; echo 77 > "$b/capacity"
  echo 80 > "$b/charge_control_end_threshold"; echo 75 > "$b/charge_control_start_threshold"; echo Charging > "$b/status"
  case "$1" in
    full|zerodie) z=$R/sys/class/thermal/thermal_zone0; mkdir -p "$z"; echo soc-die-thermal > "$z/type"
                  [ "$1" = full ] && echo 52000 > "$z/temp" || echo 0 > "$z/temp"
                  g=$R/sys/class/drm/card0/device; mkdir -p "$g"
                  printf 'pstate_status valid\npstate 12\nachieved_frequency_hz 1578000000\n' > "$g/agx_stats" ;;
  esac
}
run() { EMBERGLASS_ROOT=$T/root EMBERGLASS_OUT=$T/out EMBERGLASS_ONCE=1 python3 -I "$HERE/emberglass-sampler"; }

tree full; run
check "full: SoC die shown" has detail.txt '^SoC die      52°C'
check "full: panel uses the die" has panel.txt '^52°  6.1 W  3.8 G$'
check "full: GPU clock" has detail.txt '^GPU          58°C  1578 MHz  (pstate 12)'
check "full: HUD" has hud.txt '^SoC 52°C  CPU 64°  GPU 58° 1578 MHz  6.1 W$'
check "full: charge limit" has detail.txt '^Charge limit 80% (resumes at 75%)'

tree nodie; run
check "no die zone: no SoC line" hasnt detail.txt 'SoC'
check "no die zone: no SoC in HUD" hasnt hud.txt 'SoC'
check "no die zone: panel uses the hottest sensor" has panel.txt '^64°  6.1 W'
check "no GPU stats: no clock / idle shown" hasnt detail.txt 'idle\|MHz'
check "no dashes anywhere" sh -c "! grep -q '–' '$T/out/detail.txt' '$T/out/panel.txt' '$T/out/hud.txt'"

tree zerodie; run
check "die zone reading 0: treated as missing" hasnt detail.txt 'SoC'

tree bare; run
check "no sensors at all: only RAM (and load)" sh -c "grep -q '^RAM' '$T/out/detail.txt' && ! grep -v '^RAM\|^CPU load' '$T/out/detail.txt'"
check "no sensors at all: panel = RAM only" has panel.txt '^3.8 G$'
check "no sensors at all: no error" [ ! -e "$T/out/error.txt" ]
check "waybar.json valid" python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['class']=='cool' and 'percentage' not in d" "$T/out/waybar.json"
tree full; run
check "waybar.json class/percentage" python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['percentage']==52 and d['class']=='cool'" "$T/out/waybar.json"

# Waybar config editing (an Omarchy-style JSONC config)
H=$T/home; mkdir -p "$H/.config/waybar"; C=$H/.config/waybar/config.jsonc
cat > "$C" <<'EOF'
{
  "reload_style_on_change": true,
  "layer": "top",
  // the bar
  "modules-left": ["custom/omarchy", "hyprland/workspaces"],
  "modules-center": ["clock"],
  "modules-right": [
    "tray",
    "bluetooth",
    "network",
    "battery"
  ],
  "clock": { "format": "{:%H:%M}" }
}
EOF
cp "$C" "$T/orig"
strip() { python3 -c "import re,json,sys; t=open(sys.argv[1]).read(); json.loads(re.sub(r'//[^\n]*','',t))" "$1"; }
HOME=$H sh "$HERE/emberglass" waybar add >/dev/null 2>&1
check "waybar add: valid JSON afterwards" strip "$C"
check "waybar add: module first in modules-right" python3 -c "import re,json,sys; d=json.loads(re.sub(r'//[^\n]*','',open(sys.argv[1]).read())); assert d['modules-right'][0]=='custom/emberglass' and d['custom/emberglass']['return-type']=='json'" "$C"
check "waybar add: backup kept" cmp -s "$T/orig" "$C.emberglass-backup"
HOME=$H sh "$HERE/emberglass" waybar add >/dev/null 2>&1
check "waybar add twice: added once" [ "$(grep -c 'emberglass:begin' "$C")" = 1 ]
HOME=$H sh "$HERE/emberglass" waybar remove >/dev/null 2>&1
check "waybar remove: valid JSON" strip "$C"
check "waybar remove: module gone" sh -c "! grep -q emberglass '$C'"
check "waybar remove: same modules as before" python3 -c "import re,json,sys; f=lambda p: json.loads(re.sub(r'//[^\n]*','',open(p).read())); assert f(sys.argv[1])==f(sys.argv[2])" "$C" "$T/orig"

# Installer into a staging root
D=$T/destdir; DESTDIR=$D sh "$HERE/install.sh" install >/dev/null 2>&1
check "install.sh DESTDIR: files" [ -x "$D/usr/local/bin/emberglass" ] && [ -x "$D/usr/local/lib/emberglass/emberglass-sampler" ] && [ -f "$D/usr/local/share/plasma/plasmoids/org.emberglass.sensors/metadata.json" ] && [ -f "$D/etc/systemd/system/emberglass.service" ]
check "install.sh DESTDIR: unit path filled" grep -q 'ExecStart=/usr/bin/env python3 -I /usr/local/lib/emberglass/emberglass-sampler' "$D/etc/systemd/system/emberglass.service"
DESTDIR=$D sh "$HERE/install.sh" uninstall >/dev/null 2>&1
check "uninstall removes them" [ ! -e "$D/usr/local/bin/emberglass" ] && [ ! -e "$D/usr/local/lib/emberglass" ] && [ ! -e "$D/usr/local/share/plasma/plasmoids/org.emberglass.sensors" ]

echo "== $pass passed, $fail failed"
[ $fail = 0 ]
