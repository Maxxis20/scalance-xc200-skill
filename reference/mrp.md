# MRP on the XC-200

Media Redundancy Protocol (IEC 62439-2): devices in a ring, one **manager** (MRM) sends test frames around the
ring and keeps one of its two ring ports **blocked** while the ring is closed; when a test frame does not come
back (a cable or device lost), it forwards on both ports, and the ring heals within the recovery time (200 ms
profile by default). The others are **clients** (MRC): they forward between their two ring ports.

Seen and proven on an XC216, firmware V04.04.00, as MRP manager of a ring with two PLCnext controllers (one the
Profinet controller of the switch, the other its Profinet device), November 2026.

## Roles

`ring-redundancy mode { ard | mrpauto | mrpclient | hrpclient | hrpmanager }` in `configure terminal` (**seen** in
`?`, never run). Values seen in the output of `show ring-redundancy` and the startup information:

| Seen as | Meaning |
|---|---|
| `MRP Auto-Manager` | MRP manager that steps back to client when another manager with better priority is in the ring (`mrpauto`). The switch's own default role (**seen** on this switch before a Profinet controller took it over: Auto-Manager, domain `default-mrpdomain`, ring ports P1 and P2) |
| `MRP Manager` | fixed manager (`mode mrpmanager` in the running configuration). Set by a Profinet controller here (**proven**) |
| `MRP Client` | `mrpclient` (not seen as a state) |
| automatic redundancy detection (`ard`) | the startup information of a start showed "mode: automatic redundancy detection, role: client, ports: P0.2, P0.1(s)" (**seen**; the role changes when the ring is detected) |

- **A factory-reset XC-200 is already a ring participant on P1/P2** (Auto-Manager or ARD, ring ports
  `fastethernet 0/1` and `0/2`). Two cables into P1 and P2 from the same network therefore do not make a loop, one
  of them is blocked; and a ring of other MRP devices through P1/P2 gets this switch as a manager unless told
  otherwise. Keep that in mind when a "spare" switch is plugged into a ring, and when P1/P2 are used as ordinary
  ports.
- The ring ports are the default ring ports of the GSDML too ("Port 1 - RJ45", "Port 2 - RJ45", subslots 0x8001,
  0x8002), so a Profinet tool picks the same ports by default.

## Set by a Profinet controller (the normal case in a Profinet network)

When the switch is a Profinet device of a controller and the tool's "Media redundancy: not by STEP7"-like option
is off (the XC216's GSDML parameter), the controller writes MRP at every connection start:

- record **0x8052 PDInterfaceMrpDataAdjust** to the interface submodule (slot 0, subslot 0x8000): role, domain UUID,
  domain name, manager priority and timing, one block per MRP instance;
- record **0x8053 PDPortMrpDataAdjust** to each ring port submodule: the port's domain UUID.

The switch then shows `Ring Redundancy Mode: MRP Manager`, the controller's domain name (e.g.
`plcnext-engineer-mrp-default`, lower case on the switch), and the logbook "Ring ID 1 is configured to ring MRP
Manager." (**proven**). Running configuration afterwards: `ringid 1`, `ring ports fastethernet 0/1 fastethernet
0/2`, `mode mrpmanager`, `domain-name <name>` (**proven**).

Do not change MRP on the CLI while a controller sets it: the next connection start writes it back, and between the
two the ring may run with two managers or none.

### The duplicate domain UUID fault (found and fixed)

The XC216 V4.4 GSDML entry (DAP "SCALANCE XC216 V4.4") declares `MaxMRP_Instances="4"`. PLCnext Engineer 2026.6
therefore writes four MRP instances in record 0x8052 (MRP 1 = manager, MRP 2..4 = role Off) and offers no way to
leave 2..4 out. By default all four carry the **same domain UUID** (`ffffffff-ffff-ffff-ffff-ffffffffffff`).

Seen (**proven**): the switch takes instance 1 (it becomes manager, the ring works) but refuses the record with a
**parameterization fault**: its F lamp on, `show events faults status` -> `ID 72 "PROFINET fault - please use STEP
7 for diagnostics"`; on the controller a channel diagnosis of subslot 0x8000, ChannelErrorType 0x0010
(parameterization fault), ExtChannelErrorType 0x8001, ExtChannelAddValue **0x8052 / 0x0060** = record 0x8052, byte
offset 96 = the domain UUID of the second instance. `Red. Operational Mode` stayed "MRP Auto-Manager".

