# win.ps1 - Windows player for the speak mod. One detached, hidden Windows PowerShell 5.1 (STA) process
# per reply, started by the hooks module (see hooks/protocol.ts):
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File win.ps1 <base>.json
# The job file { base, chunks, engine, voice, speed, model, gate, session, media, remote } is read
# once and deleted. The engine's key comes from the environment: SPEAK_API_KEY (the module sets it when
# it starts this process), else FISH_API_KEY or ELEVENLABS_API_KEY.
#
# Protocol with the module, files next to <base>:
#   <base>.state  written here a few times a second: {phase, chunk, n, fraction, paused, message}
#                 phase: held | fetching | playing | done | stopped | error | expired
#   <base>.cmd    written by the module, one word, consumed here: stop pause resume back fwd replay
#
# What happens: the text's clips are fetched from the configured engine two ahead of the one playing (Fish
# generates at ~4x realtime, so the first short clip plays after ~3 s). In gated mode the reply is
# held silently until its session is the focused Herdr pane (dropped after 15 min). Players take
# turns across sessions through a lock, so voices never overlap. Before the first clip other audio is
# faded down to a twelfth (media "duck") or faded out and paused ("pause"), and the last player to finish
# brings it back. After the reply the clips
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
# SSH server hands it, 7 streams; other audio is left alone there anyway, an SSH login session cannot
# see the desktop's audio sessions).
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
$media = [string]$job.media; if ($media -notin 'duck', 'pause', 'off') { $media = 'duck' }
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

