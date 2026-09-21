/* @jsx h */
// speak: Claude's replies read aloud with the configured engine's voice, as a mod.
//
// In voice mode (Claude Code's own /voice switch, or `/speak on`) every answer's final "Spoken:"
// paragraph is read aloud; the prompt hook asks the model for that paragraph as hidden context.
// /speak reads the last reply, speaks a text, or asks the model for something spoken. A band above
// the prompt shows progress with pause, back and forward 5 s, stop and replay.
//
// Playback itself runs in a detached player process per reply (player/win.ps1, player/linux.sh):
// it fetches the clips from the configured engine, takes turns with other sessions, waits for its session to
// be the focused Herdr pane, and answers the commands this module writes (see protocol.ts). The
// module only starts it, polls its state file for the band, and writes commands.
//
// Layout note: the engine follows `$` only into functions declared at the top of this file, so the
// state is module-level and every helper that takes `$` is a top-level const.
import type { EngineInterface, PluginOptions, Register } from 'claude-code'
import { HELP, parseArgs } from './args.ts'
import { bandTree } from './band.tsx'
import {
  ENGINES, isEngine, OVER, parseState, pluginRoot, spawnArgv, starting, tempDirOf,
  type Engine, type Job, type JobSpec, type Platform, type PlayerCommand, type PlayerState,
} from './protocol.ts'
import { spokenOf, splitChunks, toSpeakable } from './speakable.ts'

// What the prompt hook tells the model in voice mode (hidden context beside the prompt).
const VOICE_INSTRUCTION = 'Voice mode is on. The user is listening, not reading: only a spoken summary of your reply is read aloud by TTS. Unless the whole reply is already one or two plain sentences, end it with a final paragraph that starts with "Spoken:" followed by one to three short, plain sentences saying what matters (what you found, what you did, what is next) as if talking to the user; no markdown, code, paths or lists in it. Everything before that line is shown on screen only.'

const COMPOSE_SUFFIX = '\n\nAnswer in plain spoken prose only, one to three short sentences unless asked for more: no markdown, code, paths or lists. It will be read aloud, not shown.'

const POLL_MS = 300
const REPLAY_WINDOW_MS = 20 * 60_000

// --- module state: one session, at most one reply being read ---
let opts: PluginOptions = {}
let platform: Platform = 'win32'
let root = ''
let tmp = ''
let session = ''
let job: Job | undefined
let poll: { cancel: () => void } | undefined
let expiry: { cancel: () => void } | undefined
// set by `/speak <request>`: read the next answer even when voice mode is off
let speakNext = false

const str = (key: string, fallback: string) => (typeof opts[key] === 'string' ? (opts[key] as string) : fallback)
const num = (key: string, fallback: number) => (typeof opts[key] === 'number' ? (opts[key] as number) : fallback)
const bool = (key: string, fallback: boolean) => (typeof opts[key] === 'boolean' ? (opts[key] as boolean) : fallback)

// Per-engine defaults: the voice id, the model, and the environment variable that may hold the key.
const DEFAULTS: Record<Engine, { voice: string; model: string; envKey: string }> = {
  fish: { voice: 'c2623f0c075b4492ac367989aee1576f', model: 's2.1-pro-free', envKey: 'FISH_API_KEY' },
  elevenlabs: { voice: 'EXAVITQu4vr4xnSDxMaL', model: 'eleven_flash_v2_5', envKey: 'ELEVENLABS_API_KEY' },
}

// The engine in use: `/speak engine <name>` wins, else the `engine` option, else Fish.
const currentEngine = async ($: EngineInterface): Promise<Engine> => {
  const override = await $.store.get('engine').catch(() => undefined)
  if (isEngine(override)) return override
  const option = opts.engine
  return isEngine(option) ? option : 'fish'
}

// The engine's key: its userConfig field (secure storage), else its environment variable. The two
// env names are spelled out because the engine lists what a module reads.
const apiKey = async ($: EngineInterface, engine: Engine): Promise<string> => {
  const fromOptions = str(`${engine}_api_key`, '')
  if (fromOptions) return fromOptions
  const fromEnv = engine === 'fish' ? await $.env.get('FISH_API_KEY') : await $.env.get('ELEVENLABS_API_KEY')
  return fromEnv ?? ''
}

