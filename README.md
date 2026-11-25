# scalance-xc200: a Claude skill for Siemens SCALANCE XC-200 switches

Lets an AI coding agent (Claude Code) work with a SCALANCE XC-200 managed switch (XC206, XC208, XC216, XC224 and
relatives, firmware V4.x) over its SSH command line: run `show` commands, read the state of an MRP ring the switch
manages, fetch files off the switch, back it up and compare two backups.

The XC-200 has a Cisco-like CLI (`CLI#` prompt). The skill runs each CLI session from a script: one SSH session
per call, a command is sent only when the prompt is back, every `--More--` page is answered (the CLI has no
command to switch paging off), and the password never appears in the output. Files come off the switch with its
own `save filetype ... tftp` command into a small TFTP receiver that the scripts start for the time of the session.

What is in the skill:

- `SKILL.md`: what the agent reads first, including the safety rules (read freely, ask before any change).
- `reference/cli.md`: the commands used and what their output means. `reference/mrp.md`: MRP roles, ring state on
  the CLI, how a Profinet controller sets MRP on the switch, and a fault with a duplicate MRP domain UUID and its
  fix. `reference/findings.md`: everything else learned. Each fact is marked proven, seen or untested.
- `scripts/sw.sh`: run CLI commands. `scripts/sw-get.sh`: fetch files (Config, RunningCLI, GSDML, LogFile, ...).
  `scripts/sw-backup.sh`: back up and compare. `scripts/sw_cli.py` (direct SSH from Linux or macOS) and
  `scripts/win/sw.ps1` (SSH from a Windows machine) drive the session.

## What you need

- The switch's address and a CLI user with its password.
- Either a Linux or macOS machine with `ssh` and Python 3 that routes to the switch, or a Windows machine on the
  switch's network (Windows PowerShell 5.1 and the built-in OpenSSH client, nothing to install) plus a script that
  reaches it, such as `scripts/vm.sh` of the
  [plcnext-engineer skill](https://github.com/Maxxis20/plcnext-engineer-skill).
- For file transfers: UDP to the receiver's port (default 50069) must be allowed from the switch to that machine.

## Install

```bash
git clone https://github.com/Maxxis20/scalance-xc200-skill ~/.claude/skills/scalance-xc200
```

Settings come from the environment or from `~/.scalance/config` (`NAME=value` lines), all of them described in
`scripts/config.sh`. A minimal one:

```bash
SW_HOST=192.0.2.20                 # the switch
SW_SECRET=SCALANCE_PASSWORD        # NAME of the environment variable that holds the password
# SW_SECRET_RUN="op run --"        # optional: your secret manager's runner, in front of the one process that reads it
# SW_VIA=/path/to/vm.sh            # optional: reach the switch through a Windows machine
```

The password is never stored by the skill and never typed into the chat: set it in your own shell or secret
manager. Then:

```bash
cd ~/.claude/skills/scalance-xc200
scripts/sw.sh "show versions"                          # model, firmware; proves address, user and password
scripts/sw.sh "show ring-redundancy" "show pnio"       # several commands in one session
scripts/sw-backup.sh backup                            # RunningCLI, Config, StartupInfo, show versions
```

## Limits, plainly

- Worked out on one switch: an XC216 with firmware V04.04.00, as MRP manager of a ring with two Profinet
  controllers. Other models and firmware are likely close but unproven.
- On the real switch the sessions ran through the Windows transport. The direct transport (`sw_cli.py`) and the
  first-login answers for a factory-new switch were tested against a simulated CLI only.
- Configuration is documented, not scripted: the helpers read, save files and back up. `sw.sh` sends whatever
  commands it is given, so the agent is told to ask before every configuration command. The XC-200 saves changes
  by itself (Auto-Save), so there is no "restart to undo".
- A `save` over TFTP stores the server address, port and file name in the switch's load/save settings; backups and
  file fetches change nothing else. (`sw.sh first-login` sets a new password, on request only.)
- A switch in a Profinet network carries every controller on it. Check what the agent proposes before it goes
  anywhere near a running plant.

## Not affiliated

An independent project, not made, endorsed or supported by Siemens. SIMATIC and SCALANCE are trademarks of
Siemens AG. No Siemens software or files are included.

MIT licence.
