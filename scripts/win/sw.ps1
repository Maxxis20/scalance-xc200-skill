# sw.ps1 - SCALANCE CLI session from a Windows machine (PowerShell 5.1, OpenSSH client ssh.exe; no Python needed).
# Not run by hand: scripts/sw.sh sends this script, the password and a job on stdin through `vm.sh pipe`.
#
#   $Pw     admin password (never printed: every occurrence in the output is replaced by ***)
#   $NewPw  new password, only for the first-login mode
#   $Job    host, user, cmds (list), mode ('run' or 'first-login'), timeout (s per command), work (folder),
#           tftp (optional: port, dir, expect = number of files to wait for), myip (optional)
# In the commands, @IP@ becomes this machine's address towards the switch (or myip) and @PORT@ the TFTP port.
#
# The session is driven like expect: a command is sent only at a prompt (CLI#, CLI(config)#, ...), --More-- is
# answered with a space, the first-login questions are answered only in first-login mode. With tftp, a one-socket
# TFTP receiver (write requests only, 512-byte blocks) runs in the same loop, behind a temporary firewall rule that
# admits UDP to that port from the switch only; the rule is removed at the end.
param([string]$Pw, [string]$NewPw, $Job)
$ErrorActionPreference = 'Stop'
$work = $Job.work; New-Item -ItemType Directory -Force "$work\run" | Out-Null
$ask = "$work\run\sw-askpass.cmd"
Set-Content $ask '@powershell -NoProfile -Command "[Console]::Out.Write($env:SW_PW)"' -Encoding ASCII

