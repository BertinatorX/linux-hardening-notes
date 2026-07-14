#!/usr/bin/env bash
# system-health-check.sh — a once-a-day "is everything still wired up?" report for a
# personal Linux workstation. Runs entirely as an unprivileged user (no sudo), prints a
# sectioned OK/WARN/FAIL report, keeps a rolling history on disk, and exits non-zero so a
# scheduler or the caller can react.
#
#   exit 0 = all OK   ·   exit 1 = warnings only   ·   exit 2 = at least one failure
#
# This is a SANITIZED, generic version of a tool I run on my own machine. The service
# names, mount points, and containers below are illustrative placeholders — edit the
# arrays near the top to match your own system. Every real hostname, IP, username, and
# path has been replaced with a placeholder or an environment variable on purpose.
set -u
export PATH=/usr/local/bin:/usr/bin:/bin
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ── configure for your system ───────────────────────────────────────────────
SYSTEM_UNITS=()                       # e.g. ("ufw" "sshd") — system units that must be active
USER_UNITS=()                         # e.g. ("syncthing") — systemd --user units that must be active
TIMERS=("fstrim.timer")               # maintenance timers that should be scheduled
DOCKER_CONTAINERS=()                  # e.g. ("media-server") — containers that should be running
MOUNTS=()                             # e.g. ("$HOME/Backup") — mountpoints to verify are mounted
STORAGE_PATHS=("/" "/home")           # filesystems to watch for capacity
DISK_WARN=85; DISK_FAIL=92            # percent-used thresholds
JOURNAL_ERR_OK=150                    # tune to your machine's quiet-day error baseline
# ────────────────────────────────────────────────────────────────────────────

OK=0; WARN=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; OK=$((OK+1)); }
warn() { printf '  [WARN] %s\n' "$1"; WARN=$((WARN+1)); }
fail() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
hdr()  { printf '\n— %s —\n' "$1"; }

# docker group may not be active in the current shell; fall back to `sg`
docker_ps() {
  if docker version >/dev/null 2>&1; then docker ps -a --format '{{.Names}}\t{{.State}}' 2>/dev/null
  else sg docker -c "docker ps -a --format '{{.Names}}\t{{.State}}'" 2>/dev/null; fi
}