// Voice mode: SPEAK_VOICE=0 in the environment (a scheduled job sets it) is off, else
// `/speak on|off` wins, else Claude Code's own voice switch in settings.
const voiceOn = async ($: EngineInterface): Promise<boolean> => {
  if ((await $.env.get('SPEAK_VOICE').catch(() => undefined)) === '0') return false
  const override = await $.store.get('voice').catch(() => undefined)
  if (override === true || override === false) return override
  const s = await $.settings.read().catch(() => ({}) as Record<string, unknown>)
  const voice = s.voice as { enabled?: unknown } | undefined
  return voice?.enabled === true || s.voiceEnabled === true
}

// --- the player protocol's calls on $ (see protocol.ts for the files) ---
const sendCommand = ($: EngineInterface, base: string, word: PlayerCommand) => $.fs.write(`${base}.cmd`, word)

const readState = async ($: EngineInterface, base: string): Promise<PlayerState | undefined> => {
  try { return parseState(await $.fs.read(`${base}.state`)) } catch { return undefined }
}

// Writes the job and starts the player detached. The API key travels as an environment variable,
// never in the job file.
const spawnPlayer = async ($: EngineInterface, spec: JobSpec, key: string) => {
  const jobFile = `${spec.base}.json`
  await $.fs.write(jobFile, JSON.stringify(spec))
  const r = await $.process.run(spawnArgv(platform, root, jobFile), { env: { SPEAK_API_KEY: key }, timeoutMs: 20000 })
  if (r.exitCode !== 0) throw new Error(`player did not start (exit ${r.exitCode}): ${r.stderr.trim()}`)
}

// Writes ~/.claude/speak-player[.cmd], the one-line launcher a remote machine runs over SSH to play
// through this machine (see player/remote.sh). Rewritten every session so it follows the checkout.
const writeLauncher = async ($: EngineInterface) => {
  const home = platform === 'win32' ? await $.env.get('USERPROFILE') : await $.env.get('HOME')
  if (!home) return
  const dir = `${home.replace(/\\/g, '/')}/.claude`
  if (platform === 'win32') {
    // pwsh (PowerShell 7) when present: Windows PowerShell 5.1 reads only the first line of the
    // stdin the Windows SSH server hands it, so commands would never arrive
    const args = `-NoProfile -STA -ExecutionPolicy Bypass -File "${root}/player/win.ps1" -Stdio`
    await $.fs.write(`${dir}/speak-player.cmd`, `@echo off\r\nwhere pwsh >nul 2>&1\r\nif %errorlevel%==0 (pwsh ${args}) else (powershell ${args})\r\n`)
  } else {
    const path = `${dir}/speak-player`
    await $.fs.write(path, `#!/usr/bin/env bash\nexec bash "${root}/player/linux.sh" --stdio\n`)
    await $.process.run(['chmod', '+x', path])
  }
}

const clearJob = ($: EngineInterface) => {
  poll?.cancel(); poll = undefined
  expiry?.cancel(); expiry = undefined
  job = undefined
  $.ui.invalidate('ui.render')
}

// Stops the current reply's playback (if any) and drops the band.
const stop = async ($: EngineInterface) => {
  if (!job) return
  if (!OVER.has(job.state.phase)) await sendCommand($, job.base, 'stop').catch(() => undefined)
  clearJob($)
}

// Polls the player's state file for the band; ends when the player is over.
const watch = ($: EngineInterface, base: string) => {
  poll?.cancel()
  let last = ''
  poll = $.clock.every(POLL_MS, async () => {
    if (!job || job.base !== base) return
    const state = await readState($, base)
    if (!state) return
    const key = JSON.stringify(state)
    if (key === last) return
    last = key
    job.state = state
    if (OVER.has(state.phase)) {
      if (state.phase === 'error') $.ui.toast(`speak: ${state.message ?? 'voice failed'}`, { timeoutMs: 8000 })
      clearJob($)
      return
    }
    if (state.phase === 'done' && !expiry) {
      // the player keeps the clips for a replay for 20 minutes, then exits; the band goes with it
      expiry = $.clock.after(REPLAY_WINDOW_MS, () => { if (job?.base === base) clearJob($) })
    }
    $.ui.invalidate('ui.render')
  })
}

