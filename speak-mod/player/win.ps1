# win.ps1 - Windows player for the speak mod. One detached, hidden Windows PowerShell 5.1 (STA) process
# per reply, started by the hooks module (see hooks/protocol.ts):
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File win.ps1 <base>.json
# The job file { base, chunks, voice, speed, model, gate, session, mediaPause } is read once and deleted.
# FISH_API_KEY comes from the environment (the module sets it when it starts this process).
#
# Protocol with the module, files next to <base>:
#   <base>.state  written here a few times a second: {phase, chunk, n, fraction, paused, message}
#                 phase: held | fetching | playing | done | stopped | error | expired
#   <base>.cmd    written by the module, one word, consumed here: stop pause resume back fwd replay
#
# What happens: the text's clips are fetched from Fish Audio two ahead of the one playing (Fish
# generates at ~4x realtime, so the first short clip plays after ~3 s). In gated mode the reply is
# held silently until its session is the focused Herdr pane (dropped after 15 min). Players take
# turns across sessions through a lock, so voices never overlap. Media apps that were playing are
# paused before the first clip and resumed by the last player to finish. After the reply the clips
# are kept 20 min for a replay ("replay", or "back" for the last 5 s), then everything is deleted.
# Log: %TEMP%\claude-speak-mod.log
# Stdio mode (-Stdio, no job file): the job arrives as the first line of standard input, commands as
# the lines after it, and every state goes out as one JSON line on standard output. This is how a
# remote machine (a dev box, over SSH) plays through this machine's speakers: see player/remote.sh.
# End of input counts as "stop".
param([string]$JobFile, [switch]$Stdio)
$ErrorActionPreference = 'Continue'
# Runs under Windows PowerShell 5.1 (file mode: it has the WinRT media-session API for pausing media
# apps) or PowerShell 7 (stdio mode over SSH: 5.1 reads only the first line of the stdin the Windows
# SSH server hands it, 7 streams; media pausing is off there anyway, an SSH login session cannot see
# the desktop's media sessions).
$script:winrt = $PSVersionTable.PSEdition -ne 'Core'
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
if ($script:winrt) { Add-Type -AssemblyName System.Runtime.WindowsRuntime }
Add-Type -AssemblyName System.Net.Http

if ($Stdio) {
  [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
  $script:stdin = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
  $job = $script:stdin.ReadLine() | ConvertFrom-Json
  $base = Join-Path $env:TEMP "claude-speak-remote-$PID"
  # The lines after the job are read by a thread of their own with plain blocking reads into a
  # queue: asynchronous reads never complete on the stdin the Windows SSH server hands a command,
  # while synchronous ones work everywhere. End of input is queued as "stop".
  $script:cmdQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
  $script:readerPs = [PowerShell]::Create()
  $null = $script:readerPs.AddScript({
    param($reader, $queue)
    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line) { $queue.Enqueue('stop'); break }
      $queue.Enqueue($line.Trim())
    }
  }).AddArgument($script:stdin).AddArgument($script:cmdQueue)
  $null = $script:readerPs.BeginInvoke()
} else {
  if (-not $JobFile) { Write-Error 'usage: win.ps1 <job.json> | win.ps1 -Stdio'; exit 2 }
  $job = Get-Content -Raw $JobFile -Encoding UTF8 | ConvertFrom-Json
  Remove-Item $JobFile -ErrorAction SilentlyContinue
  $base = [string]$job.base
}
$chunks = @($job.chunks); $n = $chunks.Count
$sessionId = [string]$job.session
$gateFocus = [bool]$job.gate
$mediaPause = [bool]$job.mediaPause
$stateFile = "$base.state"; $cmdFile = "$base.cmd"; $readyFlag = "$base.ready"
$log = Join-Path $env:TEMP 'claude-speak-mod.log'
if ((Get-Item $log -ErrorAction SilentlyContinue).Length -gt 200KB) { Remove-Item $log -ErrorAction SilentlyContinue }
function Log($m) { Add-Content -Path $log -Value ("{0:HH:mm:ss.fff} [{1}] {2}" -f (Get-Date), $PID, $m) }
function Pump { [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background) }

