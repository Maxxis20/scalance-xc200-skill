# Findings

SCALANCE XC216 (6GK5 216-0BA00-2AC2, hardware revision 2), firmware V04.04.00, November 2026. Each fact is marked
**proven** (done and checked), **seen** (observed once, not exercised) or **untested**.

## Access

- SSH with password authentication on port 22; keys were not tried. The host key changes after a factory reset, so
  the scripts keep none (`StrictHostKeyChecking=no`, no known_hosts) (**proven**).
- The CLI authenticates at the SSH level (the `password:` prompt of ssh), not with a login prompt of its own
  (**proven**). On Windows the password reaches `ssh.exe` through `SSH_ASKPASS` (a one-line `.cmd` that prints an
  environment variable of that one process) (**proven**).
- First login of a factory-new switch: "Default admin user to be changed (y/n)?", then a new password is forced
  (**seen** by the user on this switch; not scripted against it). The logbook then says "Default password changed.
  Device transitioned to operational state. All setup functions are disabled." (**seen**). After that the DCP
  server read `dcp-read-setup`: names and addresses could be set over DCP only during setup, and a Profinet tool's
  "set name" failed with "SetNotPossibleByLocalReasons" until `dcp server read-write` (**proven**, earlier session).
- `ssh.exe -tt` with stdin redirected from a file works, but it cannot react to `--More--` or questions, and it
  stays open when the file ends without `exit` (**proven**: a `?` session hung until the guest timeout). The
  scripts therefore drive the session from a loop that reads the output (PowerShell `Process` with redirected
  streams on Windows, a pty in Python elsewhere) (**proven**).
- One CLI session through a Proxmox guest agent to a Windows VM takes about 8 s for a short command (**proven**).

## Output

- Paging: `--More--` after about a screen; no command turns it off (**seen**). Answered with a space; the switch
  then overwrites the `--More--` with spaces and a carriage return, which the scripts remove (**proven**).
- After a background command (`save`) the result line comes after the prompt, and no new prompt follows until
  Enter. After a Config save the switch stays silent for 30-40 s more before it answers Enter (**proven**).
- Leaving `configure terminal` logs "Device configuration changed." even when nothing was set (**seen**; the
  running configuration before and after was the same, apart from the TFTP file names set by `save`).

## Files

- `save filetype` over TFTP to a receiver on the engineering machine: Config, RunningCLI, GSDML, StartupInfo,
  LogFile (**proven**). The switch writes 512-byte blocks and accepts a server that answers from the port it
  listens on (**proven**). A receiver that polls every 50 ms makes a 400 kB Config take minutes: answer each
  block at once (**proven**).
- A `save` sets the load/save defaults of that file type: server address, port, file name (**seen**:
  `show loadsave tftp` and the `loadsave` block of the running configuration changed to the last save's values).
- **No admin password in RunningCLI or Config** (**proven** by comparison with the real password and its MD5,
  SHA-1, SHA-256 and SHA-512 in every file of a backup): RunningCLI writes `user-account "admin" password
  "[PASSWORD]"` and the SNMPv3 template users' keys as `[PASSWORD]`; Config has no local user table (that is the
  separate file type Users). Config does carry the localized SNMPv3 keys of the factory template users
  (`templateMD5`, `templateSHA`: `usmUser...KeyChange` values) and the SNMPv1/v2c community names (`public`,
  `private`). Treat a backup as internal, not as secret; never fetch the Users file into a shared place.
- Config is a text file with a header ("SCALANCE Configuration File", MLFB, device type, IP and MAC, firmware
  versions, up time, "END OF HEADER - Checksum:<n>"), and it changes with every save (up time). Compare RunningCLI,
  not Config (**proven**).

## Device

- **Auto-Save** is on: "Config Save Mode : Auto-Save", "Config Change : Saved" (**seen**). Changes persist without
  `write startup-config`.
- No time source: the system time starts at 01/01/2000 00:00 on each start, so logbook times are up time (**seen**).
- `show usage` said CPU 100 % (status OK) while the CLI was answering (**seen**; meaning unclear).
- SNMP agent on, v1/v2c read-only (`snmp v1-v2 readonly`), communities `public` / `private`; HTTP and HTTPS servers
  in the running configuration (**seen**). Hardening is a separate decision for the user.
- The startup information lists the ring role at start (ARD, client) even on a switch that a Profinet controller
  makes manager a moment later: the controller's setting is applied after the start (**seen**).
- `show power-line-state`: L1 connected, L2 not connected. L1/L2 are not monitored by default, so a missing
  redundant supply raises no fault (**seen**).
- The GSDML lists the whole XC-200 family (XC206 .. XC224) in one file (**seen**).

## Windows side (transport through a Windows machine)

- Needs nothing installed: PowerShell 5.1 and the built-in OpenSSH client (**proven**). The whole driver
  (`win/sw.ps1`) is sent on stdin with each call, together with the password and the job.
- A PowerShell parse error in a script run with `-EncodedCommand` and redirected stdin comes out as CLIXML on
  stderr, which a caller that filters CLIXML loses. The bootstrap catches it and prints `sw: ...` (**proven**).
- TFTP into a Windows VM needs the port open twice: in the Windows firewall (the script adds and removes a rule)
  and in the hypervisor's VM firewall when that has `policy_in: DROP` (a rule by the user: UDP to the receiver's
  port, from the switch) (**proven**: without the second rule the switch reported "could not be established").
- A Windows host with its firewall up does not answer the switch's `ping`. That says nothing about TFTP (**seen**).
