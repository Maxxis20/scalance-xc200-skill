#!/usr/bin/env bash
# sw.sh '<command>' ...                run CLI commands on the switch in one session, print the session (password ***)
# sw.sh first-login                   answer the questions of a factory-new switch's first login: "Default admin user
#                                     to be changed (y/n)?" -> y, new password from the variable named by SW_NEW_SECRET
# sw.sh --tftp <local dir> <n> '<command>' ...
#                                     the same with a TFTP receiver running during the session, on the machine the
#                                     switch talks to; waits for <n> files and puts them into <local dir>. In the
#                                     commands @IP@ / @PORT@ are that machine's address and the receiver's port.
#                                     (Used by sw-get.sh and sw-backup.sh.)
#
# One SSH session per call; a command is sent only at the CLI prompt, --More-- pages are answered, the pager is
# switched off first (SW_PAGER_OFF). Transport and settings: scripts/config.sh. Exit 3 on a timeout or when the
# switch asks first-login questions outside first-login mode.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd); . "$S/config.sh"
[ -n "$SW_HOST" ] || { echo "sw.sh: SW_HOST is not set (scripts/config.sh)" >&2; exit 2; }
MODE=run; TDIR=""; TN=0
case "${1:-}" in
  first-login) MODE=first-login; shift ;;
  --tftp) TDIR=$2; TN=$3; shift 3; mkdir -p "$TDIR" ;;
  ""|-h|--help) sed -n 2,13p "$0"; exit 2 ;;
esac
CMDS=(); [ -n "$SW_PAGER_OFF" ] && [ $MODE = run ] && CMDS+=("$SW_PAGER_OFF")
CMDS+=("$@")
STAMP=$(date +%Y%m%d-%H%M%S)-$$
WDIR="$SW_WIN_WORK\\tftp\\$STAMP"
{ [ -z "$SW_VIA" ] || [ -z "$TDIR" ]; } && WDIR=$TDIR       # files land here directly, or no receiver at all
job=$(SW_MODE=$MODE SW_TDIR="$WDIR" SW_TN=$TN python3 -c '
import json, os, sys
e = os.environ
j = {"host": e["SW_HOST"], "user": e["SW_USER"], "cmds": sys.argv[1:], "mode": e["SW_MODE"], "timeout": int(e["SW_TIMEOUT"]),
     "work": e["SW_WIN_WORK"], "myip": e.get("SW_MYIP", ""), "tftp": None}
if e["SW_TDIR"]: j["tftp"] = {"port": int(e["SW_TFTP_PORT"]), "dir": e["SW_TDIR"], "expect": int(e["SW_TN"])}
print(json.dumps(j))' "${CMDS[@]+"${CMDS[@]}"}")

names=("$SW_SECRET"); [ $MODE = first-login ] && names+=("$SW_NEW_SECRET")
secrets "${names[@]}" >/dev/null || exit 1          # no password: say so before anything is started
pwlines() { secrets "${names[@]}"; [ $MODE = first-login ] || echo; }   # line 1 password, line 2 new password

if [ -z "$SW_VIA" ]; then                           # ---- ssh from this machine ---------------------------------------
  pwlines | python3 "$S/sw_cli.py" "$job"
  exit ${PIPESTATUS[1]}
fi

# ---- through a Windows machine: password, script and job travel on stdin of one PowerShell process ------------------
BOOT='$l = [Console]::In.ReadToEnd() -split "`n"
$u = [Text.Encoding]::UTF8
try { $s = [scriptblock]::Create($u.GetString([Convert]::FromBase64String($l[2].Trim())))
} catch { "sw: win/sw.ps1 does not parse: $_"; exit 4 }
$j = $u.GetString([Convert]::FromBase64String($l[3].Trim())) | ConvertFrom-Json
try { & $s -Pw $l[0].TrimEnd("`r") -NewPw $l[1].TrimEnd("`r") -Job $j } catch { "sw: error on the Windows machine: $_"; exit 4 }
exit $LASTEXITCODE'
T=$(( SW_TIMEOUT * (${#CMDS[@]} + 2) + 60 ))
set +e
out=$({ pwlines; base64 < "$S/win/sw.ps1" | tr -d '\n'; echo; printf '%s' "$job" | base64 | tr -d '\n'; echo; } \
      | "$SW_VIA" pipe "$T" "$BOOT" 2>&1)
rc=$?
set -e
printf '%s\n' "$out"
[ -n "$out" ] || { echo "sw: no output from the Windows machine (exit $rc)" >&2; exit 4; }
if [ -n "$TDIR" ]; then
  while read -r _ _ name _; do
    "$SW_VIA" get "$WDIR\\$name" "$TDIR/$name" </dev/null && echo "saved $TDIR/$name"
  done < <(printf '%s\n' "$out" | grep '^TFTP received ')
  "$SW_VIA" pipe 30 "Remove-Item -Recurse -Force '$WDIR' -ErrorAction SilentlyContinue" </dev/null >/dev/null 2>&1 || true
fi
grep -q '^sw: ' <<<"$out" && exit 3
exit $rc
