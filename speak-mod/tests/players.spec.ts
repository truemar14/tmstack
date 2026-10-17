// The Linux player's shell side, with stand-ins for herdr and ssh on PATH: the focus check, and
// remote.sh's gate and lost-link state. Needs bash and python3, so it is skipped on Windows.
import { describe, test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const PLAYER = join(import.meta.dirname, '..', 'player')
const skip = process.platform === 'win32'

// A temp dir with stand-in `herdr` and `ssh` scripts first on PATH. herdr answers from $PANE and
// $AGENTS (or fails when they are unset); ssh logs its arguments, answers `uname -s` with Linux,
// and otherwise reads the job line, sends one playing state and exits, as a dropped link would.
function sandbox() {
  const dir = mkdtempSync(join(tmpdir(), 'speak-players-'))
  writeFileSync(join(dir, 'herdr'), '#!/bin/sh\n[ -n "$PANE" ] || exit 1\ncase "$1" in pane) printf "%s" "$PANE";; agent) printf "%s" "$AGENTS";; esac\n', { mode: 0o755 })
  writeFileSync(join(dir, 'ssh'), `#!/bin/sh\necho "$@" >>"${dir}/ssh.log"\ncase "$*" in *"uname -s") echo Linux; exit 0;; esac\nread -r job\necho '{"phase": "playing", "chunk": 0, "n": 1, "fraction": 0.1, "paused": false, "message": ""}'\n`, { mode: 0o755 })
  const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, XDG_RUNTIME_DIR: dir, HERDR_ENV: '1' }
  return { dir, env }
}

const pane = (session?: string) => JSON.stringify({ result: { pane: session ? { agent_session: { value: session } } : { id: 'shell' } } })
const agents = (...sessions: string[]) => JSON.stringify({ result: { agents: sessions.map(value => ({ agent_session: { value } })) } })

describe('focused.sh', { skip }, () => {
  const focused = (env: NodeJS.ProcessEnv) => spawnSync('bash', [join(PLAYER, 'focused.sh'), 's1'], { env }).status
  test('speaks when its pane is focused, Herdr does not know it, or Herdr does not answer', () => {
    const { env } = sandbox()
    assert.equal(focused({ ...env, PANE: pane('s1'), AGENTS: agents('s1') }), 0)
    assert.equal(focused({ ...env, PANE: pane('s2'), AGENTS: agents('s2') }), 0)
    assert.equal(focused(env), 0)
  })
  test('waits while another pane is focused, an agent or a plain shell', () => {
    const { env } = sandbox()
    assert.equal(focused({ ...env, PANE: pane('s2'), AGENTS: agents('s1', 's2') }), 1)
    assert.equal(focused({ ...env, PANE: pane(), AGENTS: agents('s1') }), 1)
  })
})

// The file's text once `until` holds for it, or after 10 s.
async function waitFor(file: string, until: (text: string) => boolean) {
  let text = ''
  for (let i = 0; i < 100 && !until(text); i++) {
    await new Promise(r => setTimeout(r, 100))
    text = existsSync(file) ? readFileSync(file, 'utf8') : ''
  }
  return text
}

// Runs remote.sh on a job until `until` holds for the state file (or 10 s pass), and hands back the child to kill.
async function runRemote(env: NodeJS.ProcessEnv, dir: string, gate: boolean, until: (state: string) => boolean) {
  const base = join(dir, 'job')
  writeFileSync(`${base}.json`, JSON.stringify({ base, chunks: ['Hi.'], gate, session: 's1', remote: 'client' }))
  const child = spawn('bash', [join(PLAYER, 'remote.sh'), `${base}.json`], { env, stdio: 'ignore' })
  return { base, child, state: await waitFor(`${base}.state`, until) }
}

describe('remote.sh', { skip }, () => {
  test('holds a reply on the box until its pane is focused, and never reaches the client', async () => {
    const { env, dir } = sandbox()
    const { base, state, child } = await runRemote({ ...env, PANE: pane('s2'), AGENTS: agents('s1', 's2') }, dir, true, s => s.includes('held'))
    try {
      assert.match(state, /"phase":"held"/)
      writeFileSync(`${base}.cmd`, 'stop')
      const after = await waitFor(`${base}.state`, s => s.includes('stopped'))
      assert.match(after, /"phase":"stopped"/)
      assert.equal(existsSync(join(dir, 'ssh.log')), false)
    } finally { child.kill() }
  })
  test('a link that drops before the last phase leaves an error state', async () => {
    const { env, dir } = sandbox()
    const { state, child } = await runRemote(env, dir, false, s => s.includes('error'))
    try {
      assert.match(state, /"phase":"error".*lost the player on client while playing/)
    } finally { child.kill() }
  })
})