report() {
printf '=== health report · %s ===\n' "$(date '+%Y-%m-%d %H:%M')"

hdr "systemd"
# Distinguish "0 failed units" from "manager unreachable" via the command's exit status,
# so an inaccessible manager can never masquerade as a clean bill of health.
for scope in "" "--user"; do
  label=$([ -z "$scope" ] && echo system || echo user)
  if out=$(systemctl $scope --failed --no-legend --plain 2>/dev/null); then
    if [ -z "$out" ]; then ok "no failed $label units"
    else fail "failed $label unit(s): $(printf '%s\n' "$out" | awk '{print $1}' | paste -sd' ')"; fi
  else warn "$label manager unreachable — skipped"; fi
done
for u in "${SYSTEM_UNITS[@]}"; do
  [ "$(systemctl is-active "$u" 2>/dev/null)" = active ] && ok "$u active" || fail "$u not active"
done
for u in "${USER_UNITS[@]}"; do
  [ "$(systemctl --user is-active "$u" 2>/dev/null)" = active ] && ok "$u (user) active" || warn "$u (user) not active"
done

hdr "mounts"
# Network mounts via x-systemd.automount leave an autofs stub on the path even when the
# backing server is offline, so `mountpoint` always returns true. Test the real fs type.
for m in "${MOUNTS[@]}"; do
  fst=$(findmnt -rn -o FSTYPE "$m" 2>/dev/null | tail -1)
  if [ -n "$fst" ] && [ "$fst" != autofs ]; then ok "$m mounted ($fst)"
  else warn "$m not mounted (backing server offline?)"; fi
done

hdr "containers"
if [ "${#DOCKER_CONTAINERS[@]}" -gt 0 ]; then
  dps=$(docker_ps); drc=$?
  if [ "$drc" -ne 0 ]; then warn "docker unreachable (daemon down or group inactive)"
  else
    for c in "${DOCKER_CONTAINERS[@]}"; do
      st=$(printf '%s\n' "$dps" | awk -F'\t' -v c="$c" '$1==c{print $2}')
      [ "${st:-}" = running ] && ok "$c running" || warn "$c: ${st:-not found}"
    done
  fi
fi

hdr "storage"
for mp in "${STORAGE_PATHS[@]}"; do
  pct=$(df --output=pcent "$mp" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ -z "$pct" ]; then warn "df failed for $mp"
  elif [ "$pct" -ge "$DISK_FAIL" ]; then fail "$mp at ${pct}% — clean up now"
  elif [ "$pct" -ge "$DISK_WARN" ]; then warn "$mp at ${pct}%"
  else ok "$mp at ${pct}%"; fi
done
# _TRANSPORT=kernel spans all boots; `-k` implies current-boot-only and would drop the
# errors logged just before a crash/reboot — exactly the ones worth seeing.
kerr=$(journalctl -S -24h -p err -q --no-pager _TRANSPORT=kernel 2>/dev/null \
       | grep -icE 'btrfs.*(error|corrupt|abort)|nvme|i/o error|ata error')
[ "$kerr" -eq 0 ] && ok "no storage errors in kernel log (24h, all boots)" \
                  || fail "$kerr storage-related kernel error(s) in 24h"

hdr "maintenance timers"
for t in "${TIMERS[@]}"; do
  [ "$(systemctl is-active "$t" 2>/dev/null)" = active ] && ok "$t scheduled" || warn "$t: not scheduled"
done

hdr "updates"
if ! ip route get 1.1.1.1 >/dev/null 2>&1; then
  ok "offline — update check skipped"
elif command -v checkupdates >/dev/null 2>&1; then
  out=$(timeout 60 checkupdates 2>/dev/null); rc=$?
  case $rc in
    0) n=$(printf '%s\n' "$out" | grep -c .); [ "$n" -ge 50 ] && warn "$n updates pending — update soon" || ok "$n update(s) pending" ;;
    2) ok "packages up to date" ;;
    124) warn "update check timed out" ;;
    *) warn "update check failed (rc $rc)" ;;
  esac
fi

hdr "hardware snapshot"
for d in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$d/name" 2>/dev/null)" = k10temp ] || continue   # AMD CPU sensor; adjust for your platform
  c=$(( ($(cat "$d/temp1_input" 2>/dev/null || echo 0) + 500) / 1000 ))
  [ "$c" -ge 95 ] && warn "CPU ${c}°C at rest" || ok "CPU ${c}°C"
  break
done
cf=$(cat /sys/class/power_supply/BAT0/charge_full 2>/dev/null)
cfd=$(cat /sys/class/power_supply/BAT0/charge_full_design 2>/dev/null)
if [ -n "${cf:-}" ] && [ -n "${cfd:-}" ] && [ "$cfd" -gt 0 ]; then
  bh=$(( 100 * cf / cfd ))
  [ "$bh" -lt 70 ] && warn "battery health ${bh}% of design" || ok "battery health ${bh}% of design"
fi

hdr "journal (24h)"
e=$(journalctl -p err -S -24h -q --no-pager 2>/dev/null | grep -c .)
if   [ "$e" -eq 0 ]; then ok "no error-level journal entries"
elif [ "$e" -le "$JOURNAL_ERR_OK" ]; then ok "$e error-level journal entries (normal background noise)"
else warn "$e error-level journal entries — investigate the top identifiers"; fi

printf '\n=== summary: %d ok · %d warn · %d fail ===\n' "$OK" "$WARN" "$FAIL"
}

# Emit to stdout AND keep the last 30 reports on disk. No `report | tee`: a pipeline runs
# report in a subshell and its OK/WARN/FAIL counters would never reach the exit logic below.
RPT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/health-reports"
mkdir -p "$RPT_DIR"
RPT="$RPT_DIR/health-$(date +%Y%m%d-%H%M).txt"
report > "$RPT" 2>&1
cat "$RPT"
ls -1t "$RPT_DIR"/health-*.txt 2>/dev/null | tail -n +31 | xargs -r rm -f

[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