# --- state and commands -------------------------------------------------------------------------
$script:phase = 'fetching'; $script:chunk = 0; $script:fraction = 0.0; $script:paused = $false; $script:message = ''
$script:lastWrite = [DateTime]::MinValue
function Write-State([switch]$Force) {
  if (-not $Force -and ((Get-Date) - $script:lastWrite).TotalMilliseconds -lt 200) { return }
  $script:lastWrite = Get-Date
  $s = @{ phase = $script:phase; chunk = $script:chunk; n = $n; fraction = [math]::Round($script:fraction, 4); paused = $script:paused; message = $script:message } | ConvertTo-Json -Compress
  if ($Stdio) { try { [Console]::Out.WriteLine($s); [Console]::Out.Flush() } catch {}; return }
  try {
    [IO.File]::WriteAllText("$stateFile.tmp", $s, [Text.UTF8Encoding]::new($false))
    Move-Item "$stateFile.tmp" $stateFile -Force
  } catch {}
}
function Set-Phase([string]$p, [string]$msg = '') { $script:phase = $p; $script:message = $msg; Write-State -Force; Log "phase $p $msg" }
function Read-Cmd {
  if ($Stdio) {   # whatever the reader thread queued; nothing yet is ''
    $line = ''
    if ($script:cmdQueue.TryDequeue([ref]$line)) { return $line }
    return ''
  }
  if (-not (Test-Path $cmdFile)) { return '' }
  try { $c = (Get-Content $cmdFile -Raw -ErrorAction Stop).Trim(); Remove-Item $cmdFile -ErrorAction SilentlyContinue; return $c } catch { return '' }
}
$script:stopRequested = $false
$script:seek = 0            # ms asked for by back/fwd, consumed by Play-File
$script:replay = $false     # a replay asked for after the reply was read
$script:replayBack = 0      # ms before the end to restart from ("back" after the end)
# Takes one command from the module, if any, and applies it. Called from every wait loop.
function Handle-Cmd {
  $c = Read-Cmd
  switch ($c) {
    'stop'   { $script:stopRequested = $true }
    'pause'  { $script:paused = $true; Write-State -Force }
    'resume' { $script:paused = $false; Write-State -Force }
    'back'   { if ($script:phase -eq 'done') { $script:replayBack = 5000; $script:replay = $true } else { $script:seek -= 5000 } }
    'fwd'    { if ($script:phase -ne 'done') { $script:seek += 5000 } }
    'replay' { if ($script:phase -eq 'done') { $script:replay = $true } }
  }
}
function Test-StopRequested { Handle-Cmd; return $script:stopRequested }

