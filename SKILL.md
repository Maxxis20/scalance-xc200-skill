---
name: scalance-xc200
description: Drive Siemens SCALANCE XC-200 managed switches (XC206, XC208, XC216, XC224 and relatives, firmware V4.x) over their SSH command line without hand typing - run show commands for versions, ports, MRP ring state, Profinet, power, faults and the logbook, fetch files off the switch (configuration, running CLI, GSDML, log file) over TFTP, back the switch up and compare two backups. Use whenever the task is to inspect, back up, diagnose or (carefully) configure a SCALANCE XC-200, to check an MRP ring that such a switch manages, or when the user mentions SCALANCE, XC216, XC-200, Siemens managed switch, MRP manager on a Siemens switch, or the switch's CLI.
---

# SCALANCE XC-200, scripted

The XC-200 has a Cisco-like CLI over SSH (`CLI#` prompt, `configure terminal`, `show ...`). This skill runs CLI
sessions from a script: one SSH session per call, a command is sent only when the prompt is back, every
`--More--` page is answered, and the password never appears in the output. Files come off the switch with its own
`save filetype ... tftp` command into a small TFTP receiver that the scripts start for the time of the session.

Undocumented behaviour of one firmware (V04.04.00 on an XC216). Each fact in `reference/` is marked **proven**
(done and checked), **seen** (observed once, not exercised) or **untested** (documented recipe, never run). On
another model or firmware, prove each step again.

## Setup

Settings come from the environment or from `~/.scalance/config` (`NAME=value` lines; all of them described in
`scripts/config.sh`):

| Setting | Meaning |
|---|---|
| `SW_HOST` | the switch's address (required) |
| `SW_USER` | CLI user, default `admin` |
| `SW_SECRET` | name of the environment variable that holds the password (default `SCALANCE_PASSWORD`) |
| `SW_SECRET_RUN` | your secret manager's runner, put in front of the one process that reads the password, e.g. `op run --` |
| `SW_VIA` | empty: SSH from this machine. Else a script that reaches a Windows machine on the switch's network (below) |

**Password.** Set by the user in their own shell or secret manager, never in the chat. It travels on stdin only:
never printed (every occurrence in the output becomes `***`), never in a command line, never on disk. Never ask
for the value, never print it.

**Transports.**
- **Direct** (`SW_VIA` empty): `ssh` and `python3` on this machine; `scripts/sw_cli.py` drives the session in a
  pseudo terminal. For a switch this machine can route to.
- **Through a Windows machine** (`SW_VIA=<path of a vm.sh-like script>`): for a switch on a network only a Windows
  machine reaches, e.g. the Profinet network of an engineering PC. The script must offer `pipe <s> '<powershell>'`
  (run PowerShell with this command's stdin passed through) and `get <win path> <local>`; the `scripts/vm.sh` of
  the plcnext-engineer skill does (local Git Bash, or a VM through the Proxmox guest agent). On Windows only the
  built-in PowerShell 5.1 and OpenSSH client (`ssh.exe`) are used, no Python: `scripts/win/sw.ps1` goes over on
  stdin with each call, nothing is installed. Work folder there: `SW_WIN_WORK` (default `C:\agentwork\scalance`).

First call: `scripts/sw.sh "show versions"`. It shows the model and firmware, and proves address, user and password.

A factory-new switch (or one after `restart factory`) asks on the first login "Default admin user to be changed
(y/n)?" and forces a new password. `sw.sh` stops there (exit 3) instead of answering. With the user's go:
`SW_SECRET=<var with the current password, "admin" when new> sw.sh first-login`, the new password in the variable
named by `SW_NEW_SECRET` (default `SCALANCE_NEW_PASSWORD`); afterwards point `SW_SECRET` at the new one.
(**untested** on a real switch: the answers were proven against a simulated CLI only; the exact prompt texts after
the y/n question are not known.)

## Commands

```bash
scripts/sw.sh "show ring-redundancy" "show pnio"      # any commands, one session, about 8 s through a VM
scripts/sw-get.sh -o <dir> Config RunningCLI GSDML    # files off the switch over TFTP (about 75 s for these three)
scripts/sw-backup.sh backup [-o <parent dir>] [name]  # RunningCLI + Config + StartupInfo + show versions + info.txt
scripts/sw-backup.sh check <backup> [<backup2>]       # files intact; with two: diff of the running configuration
```

- **Pager.** The XC-200 CLI has no command to switch paging off (no `terminal length`; the exec and configure
  command lists have nothing for it, **seen** on V04.04). The scripts answer every `--More--` with a space and
  strip it from the output, so long output (`show logbook`, `?`) comes in whole (**proven**). `SW_PAGER_OFF` sends
  a command at the start of each session, for a firmware that has one.
- `?` as a command lists every command of the current mode (exec: ~210 lines, `configure terminal` then `?`:
  ~300). Entering a mode and leaving it with `end` changes nothing, but the logbook says "Device configuration
  changed" (**seen**).
- Exit codes: 0 done; 3 the session stopped (no prompt within `SW_TIMEOUT` s after a command, or the first-login
  question); 4 the Windows side failed. Error lines start with `sw:`.
- `reference/cli.md`: the commands and what their output means. `reference/mrp.md`: ring redundancy.
  `reference/findings.md`: everything else learned.

**Files (TFTP).** `sw-get.sh` and `sw-backup.sh` start a receiver on UDP `SW_TFTP_PORT` (default 50069) of the
machine the switch talks to, put its address into the `save` command (found from the route to the switch, or
`SW_MYIP`) and copy the files here. That port must be open from the switch: on Windows the script opens it in the
Windows firewall for the session (rule `scalance-tftp-<port>`, removed afterwards); **a firewall outside the
machine (a hypervisor's VM firewall, a router) needs a rule by the user** (UDP to that port, from the switch).
A `save` also stores the server address, port and file name in the switch's load/save settings (**seen**): it
changes those three settings, nothing else.

## Safety

A switch like this often carries a running Profinet network or an MRP ring with controllers on it. A wrong
command can cut every controller off at once.

- **Read freely**: `show ...`, `?`, `ping`, `whoami`, and `save filetype ...` (file out, see above).
- **Ask first, every time**, naming the command: anything under `configure terminal`, `load ...` (a loaded Config
  or Firmware takes effect), `restart ...` (`restart factory` erases everything), `clear ...`, `write
  startup-config`, `change password`, `fault report ack`, `das ...`, `cabletest`.
- The XC-200 runs **Auto-Save** by default (`show device information`: "Config Save Mode : Auto-Save"): a
  configuration change is stored by itself, there is no "just try, restart to undo".
- **Never change the ring ports, the MRP role or domain, VLANs, the IP address, `dcp server` or `pnio` on a switch
  that a Profinet controller manages**: the controller writes MRP role, ring ports, name and address at every
  connection start, and a hand change fights it or breaks the ring (`reference/mrp.md`).
- Before any change: `sw-backup.sh backup`. After it: a second backup and `check` the two.
- Never write `user-account`/`username ... password` or SNMP keys into a command that ends up in a log or a chat;
  a password on the command line is seen in `show history` too (**untested** whether the CLI masks it there).