// Reads `text` aloud: cuts it into clips and hands them to a fresh player. `gate` holds the reply
// until its session is focused (hook mode); a manual /speak plays regardless. Returns a problem to
// show, or undefined once the player is off.
const speak = async ($: EngineInterface, text: string, gate: boolean): Promise<string | undefined> => {
  const chunks = splitChunks(text)
  if (chunks.length === 0) return undefined
  const engine = await currentEngine($)
  const key = await apiKey($, engine)
  // A box that plays on its SSH client needs no key of its own: the client's player uses the
  // client's key when none rides along (see player/remote.sh and the players' key lookup).
  const remote = str('remote_playback', 'auto') || 'auto'
  const playsRemotely = platform === 'linux' && remote !== 'off' && (remote !== 'auto' || !!(await $.env.get('SSH_CONNECTION')))
  if (!key && !playsRemotely) return `speak: no ${engine} key. Set it under /config (speak) or export ${DEFAULTS[engine].envKey}.`
  await stop($)
  const now = await $.clock.now()
  const base = `${tmp}/claude-speak-${session.slice(0, 8)}-${now}`
  job = { base, n: chunks.length, startedAt: now, state: starting(chunks.length) }
  try {
    // the first state is ours, so the poller never reads a file that is not there yet
    await $.fs.write(`${base}.state`, JSON.stringify(job.state))
    await spawnPlayer($, {
      base, chunks, session, engine,
      voice: str(`${engine}_voice`, DEFAULTS[engine].voice),
      speed: num('speed', 1.05),
      model: str(`${engine}_model`, DEFAULTS[engine].model),
      gate: gate && bool('focus_gate', true),
      mediaPause: bool('media_pause', true),
      remote: str('remote_playback', 'auto') || 'auto',
    }, key)
  } catch (err) {
    clearJob($)
    return `speak: ${err instanceof Error ? err.message : String(err)}`
  }
  watch($, base)
  $.ui.invalidate('ui.render')
  return undefined
}

// The last assistant message with text, from the transcript.
const lastReply = async ($: EngineInterface): Promise<string | undefined> => {
  const messages = await $.session.messages()
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i]
    if (m && m.role === 'assistant' && m.text.trim()) return m.text
  }
  return undefined
}