# --- turn taking ---------------------------------------------------------------------------------
# Start-Playing blocks until this player may speak: its session must be the focused Herdr pane (gated
# mode; held replies expire after 15 min) and the claude-speak.playing lock must be free (one voice at
# a time across sessions; a lock left by a dead process is taken over). Returns $false when stopped
# or expired. "<base>.ready" (holding this PID) marks a player past the focus gate, so Resume-Media
# knows whether someone is about to speak next.
$playLock = Join-Path $env:TEMP 'claude-speak.playing'
function Test-Focused {
  if (-not $sessionId -or -not $env:HERDR_ENV) { return $true }   # not inside Herdr
  # With the inherited caller context set, `pane current` reports the calling pane; without it, the
  # pane focused in the UI, which is what we want.
  foreach ($k in 'HERDR_PANE_ID', 'HERDR_TAB_ID', 'HERDR_WORKSPACE_ID') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
  try {
    $pane = (herdr pane current 2>$null | Out-String | ConvertFrom-Json).result.pane
    if ($pane.agent_session.value -eq $sessionId) { return $true }
    # A session Herdr does not list can never become focused: treated as always on screen.
    if ($null -eq $script:knownSession) {
      $agents = @((herdr agent list 2>$null | Out-String | ConvertFrom-Json).result.agents)
      $script:knownSession = [bool]($agents | Where-Object { $_.agent_session.value -eq $sessionId })
      if (-not $script:knownSession) { Log 'session unknown to Herdr: not gating on focus' }
    }
    return -not $script:knownSession
  } catch { return $true }   # herdr unavailable: better to speak than to stay silent
}
function Enter-Playing {
  $waiting = $false
  while ($true) {
    try { New-Item $playLock -ItemType File -Value "$PID" -ErrorAction Stop | Out-Null; return $true } catch {}
    $owner = Get-Process -Id ([int](Get-Content $playLock -ErrorAction SilentlyContinue | Select-Object -First 1)) -ErrorAction SilentlyContinue
    if (-not $owner -or $owner.ProcessName -notin 'powershell', 'pwsh') { Remove-Item $playLock -Force -ErrorAction SilentlyContinue; continue }
    if (-not $waiting) { $waiting = $true; Log "waiting for player $($owner.Id) to finish" }
    if (Test-StopRequested) { return $false }
    Start-Sleep -Milliseconds 200
  }
}
function Exit-Playing {
  if ((Get-Content $playLock -ErrorAction SilentlyContinue | Select-Object -First 1) -eq "$PID") { Remove-Item $playLock -Force -ErrorAction SilentlyContinue }
}
function Start-Playing {
  $expiry = (Get-Date).AddMinutes(15); $held = $false
  while ($true) {
    while ($gateFocus -and -not (Test-Focused)) {
      if (-not $held) { $held = $true; Set-Phase 'held' }
      if (Test-StopRequested) { return $false }
      if ((Get-Date) -gt $expiry) { Set-Phase 'expired'; return $false }
      Start-Sleep -Milliseconds 1000
    }
    if ($held) { $held = $false; Set-Phase 'fetching' }
    Set-Content $readyFlag "$PID"
    if (-not (Enter-Playing)) { return $false }
    if (-not $gateFocus -or (Test-Focused)) { return $true }
    Exit-Playing; Remove-Item $readyFlag -ErrorAction SilentlyContinue   # focus moved away while queued
  }
}
function Stop-Playing { Exit-Playing; Remove-Item $readyFlag -ErrorAction SilentlyContinue }

# --- media ---------------------------------------------------------------------------------------
# Windows' media-session API (the volume flyout's play/pause): every session that is Playing is
# paused before the first clip and its app id kept in claude-speak.media.json; the last live player
# resumes them, so the podcast does not blip back on between two replies.
$mediaFile = Join-Path $env:TEMP 'claude-speak.media.json'
function Get-MediaSessions {
  $null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
  if (-not $script:asTask) {
    $script:asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  }
  $mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
  return @($mgr.GetSessions())
}
function Await($op, $type) { $t = $script:asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
function Suspend-Media {
  if (-not $mediaPause -or -not $script:winrt) { return }
  try {
    $ids = @(); if (Test-Path $mediaFile) { $ids = @(Get-Content $mediaFile -Raw | ConvertFrom-Json | ForEach-Object { $_ }) }
    foreach ($s in Get-MediaSessions) {
      if ("$($s.GetPlaybackInfo().PlaybackStatus)" -ne 'Playing') { continue }
      Await ($s.TryPauseAsync()) ([bool]) | Out-Null
      $ids += $s.SourceAppUserModelId; Log "paused media: $($s.SourceAppUserModelId)"
    }
    if ($ids) { ConvertTo-Json @($ids | Select-Object -Unique) -Compress | Set-Content $mediaFile }
  } catch { Log "media pause failed: $($_.Exception.Message)" }
}
# True if another live player is past its focus gate (a .ready file holding a live PID): it speaks next.
function Test-OtherPlayers {
  foreach ($f in Get-ChildItem (Join-Path $env:TEMP 'claude-speak-*.ready') -ErrorAction SilentlyContinue) {
    $id = 0; try { $id = [int](Get-Content $f.FullName -Raw -ErrorAction Stop).Trim() } catch { continue }
    if ($id -eq $PID) { continue }
    $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -in 'powershell', 'pwsh') { return $true }
  }
  return $false
}
function Resume-Media {
  if (-not $script:winrt -or -not (Test-Path $mediaFile)) { return }
  if (Test-OtherPlayers) { Log 'media left paused for the next player'; return }
  try {
    $ids = @(Get-Content $mediaFile -Raw | ConvertFrom-Json | ForEach-Object { $_ })
    foreach ($s in Get-MediaSessions) {
      if ($ids -contains $s.SourceAppUserModelId -and "$($s.GetPlaybackInfo().PlaybackStatus)" -eq 'Paused') {
        Await ($s.TryPlayAsync()) ([bool]) | Out-Null; Log "resumed media: $($s.SourceAppUserModelId)"
      }
    }
  } catch { Log "media resume failed: $($_.Exception.Message)" }
  Remove-Item $mediaFile -ErrorAction SilentlyContinue
}

