/* @jsx h */
// Engine tests, run with `claude plugin test speak-mod` (the pure tests in tests/ run under node):
// the desktop app's voice path, where the wrap_up recap is read, and the band drawn there.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

type JobFile = { chunks: string[] }

// Stands in for the machine beneath the mod: voice mode on, a key, a desktop session, a player that
// starts. Returns the job files the mod writes, one per reply it hands to the player.
function desktop(on: On, surfaces: readonly ('terminal' | 'desktop')[] = ['desktop']) {
  const jobs: JobFile[] = []
  mock.env(on, { HOME: '/home/u', XDG_RUNTIME_DIR: '/run/u', FISH_API_KEY: 'key' })
  mock.store(on, { voice: true })
  mock.clock(on, { now: 1000 })
  on('session.surfaces', () => Promise.resolve({ value: surfaces }))
  on('session.id', () => Promise.resolve({ value: 'session-1' }))
  on('fs.write', (_$, e) => {
    if (e.path.endsWith('.json')) jobs.push(JSON.parse(e.text) as JobFile)
    return Promise.resolve({ value: undefined })
  })
  on('fs.read', () => Promise.resolve({ deny: 'no state yet' }))
  on('process.run', () => Promise.resolve({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('prompt.submit', (_$, e) => Promise.resolve({ text: e.text, context: e.context }))
  on('turn.complete', (_$, e) => Promise.resolve({ text: e.answer }))
  return jobs
}

const turn = (answer: string) => ({ answer, reason: 'answer' as const, durationMs: 1, isAborted: false, turnId: 't1' })

test('desktop: the model is told the recap is read', async ($, on) => {
  desktop(on)
  const r = await $.prompt.submit({ text: 'hi', wait: false, origin: { kind: 'composer' } })
  expect((r.context ?? []).join('\n')).toContain('wrap_up')
})

test('desktop: the wrap_up recap and question are read, not the reply', async ($, on) => {
  const jobs = desktop(on)
  on('tool.call', () => Promise.resolve({ result: 'ok' }))
  await $.prompt.submit({ text: 'hi', wait: false, origin: { kind: 'composer' } })
  await $.tool.call({ tool: 'mcp__ccd_turn__wrap_up', recap: 'The fix is on a branch.', ask: 'File the PR?' })
  await $.turn.complete(turn(''))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('The fix is on a branch. File the PR?')
})

test('terminal: the Spoken paragraph is read', async ($, on) => {
  const jobs = desktop(on, ['terminal'])
  await $.prompt.submit({ text: 'hi', wait: false, origin: { kind: 'composer' } })
  await $.turn.complete(turn('Details on screen.\n\nSpoken: All done.'))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('All done.')
})

test('the band draws its controls on the terminal and in the desktop app', async ($, on) => {
  desktop(on)
  await $.prompt.submit({ text: 'hi', wait: false, origin: { kind: 'composer' } })
  await $.turn.complete(turn('Spoken: Reading this.'))
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: 'speak', surface, component: 'AbovePrompt',
      props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 9 }, view: {} },
    })
    expect(await ui.find({ key: 'speak:stop' })).toBeDefined()
  }
})
