#!/usr/bin/env bash
# sw-get.sh [-o <dir>] <filetype> ...  - fetch files off the switch over TFTP into <dir> (default: the current folder)
#
# For each file type one `save filetype <type> tftp ipv4 <this machine> port <SW_TFTP_PORT> file <name>` runs, in
# one CLI session, while a TFTP receiver listens on the machine the switch can reach: this one (SW_VIA empty) or
# the Windows machine behind SW_VIA, from where the files are copied here. File names: <type> plus an extension
# (Config.cfg, RunningCLI.cli, StartupInfo.txt, LogFile.txt, GSDML.zip, ...). The list of types and what each one
# allows: `sw.sh "show loadsave files"`. Saving does not change the switch.
#
# The receiver needs UDP <SW_TFTP_PORT> from the switch to reach it: a firewall in between (on a VM host, too) must
# let it through. A save of Config takes 30-60 s; SW_SAVE_TIMEOUT (default 120) is the wait per command.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd); . "$S/config.sh"
OUT=.; [ "${1:-}" = -o ] && { OUT=$2; shift 2; }
[ $# -gt 0 ] || { sed -n 2,11p "$0"; exit 2; }
ext() { case "$1" in Config|ConfigPack) echo cfg;; RunningCLI|Script) echo cli;; StartupInfo|LogFile|LoginWelcomeMessage) echo txt;;
                     GSDML|EDS|MIB|Debug|DebugExt) echo zip;; *) echo bin;; esac; }
cmds=(); for t; do cmds+=("save filetype $t tftp ipv4 @IP@ port @PORT@ file $t.$(ext "$t")"); done
mkdir -p "$OUT"
SW_TIMEOUT=${SW_SAVE_TIMEOUT:-120} "$S/sw.sh" --tftp "$OUT" $# "${cmds[@]}"