# --- playback ------------------------------------------------------------------------------------
$script:carry = 0; $script:lastLen = 0
$script:lens = @{}   # clip lengths in ms by index, for cross-clip seeking and "back" after the end
# Plays one clip from $startAt ms. Returns its length in ms when it played to the end, -1 when
# stopped, -2 when a "back 5 s" went past the clip's start, or -3 when a "forward 5 s" (or
# $startAt itself) went past its end and this is not the last clip. For -2/-3 $script:carry holds the
# ms to land at, counted from the end of the previous clip (negative) or the start of the next one.
# $from/$to are the clip's share of the whole text, for the progress fraction.
function Play-File([string]$file, [double]$from = 0, [double]$to = 1, [double]$startAt = 0) {
  $p = New-Object System.Windows.Media.MediaPlayer
  $p.Open([Uri]$file)
  $d = (Get-Date).AddSeconds(5)
  while (-not $p.NaturalDuration.HasTimeSpan -and (Get-Date) -lt $d) { Pump; Start-Sleep -Milliseconds 50 }
  $len = 0
  if ($p.NaturalDuration.HasTimeSpan) {
    $len = $p.NaturalDuration.TimeSpan.TotalMilliseconds; $script:lastLen = $len
    if ($startAt -ge $len - 100 -and $to -lt 1) { $script:carry = $startAt - $len; $p.Close(); return -3 }
    if ($startAt -gt 0) { $p.Position = [TimeSpan]::FromMilliseconds([math]::Min($startAt, $len - 100)) }
    if (-not $script:paused) { $p.Play() }
    $deadline = (Get-Date).AddMilliseconds($len - $startAt + 2000)
    $wasPaused = $script:paused
    while ($p.Position.TotalMilliseconds -lt $len - 50 -and (Get-Date) -lt $deadline) {
      Pump
      if (Test-StopRequested) { $len = -1; break }
      if ($script:paused -ne $wasPaused) {
        $wasPaused = $script:paused
        if ($wasPaused) { $p.Pause() } else { $p.Play() }
      }
      if ($script:seek) {
        $new = $p.Position.TotalMilliseconds + $script:seek; $script:seek = 0
        if ($new -lt 0 -and $from -gt 0) { $script:carry = $new; $len = -2; break }
        if ($new -ge $len -and $to -lt 1) { $script:carry = $new - $len; $len = -3; break }
        $p.Position = [TimeSpan]::FromMilliseconds([math]::Max(0, [math]::Min($new, $len - 50)))
        $deadline = (Get-Date).AddMilliseconds($len - $p.Position.TotalMilliseconds + 2000)
      }
      if ($wasPaused) { $deadline = $deadline.AddMilliseconds(50) }
      $script:fraction = $from + ($to - $from) * $p.Position.TotalMilliseconds / $len
      Write-State
      Start-Sleep -Milliseconds 50
    }
  }
  $p.Close()
  return $len
}