$st = @{ log = New-Object Text.StringBuilder; pend = ''; eof = $false; files = @(); xfer = @{}; lastData = [datetime]::MinValue; lastOut = Get-Date }
$udp = $null; $rule = $null
if ($Job.tftp) {
  $dir = $Job.tftp.dir; New-Item -ItemType Directory -Force $dir | Out-Null
  $rule = "scalance-tftp-$($Job.tftp.port)"
  Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol UDP -LocalPort $Job.tftp.port `
    -RemoteAddress $Job.host -Action Allow | Out-Null
  $udp = New-Object Net.Sockets.UdpClient ([int]$Job.tftp.port)
}

function Ack($ep, [int]$blk) { $b = [byte[]](0, 4, [byte]($blk -shr 8), [byte]($blk -band 255)); [void]$udp.Send($b, 4, $ep) }
function PollUdp {
  if (-not $udp) { return }
  $until = (Get-Date).AddMilliseconds(500)   # while a transfer runs, stay here and answer each block at once
  do { while ($udp.Available -gt 0) {
    $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any), 0
    $p = $udp.Receive([ref]$ep); $key = $ep.ToString()
    $op = $p[0] * 256 + $p[1]
    if ($op -eq 2) {                                  # write request: file name, 0, mode, 0 [, options]: options ignored
      $name = [Text.Encoding]::ASCII.GetString($p, 2, $p.Length - 2).Split([char]0)[0]
      $name = [IO.Path]::GetFileName($name); if (-not $name) { $name = 'upload.bin' }
      $st.xfer[$key] = @{ name = $name; data = New-Object IO.MemoryStream; next = 1 }
      Ack $ep 0
    } elseif ($op -eq 3 -and $st.xfer.ContainsKey($key)) {
      $x = $st.xfer[$key]; $blk = $p[2] * 256 + $p[3]
      if ($blk -eq $x.next) { $x.data.Write($p, 4, $p.Length - 4); $x.next = ($x.next + 1) % 65536 }
      Ack $ep $blk; $st.lastData = Get-Date
      if ($p.Length - 4 -lt 512) {
        $f = Join-Path $Job.tftp.dir $x.name; [IO.File]::WriteAllBytes($f, $x.data.ToArray())
        $st.files += "TFTP received $($x.name) $($x.data.Length) bytes from $($ep.Address)"
        $st.xfer.Remove($key)
      }
    } elseif ($op -eq 5) {
      $st.files += "TFTP error from $($ep.Address): " + [Text.Encoding]::ASCII.GetString($p, 4, $p.Length - 4).Trim([char]0)
    }
  }
  if ($st.xfer.Count -eq 0) { break }
  } while ($udp.Client.Poll(20000, [Net.Sockets.SelectMode]::SelectRead) -or (Get-Date) -lt $until)
}

$psi = New-Object Diagnostics.ProcessStartInfo 'ssh.exe'
$psi.Arguments = '-tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o LogLevel=ERROR -o ConnectTimeout=8 ' +
  "-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 $($Job.user)@$($Job.host)"
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
$psi.EnvironmentVariables['SSH_ASKPASS'] = $ask; $psi.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'
$psi.EnvironmentVariables['DISPLAY'] = 'x'; $psi.EnvironmentVariables['SW_PW'] = $Pw
$p = [Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$buf = New-Object char[] 8192
$st.task = $p.StandardOutput.ReadAsync($buf, 0, $buf.Length)

function Pump([int]$ms) {   # read what has arrived within ms; false at end of output
  if ($st.task.Wait($ms)) {
    $n = $st.task.Result
    if ($n -le 0) { $st.eof = $true; return }
    $s = New-Object string ($buf, 0, $n)
    [void]$st.log.Append($s); $st.pend += $s; $st.lastOut = Get-Date
    $st.task = $p.StandardOutput.ReadAsync($buf, 0, $buf.Length)
  }
}
function Send([string]$s) { $p.StandardInput.Write($s); $p.StandardInput.Flush(); $st.pend = '' }

$myip = if ($Job.myip) { $Job.myip } else { try { @(Find-NetRoute -RemoteIPAddress $Job.host)[0].IPAddress } catch { '' } }
$queue = New-Object Collections.Queue
foreach ($c in @($Job.cmds)) { $c = [string]$c; if ($Job.tftp) { $c = $c.Replace('@PORT@', [string]$Job.tftp.port) }; $queue.Enqueue($c.Replace('@IP@', $myip)) }
$prompt = 'CLI(\([^)]*\))?#\s*$'
$tmo = [int]$Job.timeout; $deadline = (Get-Date).AddSeconds($tmo + 20); $sentExit = $false; $status = 'ok'; $last = '(login)'
while (-not $st.eof) {
  Pump 50; PollUdp
  $t = $st.pend
  if ($t -match '--More--') { Send ' '; $deadline = (Get-Date).AddSeconds($tmo); continue }
  if ($t -match '(?i)\(y/n\)\s*\??\s*$') {
    if ($Job.mode -eq 'first-login') { Send "y`r"; continue }
    $status = 'first-login: the switch asks "' + ($t.Trim() -split "`n")[-1].Trim() + '"; run: sw.sh first-login'; break
  }
  if ($Job.mode -eq 'first-login' -and $t -match '(?i)password[^\n]*:\s*$') {
    if ($t -match '(?i)(old|current)[^\n]*password[^\n]*:\s*$') { Send "$Pw`r" } else { Send "$NewPw`r" }
    continue
  }
  if ($t -match $prompt) {
    if ($queue.Count -gt 0) { $last = $queue.Dequeue(); Send "$last`r"; $deadline = (Get-Date).AddSeconds($tmo) }
    elseif (-not $sentExit) {
      if ($udp -and $st.xfer.Count -gt 0 -and (Get-Date) -lt $deadline) { continue }   # a transfer still running
      Send "exit`r"; $sentExit = $true; $deadline = (Get-Date).AddSeconds(10)
    }
    continue
  }
  if ($last -ne '(login)' -and $st.xfer.Count -eq 0 -and ((Get-Date) - $st.lastOut).TotalSeconds -gt 5 -and
      ((Get-Date) - $st.lastData).TotalSeconds -gt 5) {
    # a message that came after the prompt (e.g. "File was successfully saved") leaves no prompt at the end: Enter
    $p.StandardInput.Write("`r"); $p.StandardInput.Flush(); $st.lastOut = Get-Date
  }
  if ((Get-Date) -gt $deadline -and ((Get-Date) - $st.lastData).TotalSeconds -gt 10) {   # a running transfer extends it
    $status = "TIMEOUT: no prompt within $tmo s after: $last"; break
  }
}
if ($udp) {   # files of the last command may still be on their way
  $end = (Get-Date).AddSeconds([int]$Job.timeout)
  while ((Get-Date) -lt $end -and ($st.files.Count -lt [int]$Job.tftp.expect -or $st.xfer.Count -gt 0)) { PollUdp; Start-Sleep -Milliseconds 50 }
  $udp.Close(); Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
}
if (-not $p.HasExited) { if (-not $p.WaitForExit(3000)) { $p.Kill() } }
Pump 200

$o = $st.log.ToString() + $errTask.Result
$o = $o -replace '\x1b\[[0-9;?]*[A-Za-z]', '' -replace '\[27m', '' -replace '--More--', '' -replace '[\b]', ''
$o = (($o -split "`n") | ForEach-Object { $l = $_.TrimEnd("`r"); $l.Substring($l.LastIndexOf("`r") + 1) }) -join "`n"   # a CR overwrites the line
$o = $o -replace "(?m)[ \t]+$", '' -replace "\n{3,}", "`n`n"
if ($Pw) { $o = $o.Replace($Pw, '***') }; if ($NewPw) { $o = $o.Replace($NewPw, '***') }
$o
foreach ($f in $st.files) { $f }
foreach ($k in $st.xfer.Keys) { $x = $st.xfer[$k]; "TFTP unfinished: $($x.name) from $k, $($x.data.Length) bytes, next block $($x.next)" }
if ($udp -and $st.files.Count -lt [int]$Job.tftp.expect) { "TFTP: $($st.files.Count) of $($Job.tftp.expect) files received" }
if ($status -ne 'ok') { "sw: $status"; exit 3 }
