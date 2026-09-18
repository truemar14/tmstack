// The player protocol: how the hooks module talks to the detached player process that fetches and
// plays one reply's clips. Everything goes through files next to a per-reply <base> path:
//   <base>.json   the job, written by the module, read once and deleted by the player
//   <base>.state  written by the player a few times a second: PlayerState
//   <base>.cmd    written by the module, one word, consumed by the player: stop pause resume back fwd replay
// The player is player/win.ps1 on Windows and player/linux.sh on Linux; both speak this protocol.
// Only pure values and functions live here (the engine follows `$` within one file alone, so the
// calls on `$` are in register.tsx).

export type Platform = 'win32' | 'linux'

export type Phase = 'starting' | 'held' | 'fetching' | 'playing' | 'done' | 'stopped' | 'error' | 'expired'

export type PlayerState = {
  phase: Phase
  chunk: number // index of the clip being fetched or played
  n: number // clips in all
  fraction: number // 0..1 of the whole text, by characters
  paused: boolean
  message?: string // an error's text
}

export type PlayerCommand = 'stop' | 'pause' | 'resume' | 'back' | 'fwd' | 'replay'

// A reply the player is working on, as the module tracks it.
export type Job = { base: string; n: number; startedAt: number; state: PlayerState }

export type Engine = 'fish' | 'elevenlabs'
export const ENGINES: readonly Engine[] = ['fish', 'elevenlabs']
export const isEngine = (value: unknown): value is Engine => value === 'fish' || value === 'elevenlabs'

export type JobSpec = {
  base: string
  chunks: string[]
  engine: Engine
  voice: string // Fish reference_id (may be empty) or ElevenLabs voice id
  speed: number
  model: string // Fish model header or ElevenLabs model_id
  gate: boolean // hold the reply until its session is the focused Herdr pane
  session: string
  mediaPause: boolean
  // where to play: 'auto' (on the SSH client when this session came in over SSH, else here),
  // 'off' (always here), or an SSH host to always play on. Read by the Linux player.
  remote: string
}

// Phases after which the player has exited (or will within seconds) and the job is over.
export const OVER: ReadonlySet<Phase> = new Set<Phase>(['stopped', 'error', 'expired'])

export const starting = (n: number): PlayerState => ({ phase: 'starting', chunk: 0, n, fraction: 0, paused: false })

// The state file's text as a PlayerState, or undefined when it is not one (missing, mid-write).
export function parseState(text: string): PlayerState | undefined {
  try {
    const s = JSON.parse(text) as Partial<PlayerState>
    if (typeof s.phase !== 'string') return undefined
    return { phase: s.phase as Phase, chunk: s.chunk ?? 0, n: s.n ?? 0, fraction: s.fraction ?? 0, paused: s.paused === true, message: s.message }
  } catch {
    return undefined
  }
}

// The plugin's directory from the hooks module's own `import.meta.url` (…/<root>/hooks/register.tsx).
export function pluginRoot(moduleUrl: string): string {
  let path = decodeURIComponent(new URL(moduleUrl).pathname)
  if (/^\/[A-Za-z]:\//.test(path)) path = path.slice(1) // /C:/x -> C:/x
  return path.split('/').slice(0, -2).join('/')
}

// The temp directory the job, state and clip files go to, forward slashes throughout.
export function tempDirOf(platform: Platform, envTemp: string | undefined, envRuntime: string | undefined): string {
  const dir = platform === 'win32' ? envTemp : envRuntime
  return (dir ?? (platform === 'win32' ? 'C:/Temp' : '/tmp')).replace(/\\/g, '/').replace(/\/$/, '')
}

// The argv that starts the player detached for a job file, so the call returns in well under a
// second while the player fetches and plays for as long as the reply takes.
export function spawnArgv(platform: Platform, root: string, jobFile: string): string[] {
  if (platform === 'win32') {
    const args = ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', `${root}/player/win.ps1`, jobFile].map(psQuote).join(',')
    return ['powershell', '-NoProfile', '-Command', `Start-Process -WindowStyle Hidden powershell -ArgumentList @(${args}) | Out-Null`]
  }
  // setsid -f detaches; the redirects keep the child off the call's pipes, which would otherwise
  // hold the call open until the player exits.
  return ['bash', '-c', 'setsid -f bash "$1" "$2" </dev/null >/dev/null 2>&1', '_', `${root}/player/linux.sh`, jobFile]
}

const psQuote = (s: string) => `'${s.replace(/'/g, "''")}'`
