# CLI reference: commands used and seen

SCALANCE XC216, firmware V04.04.00. Every command below was run through `scripts/sw.sh` unless marked. The output
examples are shortened; addresses and names are placeholders.

## Session

- Login over SSH with user and password; banner "SIMATIC NET - Industrial Ethernet / Command Line Interface
  SCALANCE XC200", then the prompt `CLI#` (**proven**). Modes: `CLI(config)#` after `configure terminal`,
  `CLI(config-red)#` (`ring-redundancy configuration`), `CLI(config-loadsave)#` (`loadsave`), `CLI(config-events)#`
  (`events`); `exit` one level up, `end` back to `CLI#` (**proven**: entered and left, nothing set).
- Output pages with `--More--` (a key continues); no command to turn paging off (**seen**: not in `?` of exec
  or configure mode). The scripts answer it.
- A command that runs in the background (a `save`) prints its result after the prompt: "File was successfully
  saved" comes after `CLI#`, and the next prompt only after Enter. The scripts press Enter after 5 s of silence
  (**proven**).
- `?` lists every command of the mode with its syntax (**proven**). `help [command]` exists (not used).
- Console session timeout: `show cli-console-timeout` -> "Enabled, 300 seconds" (**seen**).
- `show users`: lines (vty 2..9) with user, peer address, auth (**seen**: two stale SSH sessions of an earlier
  client were still listed hours later; `clear line vty <n>` would close them, **untested**).

## Identity and state

| Command | Shows |
|---|---|
| `show versions` | hardware (name, revision, order id), firmware / bootloader / running firmware with dates (**proven**) |
| `show device information` | MAC, serial number, up time, system name, restart counter, **Config Save Mode** (Auto-Save), Config Change (Saved) (**proven**) |
| `show hardware` | line card table (`BASEXC216 UP`) (**seen**) |
| `show usage [cpu\|ram]` | CPU and RAM usage in % with thresholds (**seen**: CPU 100 %, status OK, while answering the CLI) |
| `show environmental temperature` | chassis temperature and thresholds (**seen**: 34 °C) |
| `show power-line-state` | `L1 is connected.` / `L2 is not connected.` (**proven**). (Not `show power-line`: no such command.) |
| `show startup-information` | numbered events of the last start: cold start and firmware, startup configuration source (internal / PLUG), power lines, ports, ring redundancy mode, role and ports at start, faults after start (**proven**) |
| `show time` | (not run) the switch had no time source: log times start at 01/01/2000 |
| `whoami` | `admin` (**seen**) |

## Ports, addresses, neighbours

| Command | Shows |
|---|---|
| `show interfaces status` | per port (`Fa0/1`..`Fa0/16`): connected / not connected, duplex, speed, negotiation (**proven**) |
| `show interfaces fastethernet 0/1` | up/down, "Port is not blocked", port MAC, MTU, speed, rx/tx counters (**seen**) |
| `show interfaces counters` | octets, unicast, discards, errors per port and `vlan1`, in and out (**seen**) |
| `show ip interface` | `vlan1` up, "configured as tia-interface", IP, mask, broadcast, collision detection (**proven**) |
| `show ip gateway` | `Default Gateway: <address>` (**seen**) |
| `show ip arp` | ARP table (**seen**) |
| `show lldp neighbors brief` | neighbour system name, device id (a Profinet station name or a chassis MAC) and local port (**proven**) |
| `ping <address> count <n>` | replies; a Windows host with its firewall up does not answer (**seen**) |

Port names: `fastethernet 0/<n>` in commands, `Fa0/<n>` in output, `P0.<n>` in startup information and the
logbook, "Port <n> - RJ45" in the GSDML and Profinet tools: the same port.

## Ring redundancy and Profinet

| Command | Shows |
|---|---|
| `show ring-redundancy` | Ring ID, Domain Name, Ring Redundancy Mode, Ringports, Red. Operational Mode, **RM Status**, No. of Changes to RM Active State, Max. Delay of RM Test Packets, then MRP interconnection, HRP observer, standby (**proven**) |
| `show ring-redundancy manager counters` | only the two counter lines (**proven**) |
| `show running-config redundancy` | the ring setting as CLI lines (`ringid 1`, `ring ports ...`, `mode mrpmanager`, `domain-name ...`) (**proven**) |
| `show pnio` | PROFINET Mode (and for next boot), **AR Status** Online/Offline, Name of Station (**proven**) |
| `show dcp server` | `dcp-read-write` / `dcp-read-only` / `dcp-read-setup` (**proven**) |

Meaning of the ring fields: `reference/mrp.md`.

## Faults, events, logbook

| Command | Shows |
|---|---|
| `show events faults status` | active faults with ID and text, or `Fault Status : no fault` (**proven**; with a fault: `ID 72 "PROFINET fault - please use STEP 7 for diagnostics"`, **seen**) |
| `show fault counter` | `No. of Signaled Faults: <n>` since start (**seen**) |
| `show events faults config` | link flap count/time/reaction, monitored interfaces and power lines (**proven**) |
| `show events config` | per event type (cold/warm start, link change, authentication failure, power change, RM state change, fault state change, configuration change, ...) where it goes: e-mail, trap, log table, syslog, faults (**proven**) |
| `show logbook [info\|warning\|critical]` | numbered entries, newest first: `[n:Info] Restart #6, System Up Time hh:mm:ss, System Time ...` and a text line (**proven**; ~1000 lines after a few hours: paged, the scripts read it whole) |

