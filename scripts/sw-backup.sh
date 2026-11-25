#!/usr/bin/env bash
# sw-backup.sh backup [-o <parent dir>] [name]   - back up the switch into <parent dir>/<name> (default:
#                                                   <SW_HOME>/backup/<SW_HOST>-<date-time>)
# sw-backup.sh check <backup> [<backup2>]       - check a backup's files against its info.txt; with a second backup
#                                                   also compare the two running configurations (diff of RunningCLI)
#
# A backup is one CLI session (sw.sh) that runs `show versions` and saves RunningCLI, Config and StartupInfo over
# TFTP (as sw-get.sh), plus info.txt: switch, date, firmware, and size and sha256 of every file. About a minute,
# most of it the Config file. Nothing on the switch is changed.
#   RunningCLI.cli   the running configuration as CLI commands; passwords are written as "[PASSWORD]" (placeholder)
#   Config.cfg       the full configuration as SNMP objects, the file `load ... filetype Config` takes back
#   StartupInfo.txt  the events of the last start; versions.txt  `show versions`
# Exit code of check: 0 = files intact (and the same RunningCLI), 1 = not.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd); . "$S/config.sh"

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -c1-64; else shasum -a 256 "$1" | cut -c1-64; fi; }
size() { wc -c < "$1" | tr -d ' '; }
runcli() { grep -v '^#' "$1" | tr -d '\r'; }   # without the comment lines on top

backup() {
  local parent="$SW_HOME/backup" name d out
  [ "${1:-}" = -o ] && { parent=$2; shift 2; }
  name=${1:-$SW_HOST-$(date +%Y%m%d-%H%M%S)}; d="$parent/$name"
  [ -e "$d" ] && { echo "backup: $d exists" >&2; exit 2; }
  mkdir -p "$d"
  out=$(SW_TIMEOUT=${SW_SAVE_TIMEOUT:-120} "$S/sw.sh" --tftp "$d" 3 "show versions" \
        "save filetype RunningCLI tftp ipv4 @IP@ port @PORT@ file RunningCLI.cli" \
        "save filetype Config tftp ipv4 @IP@ port @PORT@ file Config.cfg" \
        "save filetype StartupInfo tftp ipv4 @IP@ port @PORT@ file StartupInfo.txt") || { printf '%s\n' "$out"; echo "backup: FAILED" >&2; exit 1; }
  printf '%s\n' "$out" | awk '/CLI# show versions/{on=1; next} on && /^CLI/{exit} on' > "$d/versions.txt"
  local f missing=0
  for f in RunningCLI.cli Config.cfg StartupInfo.txt; do [ -s "$d/$f" ] || { echo "backup: $f missing" >&2; missing=1; }; done
  [ $missing = 0 ] || exit 1
  {
    echo "switch: $SW_HOST"
    echo "date: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "device: $(awk -F'|' '/Basic Device/{gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$4); print $2 ", " $4; exit}' "$d/versions.txt")"
    echo "firmware: $(awk -F'|' '/Firmware_Running/{gsub(/ /,"",$2); print $2; exit}' "$d/versions.txt")"
    echo "files (bytes, sha256):"
    for f in RunningCLI.cli Config.cfg StartupInfo.txt versions.txt; do echo "  $f $(size "$d/$f") $(sha "$d/$f")"; done
  } > "$d/info.txt"
  cat "$d/info.txt"; echo "backup: $d"
}

intact() {   # intact <backup>: every file as in its info.txt
  local d=$1 f n h ok=0
  [ -f "$d/info.txt" ] || { echo "check: $d/info.txt missing"; return 1; }
  while read -r f n h; do
    if [ ! -f "$d/$f" ]; then echo "check: $d/$f missing"; ok=1
    elif [ "$(size "$d/$f")" != "$n" ] || [ "$(sha "$d/$f")" != "$h" ]; then echo "check: $d/$f changed since the backup"; ok=1; fi
  done < <(sed -n '/^files/,$p' "$d/info.txt" | sed 1d)
  [ $ok = 0 ] && echo "check: $d intact ($(sed -n '/^files/,$p' "$d/info.txt" | sed 1d | wc -l | tr -d ' ') files)"
  return $ok
}

check() {
  local a=${1:?usage: sw-backup.sh check <backup> [<backup2>]} b=${2:-} rc=0
  intact "$a" || rc=1
  [ -z "$b" ] && return $rc
  intact "$b" || rc=1
  if diff <(runcli "$a/RunningCLI.cli") <(runcli "$b/RunningCLI.cli") > /dev/null; then
    echo "check: same running configuration ($a, $b)"
  else
    echo "check: running configuration differs (< $a, > $b):"
    diff <(runcli "$a/RunningCLI.cli") <(runcli "$b/RunningCLI.cli") || true
    rc=1
  fi
  return $rc
}

case "${1:-}" in
  backup) shift; backup "$@" ;;
  check)  shift; check "$@" ;;
  *) sed -n 2,13p "$0"; exit 2 ;;
esac