Fix (**proven**): give MRP 2..4 their own domain UUIDs (e.g. `11111111-...`, `22222222-...`, `33333333-...`, names
`mrp-unused-2..4`), roles left Off, MRP 1 unchanged. After the next connection start: `Fault Status : no fault`,
the F lamp off (seen at the switch), the controller's diagnosis gone, `Red. Operational Mode` **"MRP Manager"**, ring still closed. So the cause was
the second instance's domain UUID equal to the first, not the number of instances.

Other Profinet details (**proven** from the controller side): the XC216 does not serve record 0x8050
PDInterfaceMrpDataReal (read error 0xDE80B900); record 0x8054 PDPortMrpDataReal holds only the domain UUID;
record **0x802A PDPortDataReal** of each ring port answers with the LLDP neighbour and the port state:
`0x0501` forwarding/up, `0x0201` blocking/up. Both links up and one ring port blocking = ring closed. The switch's
GSDML has no "ring open" diagnosis of its own; its update time minimum is 128 ms (`MinDeviceInterval=4096`).

## Ring state on the CLI

`show ring-redundancy` (**proven**, closed ring and during cable tests):

| Field | Meaning |
|---|---|
| `Ring Redundancy Mode` | the configured role (`MRP Manager`) |
| `Ringports` | `Fa0/1 Fa0/2` |
| `Red. Operational Mode` | the role in effect (`MRP Manager`, or `MRP Auto-Manager`) |
| `RM Status` | **`passive` = ring closed** (the manager blocks one port); **`active` = ring open** (it forwards on both) |
| `No. of Changes to RM Active State` | how often the ring has opened since the counters were cleared (each pulled cable +1) |
| `Max. Delay of RM Test Packets [ms]` | the longest round trip of the test frames: 4 ms with the ring closed, 8-11 ms after reconnects, up to 39 ms seen over hours with two controllers in the ring |

The logbook has a line per change: "Ring ID 1. MRP ring manager entered active state." (open) / "... falls back to
passive state." (closed). Counters: `clear ring-redundancy manager counters` (exec, **untested**).

Cable tests with a running process (**proven**): pulling either cable between the manager and a controller or
between the two controllers turned RM Status active and the counter +1, the controllers kept exchanging data (no
Profinet connection lost within the 384 ms watchdog); plugging back turned it passive.

## Setting MRP by hand (**untested**: none of this was run)

Only for a switch that no Profinet controller manages ("not by STEP7" / MRP setting outside the controller), and
with the ring open or with the user's go:

```
configure terminal
ring-redundancy mode mrpauto               ! or mrpclient; the fixed manager role is "mode mrpmanager" below
ring-redundancy configuration
 ringid 1
 ring ports fastethernet 0/1 fastethernet 0/2
 mode mrpmanager
 domain-name <name>
 exit
end
```

The `ringid` / `ring ports` / `mode` / `domain-name` lines are the form the switch prints in `show running-config
redundancy`; `ringid <1-4>` and `ring ports` are listed in `?` of `CLI(config-red)#`; the commands inside
`ringid` mode, a domain UUID setting, manager priority and `no ring-redundancy` are not known in detail. Check
afterwards: `show ring-redundancy`, then pull a cable and see RM Status change. `ring-redundancy restore-default`
(listed) presumably returns to the factory role.