Logbook lines seen (the same texts are in the LogFile, `save filetype LogFile`, as CSV
`Restart;SystemUpTime;SystemTime;Severity;Message`): "Ring ID 1. MRP ring manager entered active state." / "... falls
back to passive state.", "Ring ID 1 is configured to ring MRP Manager.", "PROFINET connection established." /
"terminated. Reason: 15 got release.ind" / "Reason: 11 alarm.ind(err)", "New Fault state: ..." / "Fault state gone:
...", "Device configuration changed.", "SSH: User admin has logged in from <address>.", "TFTP: Saved file type
Config.", "TFTP: File download type RunningCLI failed. Cannot connect to given IP address.", "Default password
changed. Device transitioned to operational state. All setup functions are disabled."

## Files: load and save

```
save filetype <filetype> {tftp | sftp} {ipv4 <addr> | fqdn-name <FQDN>} [port <port>] file <filename> [user <u>] [password <p>]
load {tftp | sftp} {ipv4 <addr> | fqdn-name <FQDN>} [port <port>] file <filename> filetype <filetype> [user <u>] [password <p>]
```

- `save` over TFTP: the switch is the TFTP client and **writes** the file to a server (write request, octet,
  512-byte blocks) (**proven** with the receiver of `scripts/win/sw.ps1` / `sw_cli.py`). It prints "File save
  operation started. Please wait", then "File was successfully saved", or "% TFTP connection using current IP
  address and port number could not be established" when nothing answers (**proven**; the logbook then says
  "Cannot connect to given IP address").
- A `save` stores server address, port and file name as the defaults of that file type (`show loadsave tftp`:
  "TFTP server address: <addr>, port: <port>"; running configuration: `tftp filename filetype Config name <name>`
  under `loadsave`) (**seen**). Auto-Save keeps them.
- `load` (**untested**, not run): a loaded Config, ConfigPack, Firmware, Users or Script takes effect on the switch.
  Ask first.
- SFTP variants and `loadsave` mode (`tftp server ...`, `tftp filename ...`, `tftp save filetype <t>`, `password
  filetype <t> pw <p>` for encrypted files): listed, **untested**.

`show loadsave files` (**proven**):

| File type | Storage | Load | Save | PW | What it is (from what came out) |
|---|---|---|---|---|---|
| Config | FLASH | yes | yes | no | full configuration as SNMP objects (`Name=`, `OID=`, `Type=`, `Value=`, `Index=`, `Rowstatus=` blocks), text with a header and checksum; ~400 kB, 30-60 s to save (**proven**) |
| ConfigPack | RAM | yes | yes | no | not fetched |
| RunningCLI | RAM | no | yes | no | running configuration as CLI commands, ~26 kB; starts "# Important hint: This file is not intended to be uploaded without modifications!"; passwords as `"[PASSWORD]"` (**proven**) |
| StartupInfo | FLASH | no | yes | no | the text of `show startup-information`, ~1.4 kB (**proven**) |
| LogFile | RAM | no | yes | no | the logbook as CSV, ~31 kB (**proven**) |
| GSDML | MAP | no | yes | no | zip: the GSDML xml of the XC-200 family and the bitmaps, ~190 kB (**proven**) |
| Debug, DebugExt, EDS, MIB | RAM/MAP | no | yes | no | not fetched |
| Firmware | RAM | yes | yes | no | not fetched |
| Users | FLASH | yes | yes | no | not fetched (holds the local users; treat as secret) |
| HTTPSCert, SSHPrivateKeyECDSA/RSA, SINEMAConfig | FLASH | yes | no | yes | load only |
| Script, LoginWelcomeMessage, WBMFav | FLASH | yes | no | no | load only |

## Configuration commands seen (none run except where noted)

- `dcp server {read-only | read-write | read-setup}`: whether a Profinet tool may set name and address by DCP.
  `read-setup` (what the switch showed after its first password change) lets DCP set name and address only while
  the switch is in its setup state, i.e. no more; `read-write` was set once so that a Profinet controller could
  name and address it (**proven**, earlier session).
- `write startup-config` (exec): stores the running configuration (**proven** once, earlier session); with
  Auto-Save on it is not needed (**seen**: "Config Change: Saved" without it).
- `pnio {off | on}`, `restart [factory | pnio | ethernetip | ie]`, `change password <passwd>`, `username {user |
  admin} password <passwd>`, `user-account <name> password <pw> role <role>`, `cli-console-timeout <60-600>`,
  `system name <name>`, `ring-redundancy ...` (`reference/mrp.md`), `interface fastethernet 0/<n>` then
  `shutdown` / `no shutdown` (the usual form, **untested**), `vlan <id>`, `ip gateway <addr>`: listed in `?`,
  **untested**.