export const register: Register = (on, options) => {
  opts = options

  on('session.start', async ($, e, next) => {
    const r = await next(e)
    platform = (await $.env.get('OS')) === 'Windows_NT' ? 'win32' : 'linux'
    root = pluginRoot((import.meta as { url?: string }).url ?? '')
    tmp = tempDirOf(platform, await $.env.get('TEMP'), await $.env.get('XDG_RUNTIME_DIR'))
    session = await $.session.id().catch(() => 'nosession')
    await writeLauncher($).catch(err => $.ui.log(`speak: launcher not written: ${err}`))
    await $.command.register({
      name: 'speak',
      description: 'Read the last reply aloud, speak a text, or ask for a spoken answer; stop, pause, replay (speak)',
      argumentHint: '[original | say <text> | <request> | stop | pause | resume | back | forward | replay | on | off | status]',
      immediate: true,
    }).catch(err => $.ui.log(`speak: /speak not registered: ${err}`))
    return r
  })

  // A new prompt interrupts this session's reading; in voice mode the model is asked for the
  // "Spoken:" paragraph as context it reads beside the prompt, never shown in the transcript.
  on('prompt.submit', async ($, e, next) => {
    await stop($)
    if (e.origin?.kind === 'plugin' || !(await voiceOn($))) return next(e)
    return next({ ...e, context: [...(e.context ?? []), VOICE_INSTRUCTION] })
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId || e.reason !== 'answer' || !e.answer.trim()) return r
    const compose = speakNext
    speakNext = false
    if (!compose && !(await voiceOn($))) return r
    const speakable = toSpeakable(e.answer)
    const text = compose ? speakable : spokenOf(speakable)
    if (!text) return r // "Spoken:" with nothing after it: the reply chose silence
    const problem = await speak($, text, true)
    if (problem) $.ui.toast(problem, { timeoutMs: 8000 })
    return r
  })

  on('command.run', { command: 'speak' }, async ($, e) => {
    const cmd = parseArgs(e.args)
    switch (cmd.kind) {
      case 'last':
      case 'original': {
        const reply = await lastReply($)
        if (!reply) return { text: 'speak: nothing to read yet' }
        const speakable = toSpeakable(reply)
        const text = cmd.kind === 'original' ? speakable : spokenOf(speakable) || speakable
        return { text: (await speak($, text, false)) ?? 'Speaking.' }
      }
      case 'say':
        return { text: (await speak($, toSpeakable(cmd.text), false)) ?? 'Speaking.' }
      case 'compose':
        speakNext = true
        await $.prompt.submit({ text: cmd.instruction + COMPOSE_SUFFIX })
        return { text: 'Asking, then reading the answer aloud.' }
      case 'stop':
        await stop($)
        return { text: 'Stopped.' }
      case 'close':
        await stop($)
        return { text: '' }
      case 'pause':
      case 'resume':
      case 'back':
      case 'forward':
      case 'replay': {
        if (!job) return { text: 'speak: nothing is playing' }
        await sendCommand($, job.base, cmd.kind === 'forward' ? 'fwd' : cmd.kind)
        return { text: '' }
      }
      case 'on':
      case 'off':
        await $.store.set('voice', cmd.kind === 'on')
        return { text: cmd.kind === 'on' ? 'Replies will be read aloud.' : 'Replies will not be read aloud (until /speak on).' }
      case 'engine': {
        if (!cmd.name) return { text: `voice engine: ${await currentEngine($)} (${ENGINES.join(' | ')})` }
        if (!isEngine(cmd.name)) return { text: `speak: no engine called "${cmd.name}" (${ENGINES.join(' | ')})` }
        await $.store.set('engine', cmd.name)
        const key = (await apiKey($, cmd.name)) ? '' : ` · no key yet: set it under /config (speak) or export ${DEFAULTS[cmd.name].envKey}`
        return { text: `voice engine: ${cmd.name}${key}` }
      }
      case 'status': {
        const voice = await voiceOn($)
        const engine = await currentEngine($)
        const playing = job ? `${job.state.phase} ${job.state.chunk + 1}/${job.n}` : 'idle'
        const key = (await apiKey($, engine)) ? 'set' : 'missing'
        return { text: `voice mode ${voice ? 'on' : 'off'} · ${playing} · ${engine} · voice ${str(`${engine}_voice`, DEFAULTS[engine].voice) || 'default'} · ${str(`${engine}_model`, DEFAULTS[engine].model)} · speed ${num('speed', 1.05)} · key ${key} · ${platform}` }
      }
      case 'help':
        return { text: HELP }
    }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!job || e.surface !== 'terminal' || e.props.hasSurvey) return next(e)
    const el = $.ui.resolve(e)
    const base = job.base
    const send = (word: PlayerCommand) => () => {
      if (job?.base !== base) return
      if (word === 'replay' || word === 'back') { expiry?.cancel(); expiry = undefined }
      if (word === 'pause' || word === 'resume') { job.state = { ...job.state, paused: word === 'pause' }; $.ui.invalidate('ui.render') }
      void sendCommand($, base, word)
    }
    // The band is this plugin's whole tree: the engine draws nothing of its own here, and
    // wrapping its empty result in a column box cost a blank row under the band.
    return bandTree(el, job, e.props.bodyColumns, {
      pause: send('pause'), resume: send('resume'), back: send('back'), forward: send('fwd'), replay: send('replay'),
      stop: () => { void stop($) },
      close: () => { void stop($) },
    })
  })
}
