# sw_cli.py - SCALANCE CLI session from this machine (Linux / macOS): ssh in a pty, driven like expect.
# Not run by hand: scripts/sw.sh starts it. Same job and behaviour as win/sw.ps1 (keep the two in step):
#   stdin   line 1 the password, line 2 the new password (first-login mode only; may be empty)
#   argv[1] the job as JSON: host, user, cmds, mode ('run' | 'first-login'), timeout, tftp {port, dir, expect} or null,
#           myip (optional). In the commands @IP@ becomes this machine's address towards the switch, @PORT@ the TFTP port.
# A command is sent only at a prompt, --More-- is answered with a space, the first-login questions are answered only
# in first-login mode, and with tftp a one-socket TFTP receiver (write requests, 512-byte blocks) runs in the loop.
# Output: the session text with every occurrence of either password replaced by ***.
import json, os, pty, re, select, socket, struct, sys, time

job = json.loads(sys.argv[1])
lines = sys.stdin.read().split("\n")
pw, npw = lines[0].rstrip("\r"), (lines[1].rstrip("\r") if len(lines) > 1 else "")
tmo = int(job.get("timeout", 30))
ssh = os.environ.get("SW_SSH", "ssh")      # SW_SSH: another program instead of ssh (used to test this driver)

udp, files, xfer, last_data = None, [], {}, 0.0
if job.get("tftp"):
    os.makedirs(job["tftp"]["dir"], exist_ok=True)
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); udp.bind(("0.0.0.0", int(job["tftp"]["port"])))

def poll_udp():
    global last_data
    while udp and select.select([udp], [], [], 0)[0]:
        p, ep = udp.recvfrom(4 + 65536)
        op = struct.unpack("!H", p[:2])[0]
        if op == 2:
            name = os.path.basename(p[2:].split(b"\0")[0].decode(errors="replace")) or "upload.bin"
            xfer[ep] = {"name": name, "data": bytearray(), "next": 1}
            udp.sendto(struct.pack("!HH", 4, 0), ep)
        elif op == 3 and ep in xfer:
            x, blk = xfer[ep], struct.unpack("!H", p[2:4])[0]
            if blk == x["next"]:
                x["data"] += p[4:]; x["next"] = (x["next"] + 1) % 65536
            udp.sendto(struct.pack("!HH", 4, blk), ep)
            last_data = time.time()
            if len(p) - 4 < 512:
                with open(os.path.join(job["tftp"]["dir"], x["name"]), "wb") as f: f.write(x["data"])
                files.append("TFTP received %s %d bytes from %s" % (x["name"], len(x["data"]), ep[0])); del xfer[ep]
        elif op == 5:
            files.append("TFTP error from %s: %s" % (ep[0], p[4:].split(b"\0")[0].decode(errors="replace")))

pid, fd = pty.fork()
if pid == 0:
    os.execvp(ssh, [ssh, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR",
                    "-o", "ConnectTimeout=8", "-o", "PubkeyAuthentication=no", "-o", "NumberOfPasswordPrompts=1",
                    "-o", "PreferredAuthentications=password,keyboard-interactive", "%s@%s" % (job["user"], job["host"])])

log, pend, eof, last_out = [], "", False, time.time()
def pump(t):
    global pend, eof, last_out
    if fd in select.select([fd] + ([udp] if udp else []), [], [], t)[0]:   # wakes up for TFTP packets too
        try: s = os.read(fd, 8192).decode(errors="replace")
        except OSError: s = ""
        if not s: eof = True; return
        log.append(s); pend += s; last_out = time.time()
def send(s):
    global pend
    os.write(fd, s.encode()); pend = ""

myip = job.get("myip") or ""
if not myip:
    try:
        u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.connect((job["host"], 9)); myip = u.getsockname()[0]; u.close()
    except OSError: pass
port = str(job["tftp"]["port"]) if job.get("tftp") else ""
queue = [c.replace("@IP@", myip).replace("@PORT@", port) for c in job["cmds"]]; prompt = re.compile(r"CLI(\([^)]*\))?#\s*$")
deadline, sent_exit, status, last, logged_in = time.time() + tmo + 20, False, "ok", "(login)", False
while not eof:
    pump(0.05); poll_udp(); t = pend
    if not logged_in and re.search(r"(?i)password:\s*$", t):          # the ssh login itself
        send(pw + "\r"); logged_in = True; continue
    if "--More--" in t:
        send(" "); deadline = time.time() + tmo; continue
    if re.search(r"(?i)\(y/n\)\s*\??\s*$", t):
        if job["mode"] == "first-login": send("y\r"); continue
        status = 'first-login: the switch asks "%s"; run: sw.sh first-login' % t.strip().splitlines()[-1].strip(); break
    if job["mode"] == "first-login" and logged_in and re.search(r"(?i)password[^\n]*:\s*$", t):
        send((pw if re.search(r"(?i)(old|current)[^\n]*password[^\n]*:\s*$", t) else npw) + "\r"); continue
    if prompt.search(t):
        logged_in = True
        if queue:
            last = queue.pop(0); send(last + "\r"); deadline = time.time() + tmo
        elif not sent_exit:
            if udp and xfer and time.time() < deadline: continue
            send("exit\r"); sent_exit = True; deadline = time.time() + 10
        continue
    if last != "(login)" and not xfer and time.time() - last_out > 5 and time.time() - last_data > 5:
        # a message that came after the prompt (e.g. "File was successfully saved") leaves no prompt at the end: Enter
        os.write(fd, b"\r"); last_out = time.time()
    if time.time() > deadline and time.time() - last_data > 10:      # a running transfer extends it
        status = "TIMEOUT: no prompt within %d s after: %s" % (tmo, last); break
if udp:
    end = time.time() + tmo
    while time.time() < end and (len([f for f in files if "received" in f]) < int(job["tftp"].get("expect", 0)) or xfer):
        poll_udp(); time.sleep(0.05)
    udp.close()
try: os.kill(pid, 9)
except OSError: pass

o = "".join(log)
o = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", o).replace("[27m", "").replace("--More--", "").replace("\b", "")
o = "\n".join(l.rstrip("\r").split("\r")[-1] for l in o.split("\n"))     # a CR overwrites the line
o = re.sub(r"(?m)[ \t]+$", "", o); o = re.sub(r"\n{3,}", "\n\n", o)
for s in (pw, npw):
    if s: o = o.replace(s, "***")
sys.stdout.write(o + "\n")
for f in files: print(f)
for ep, x in xfer.items(): print("TFTP unfinished: %s from %s:%d, %d bytes, next block %d" % (x["name"], ep[0], ep[1], len(x["data"]), x["next"]))
if udp and len([f for f in files if "received" in f]) < int(job["tftp"].get("expect", 0)):
    print("TFTP: %d of %s files received" % (len([f for f in files if "received" in f]), job["tftp"]["expect"]))
if status != "ok": print("sw: " + status); sys.exit(3)