# --- other audio ---------------------------------------------------------------------------------
# Every other app playing on the default output is faded to $duckLevel of its volume before the first
# clip, through the per-app mixer (Core Audio sessions), and faded back by the last live player. In
# "pause" mode media apps are then paused through Windows' media-session API (the volume flyout's
# play/pause), and resumed before the fade back up. The volumes as they were, by the app's executable
# path, and the paused apps' ids are kept in files, so the podcast does not blip back on between two
# replies and a player that died mid-reply is repaired by the next one. A path, unlike a process id,
# still names the same app after it restarts or the machine reboots, and never an unrelated one.
$duckLevel = 1 / 12
$duckFile = Join-Path $env:TEMP 'claude-speak.duck.json'
$mediaFile = Join-Path $env:TEMP 'claude-speak.media.json'
# Compiles the mixer helper once per player, which takes about a second: while clip 0 is fetched (see
# Play-Round), and before restoring volumes this or another player saved, whatever the mode.
function Use-Mixer {
  if ('SpeakAudio.Mixer' -as [type]) { return }
  try {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
namespace SpeakAudio {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator {
    int NotImpl1();
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
  }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object o);
  }
  [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionManager2 {
    int NotImpl1(); int NotImpl2();
    [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator e);
  }
  [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionEnumerator {
    [PreserveSig] int GetCount(out int n);
    [PreserveSig] int GetSession(int i, out IAudioSessionControl2 s);
  }
  [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl2 {
    [PreserveSig] int GetState(out int state);
    int NotImpl1(); int NotImpl2(); int NotImpl3(); int NotImpl4(); int NotImpl5(); int NotImpl6(); int NotImpl7(); int NotImpl8();
    int NotImpl9(); int NotImpl10();
    [PreserveSig] int GetProcessId(out uint pid);
    [PreserveSig] int IsSystemSoundsSession();
  }
  [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface ISimpleAudioVolume {
    [PreserveSig] int SetMasterVolume(float level, ref Guid context);
    [PreserveSig] int GetMasterVolume(out float level);
  }
  // The per-app mixer of the default output device.
  public static class Mixer {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr handle, int flags, StringBuilder name, ref int size);
    // A process's executable path in lower case; null when it is gone or cannot be read.
    static string PathOf(uint pid) {
      var h = OpenProcess(0x1000, false, pid); if (h == IntPtr.Zero) return null;   // PROCESS_QUERY_LIMITED_INFORMATION
      try { var b = new StringBuilder(1024); int n = b.Capacity; return QueryFullProcessImageName(h, 0, b, ref n) ? b.ToString().ToLowerInvariant() : null; }
      finally { CloseHandle(h); }
    }
    static List<IAudioSessionControl2> Sessions() {
      var list = new List<IAudioSessionControl2>();
      var en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
      IMMDevice dev; if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) return list;   // render, multimedia
      var iid = typeof(IAudioSessionManager2).GUID; object o;
      if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return list;              // CLSCTX_ALL
      IAudioSessionEnumerator e; if (((IAudioSessionManager2)o).GetSessionEnumerator(out e) != 0) return list;
      int n; e.GetCount(out n);
      for (int i = 0; i < n; i++) { IAudioSessionControl2 s; if (e.GetSession(i, out s) == 0) list.Add(s); }
      return list;
    }
    // Volume by executable path of every app sounding now, other than the system sounds and this
    // player's own executable, so no player ducks its own voice or the next player's. An app whose
    // path cannot be read is left alone.
    public static Dictionary<string, float> Playing() {
      var self = PathOf((uint)Process.GetCurrentProcess().Id);
      var d = new Dictionary<string, float>();
      foreach (var s in Sessions()) {
        int state; uint pid; float v;
        if (s.IsSystemSoundsSession() == 0 || s.GetState(out state) != 0 || state != 1) continue;   // 1: active
        if (s.GetProcessId(out pid) != 0 || pid == 0) continue;
        var path = PathOf(pid); if (path == null || path == self) continue;
        if (((ISimpleAudioVolume)s).GetMasterVolume(out v) == 0 && !d.ContainsKey(path)) d[path] = v;
      }
      return d;
    }
    // Sets every session of these apps to its saved volume times factor.
    public static void Scale(Dictionary<string, float> volumes, float factor) {
      var ctx = Guid.Empty;
      foreach (var s in Sessions()) {
        uint pid; if (s.GetProcessId(out pid) != 0) continue;
        var path = PathOf(pid); if (path == null || !volumes.ContainsKey(path)) continue;
        ((ISimpleAudioVolume)s).SetMasterVolume(Math.Max(0f, Math.Min(1f, volumes[path] * factor)), ref ctx);
      }
    }
  }
}
'@
  } catch { Log "mixer unavailable: $($_.Exception.Message)" }
}
# Fades the saved volumes from one share of themselves to another over about a third of a second.
function Fade-Volumes($volumes, [double]$from, [double]$to) {
  for ($k = 1; $k -le 8; $k++) {
    [SpeakAudio.Mixer]::Scale($volumes, [single]($from + ($to - $from) * $k / 8)); Start-Sleep -Milliseconds 40
  }
}
# The volumes saved before the duck, by executable path; empty when nothing is ducked.
function Read-Duck {
  $d = New-Object 'System.Collections.Generic.Dictionary[string,single]'
  if (Test-Path $duckFile) {
    $saved = Get-Content $duckFile -Raw | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { $d[$p.Name] = [single]$p.Value }
  }
  return ,$d
}
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
  if ($media -eq 'off' -or -not $script:winrt) { return }
  try {
    # Volumes already saved win: a player before this one left those apps ducked, and they stay
    # where they are. Only apps not ducked yet fade down.
    $volumes = Read-Duck
    $fresh = New-Object 'System.Collections.Generic.Dictionary[string,single]'
    $playing = [SpeakAudio.Mixer]::Playing()
    foreach ($id in $playing.Keys) { if (-not $volumes.ContainsKey($id)) { $volumes[$id] = $playing[$id]; $fresh[$id] = $playing[$id] } }
    if ($volumes.Count) {
      $out = @{}; foreach ($id in $volumes.Keys) { $out[$id] = $volumes[$id] }
      ConvertTo-Json $out -Compress | Set-Content $duckFile
      if ($fresh.Count) { Fade-Volumes $fresh 1 $duckLevel; Log "ducked: $($fresh.Keys -join ', ')" }
    }
  } catch { Log "duck failed: $($_.Exception.Message)" }
  if ($media -eq 'pause') {
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
  Start-Sleep -Milliseconds 150   # a beat between the fade and the voice
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
  if (-not $script:winrt -or -not ((Test-Path $mediaFile) -or (Test-Path $duckFile))) { return }
  if (Test-OtherPlayers) { Log 'other audio left down for the next player'; return }
  Start-Sleep -Milliseconds 250   # a beat after the voice before the music comes back
  if (Test-Path $mediaFile) {
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
  if (Test-Path $duckFile) {
    # The file goes only once the volumes are back: a failed restore leaves it for the next player.
    try {
      Use-Mixer
      $volumes = Read-Duck; Fade-Volumes $volumes $duckLevel 1; Log "restored: $($volumes.Keys -join ', ')"
      Remove-Item $duckFile -ErrorAction SilentlyContinue
    } catch { Log "restore failed, volumes kept in $($duckFile): $($_.Exception.Message)" }
  }
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
      # Compile the mixer, then wait for our turn (focused session + lock), while clip 0 is fetched;
      # then turn other audio down. The ~1 s of setup hides behind the ~3 s fetch, and a beat of
      # silence is fine.
      if ($script:winrt -and $media -ne 'off') { Use-Mixer }
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
  # Also when this player never spoke: a stop while it waited for its turn still has to give back
  # the audio the player before it left down for it.
  Resume-Media
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