# The engine's key: SPEAK_API_KEY from the module, else the engine's own variable (process, then the
# persisted User-scope value, so a fresh `setx` works without restarting).
$engine = [string]$job.engine; if (-not $engine) { $engine = 'fish' }
$keyVar = if ($engine -eq 'elevenlabs') { 'ELEVENLABS_API_KEY' } else { 'FISH_API_KEY' }
$key = $env:SPEAK_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable($keyVar, 'Process') }
if (-not $key) { $key = [Environment]::GetEnvironmentVariable($keyVar, 'User') }
if (-not $key) { Set-Phase 'error' "$keyVar is not set on $env:COMPUTERNAME"; if (-not $Stdio) { Start-Sleep 5; Remove-Item $stateFile -ErrorAction SilentlyContinue }; exit 1 }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(120)
if ($engine -eq 'elevenlabs') {
  $client.DefaultRequestHeaders.Add('xi-api-key', $key)
} else {
  $client.DefaultRequestHeaders.Add('Authorization', "Bearer $key")
  $client.DefaultRequestHeaders.Add('model', [string]$job.model)
}
$total = ($chunks | ForEach-Object Length | Measure-Object -Sum).Sum
# One request for clip $i, per engine. Fish: POST /v1/tts with the model as a header. ElevenLabs:
# POST /v1/text-to-speech/<voice> with the model in the body; its speed range is 0.7..1.2.
function Fetch($i) {
  if ($engine -eq 'elevenlabs') {
    $speed = [math]::Max(0.7, [math]::Min(1.2, [double]$job.speed))
    $body = @{ text = $chunks[$i]; model_id = [string]$job.model; voice_settings = @{ speed = $speed } }
    $url = "https://api.elevenlabs.io/v1/text-to-speech/$([string]$job.voice)?output_format=mp3_44100_128"
  } else {
    $body = @{ text = $chunks[$i]; format = 'mp3'; latency = 'balanced'; prosody = @{ speed = [double]$job.speed } }
    if ($job.voice) { $body.reference_id = [string]$job.voice }
    $url = 'https://api.fish.audio/v1/tts'
  }
  $content = New-Object System.Net.Http.StringContent(($body | ConvertTo-Json -Compress -Depth 3), [Text.Encoding]::UTF8, 'application/json')
  return $client.PostAsync($url, $content)
}
# One pass over the clips from $first (at $firstAt ms), fetching any not on disk (a replay fetches
# nothing). Returns 'done' when everything played, 'stopped' otherwise (the phase says why).
function Play-Round([int]$first = 0, [double]$firstAt = 0) {
  $done = 0; for ($k = 0; $k -lt $first; $k++) { $done += $chunks[$k].Length }
  $tasks = @{}; $startAt = $firstAt; $started = $false; $status = 'done'; $failed = 0
  for ($i = $first; $i -lt $n; $i++) {
    $script:chunk = $i
    foreach ($j in @($i, ($i + 1), ($i + 2))) {
      if ($j -lt $n -and -not $tasks.ContainsKey($j) -and -not (Test-Path "$base-$j.mp3")) { $tasks[$j] = Fetch $j; Log "fetch $j started" }
    }
    if (-not $started) {
      # Wait for our turn (focused session + lock) while clip 0 is fetched, then pause the media; the
      # ~1 s of setup hides behind the ~3 s fetch, and a beat of silence is fine.
      if (-not (Start-Playing)) { $status = 'stopped'; break }
      $started = $true; Suspend-Media
    }
    $file = "$base-$i.mp3"
    if ($tasks.ContainsKey($i)) {
      Set-Phase 'fetching'
      $task = $tasks[$i]; $tasks.Remove($i)
      while (-not $task.IsCompleted) { if (Test-StopRequested) { break }; Start-Sleep -Milliseconds 50 }
      if ($script:stopRequested) { $status = 'stopped'; break }
      try {
        $resp = $task.Result
        if (-not $resp.IsSuccessStatusCode) {
          $detail = ''; try { $d = ($resp.Content.ReadAsStringAsync().Result -replace '\s+', ' '); $detail = $d.Substring(0, [math]::Min(200, $d.Length)) } catch {}
          Log "chunk $i HTTP $([int]$resp.StatusCode) $detail"; $failed++; continue
        }
        [IO.File]::WriteAllBytes($file, $resp.Content.ReadAsByteArrayAsync().Result)
      } catch { Log "chunk $i failed: $($_.Exception.Message)"; $failed++; continue }
    }
    Set-Phase 'playing'
    $len = Play-File $file ($done / $total) (($done + $chunks[$i].Length) / $total) $startAt
    $startAt = 0
    if ($len -eq -2) {   # back past this clip's start: replay the previous clip from near its end
      $script:lens[$i] = $script:lastLen
      $i -= 2; $done -= $chunks[$i + 1].Length; $startAt = [math]::Max(0, [double]$script:lens[$i + 1] + $script:carry)
      Log "back to chunk $($i + 1) at $([int]$startAt) ms"; continue
    }
    if ($len -eq -3) {   # forward past this clip's end: carry the rest into the next clip
      $script:lens[$i] = $script:lastLen; $done += $chunks[$i].Length; $startAt = $script:carry
      Log "forward to chunk $($i + 1) at $([int]$startAt) ms"; continue
    }
    if ($len -lt 0) { Log "stopped at chunk $i"; $status = 'stopped'; break }
    $script:lens[$i] = $len; $done += $chunks[$i].Length
    Log "played $i ($([int]$len) ms)"
  }
  if ($started) { Resume-Media }
  Stop-Playing
  if ($failed -eq $n) { Set-Phase 'error' "$engine request failed (see claude-speak-mod.log)"; return 'stopped' }
  return $status
}
# After a full read, keeps the clips 20 min for a replay: "replay" starts over, "back" starts 5 s
# before the end. Returns $true on a replay, $false on stop or after the window.
function Wait-Replay {
  $script:replay = $false; $script:replayBack = 0; $script:paused = $false
  $expiry = (Get-Date).AddMinutes(20)
  while ($true) {
    Pump
    if (Test-StopRequested) { return $false }
    if ($script:replay) { return $true }
    if ((Get-Date) -gt $expiry) { Set-Phase 'expired'; return $false }
    Start-Sleep -Milliseconds 100
  }
}

Log "start, $n chunks, gate=$gateFocus, session=$sessionId"
Write-State -Force
$first = 0; $firstAt = 0
while ((Play-Round $first $firstAt) -eq 'done') {
  Set-Phase 'done'; $script:fraction = 1
  if (-not (Wait-Replay)) { break }
  $first = 0; $firstAt = 0
  if ($script:replayBack) {
    $rem = $script:replayBack; $script:replayBack = 0; $first = $n - 1
    while ($first -gt 0 -and [double]$script:lens[$first] -lt $rem) { $rem -= [double]$script:lens[$first]; $first-- }
    $firstAt = [math]::Max(0, [double]$script:lens[$first] - $rem)
  }
  Log "replay from chunk $first at $([int]$firstAt) ms"
}
if ($script:stopRequested) { Set-Phase 'stopped' }
$client.Dispose()
Remove-Item "$base-*.mp3", $cmdFile, $readyFlag -ErrorAction SilentlyContinue
Log "exit ($($script:phase))"
if ($Stdio) { exit 0 }
Start-Sleep 5   # give the module a moment to read the final phase
Remove-Item $stateFile -ErrorAction SilentlyContinue
