/* @jsx h */
// Engine tests, run with `claude plugin test speak-mod` (the pure tests in tests/ run under node):
// the desktop app's voice path, where the wrap_up recap is read, and the band drawn there.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

type JobFile = { chunks: string[] }

// Stands in for the machine beneath the mod: voice mode on, a key, a session drawn on `surfaces`, a
// player that starts. `jobs` are the job files the mod writes, one per reply it hands to the player;
// `player.state` is what the player's state file holds, read on the band's next poll.
function machine(on: On, surfaces: readonly ('terminal' | 'desktop')[] = ['desktop']) {
  const jobs: JobFile[] = []
  const player = { state: '' }
  mock.env(on, { HOME: '/home/u', XDG_RUNTIME_DIR: '/run/u', FISH_API_KEY: 'key' })
  mock.store(on, { voice: true })
  const clock = mock.clock(on, { now: 1000 })
  on('session.surfaces', () => Promise.resolve({ value: surfaces }))
  on('session.id', () => Promise.resolve({ value: 'session-1' }))
  on('fs.write', (_$, e) => {
    if (e.path.endsWith('.json')) jobs.push(JSON.parse(e.text) as JobFile)
    return Promise.resolve({ value: undefined })
  })
  on('fs.read', () => Promise.resolve(player.state ? { value: player.state } : { deny: 'no state yet' }))
  on('process.run', () => Promise.resolve({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('prompt.submit', (_$, e) => Promise.resolve({ text: e.text, context: e.context }))
  on('turn.complete', (_$, e) => Promise.resolve({ text: e.answer }))
  return { jobs, clock, player }
}

const turn = (answer: string) => ({ answer, reason: 'answer' as const, durationMs: 1, isAborted: false, turnId: 't1' })
const submit = { text: 'hi', wait: false, origin: { kind: 'composer' as const } }
const BAND = { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 9 }, view: {} }

test('desktop: the model is told the recap is read', async ($, on) => {
  machine(on)
  const r = await $.prompt.submit(submit)
  expect((r.context ?? []).join('\n')).toContain('wrap_up')
})

test('desktop: the wrap_up recap and question are read, not the reply', async ($, on) => {
  const { jobs } = machine(on)
  on('tool.call', () => Promise.resolve({ result: 'ok' }))
  await $.prompt.submit(submit)
  await $.tool.call({ tool: 'mcp__ccd_turn__wrap_up', recap: 'The fix is on a branch.', ask: 'File the PR?' })
  await $.turn.complete(turn(''))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('The fix is on a branch. File the PR?')
})

test('terminal: the Spoken paragraph is read', async ($, on) => {
  const { jobs } = machine(on, ['terminal'])
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Details on screen.\n\nSpoken: All done.'))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('All done.')
})

test('the band draws its controls on the terminal and in the desktop app', async ($, on) => {
  machine(on)
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Spoken: Reading this.'))
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'speak', surface, component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ key: 'speak:stop' })).toBeDefined()
    expect(await ui.find({ key: 'speak:fwd' })).toBeUndefined()
  }
})

test('desktop: the band reads like the app, from speaking through paused to read', async ($, on) => {
  const { clock, player } = machine(on)
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Spoken: First part. Second part.'))
  player.state = JSON.stringify({ phase: 'playing', chunk: 0, n: 2, fraction: 0.4, paused: false })
  await clock.advance(300)
  const ui = await $.ui.mount({ plugin: 'speak', surface: 'desktop', component: 'AbovePrompt', props: BAND })
  expect(await ui.find({ type: 'Text', text: 'Reading aloud' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '1 of 2' })).toBeDefined()
  expect((await ui.find({ key: 'speak:toggle' }))?.props.label).toBe('Pause')
  expect(await ui.find({ key: 'speak:back' })).toBeDefined()
  expect(await ui.find({ key: 'speak:fwd' })).toBeUndefined()

  await ui.press({ key: 'speak:toggle' })
  const resume = await ui.find({ key: 'speak:toggle' })
  expect(resume?.text).toBe('Resume')
  expect(resume?.props.plain).toBe(true)

  player.state = JSON.stringify({ phase: 'done', chunk: 1, n: 2, fraction: 1, paused: false })
  await clock.advance(300)
  expect(await ui.find({ key: 'speak:replay' })).toBeDefined()
  expect(await ui.find({ key: 'speak:toggle' })).toBeUndefined()
})
