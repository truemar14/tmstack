/* @jsx h */
// Engine tests, run with `claude plugin test speak-mod` (the pure tests in tests/ run under node):
// what voice mode reads (the wrap_up recap, a short reply, a Haiku summary), `/speak ask`, what a
// /clear ends, what stops a reading and what waits for it, and the band on both surfaces.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

type JobFile = { chunks: string[]; session: string }
type Summary = { isAnswered: true; text: string } | { isAnswered: false; reason: 'empty-reply' }

// Stands in for the machine beneath the mod: a key, a session (`ids.current`, its id), a player that starts, and a
// summarizer. `jobs` are the job files the mod writes, one per reply it hands to the
// player; `player.state` is what the player's state file holds, read on the band's next poll;
// `summaries` are the prompts the mod sent to the summary model, and `model.reply` what it answers;
// `prompts` are the prompt texts that reached core; `toasts` what the mod showed.
function machine(on: On) {
  const jobs: JobFile[] = []
  const summaries: string[] = []
  const prompts: string[] = []
  const toasts: string[] = []
  const player = { state: '' }
  const ids = { current: 'session-1' }
  const model = { reply: (): Promise<Summary> => Promise.resolve({ isAnswered: true, text: 'I fixed the bug.' }) }
  mock.env(on, { HOME: '/home/u', XDG_RUNTIME_DIR: '/run/u', FISH_API_KEY: 'key' })
  mock.store(on, {})
  on('model.complete', async (_$, e) => {
    summaries.push(e.prompt)
    const usage = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
    return { value: { ...(await model.reply()), usage } }
  })
  on('ui.toast', (_$, e) => (toasts.push(e.text), Promise.resolve({ value: undefined })))
  const clock = mock.clock(on, { now: 1000 })
  on('session.id', () => Promise.resolve({ value: ids.current }))
  on('session.end', (_$, e) => Promise.resolve({ sessionId: e.sessionId }))
  on('fs.write', (_$, e) => {
    if (e.path.endsWith('.json')) jobs.push(JSON.parse(e.text) as JobFile)
    return Promise.resolve({ value: undefined })
  })
  on('fs.read', () => Promise.resolve(player.state ? { value: player.state } : { deny: 'no state yet' }))
  on('process.run', () => Promise.resolve({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('prompt.submit', (_$, e) => (prompts.push(e.text), Promise.resolve({ text: e.text, context: e.context })))
  on('turn.start', (_$, e) => Promise.resolve({ turnId: e.turnId }))
  on('turn.complete', (_$, e) => Promise.resolve({ text: e.answer }))
  return { jobs, summaries, prompts, toasts, model, clock, player, ids }
}

const turn = (answer: string, turnId = 't1') => ({ answer, reason: 'answer' as const, durationMs: 1, isAborted: false, turnId })
const submit = { text: 'hi', wait: false, origin: { kind: 'composer' as const } }
const LONG = 'A paragraph that goes on for a while about what changed and why it matters. '.repeat(6)
const BAND = { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 100, scroll: { offset: 0, bodyRows: 9 }, view: {} }

test('the model is never told about the voice', async ($, on) => {
  machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  const r = await $.prompt.submit(submit)
  expect(r.context ?? []).toEqual([])
})

test('voice mode is off until /speak on', async ($, on) => {
  const { jobs } = machine(on)
  await $.prompt.submit(submit)
  await $.turn.complete(turn('All done.'))
  expect(jobs.length).toBe(0)
})

test('the wrap_up recap and question are read, not the reply', async ($, on) => {
  const { jobs, summaries } = machine(on)
  on('tool.call', () => Promise.resolve({ result: 'ok' }))
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.tool.call({ tool: 'mcp__ccd_turn__wrap_up', recap: 'The fix is on a branch.', ask: 'File the PR?' })
  await $.turn.complete(turn(''))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('The fix is on a branch. File the PR?')
  expect(summaries.length).toBe(0)
})

test('a short reply is read as it is, a long one as its summary', async ($, on) => {
  const { jobs, summaries } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('All **done**.'))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('All done.')
  await $.prompt.submit(submit)
  await $.turn.complete(turn(LONG))
  expect(summaries).toEqual([`<reply>\n${LONG}\n</reply>`])
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('I fixed the bug.')
})

test('a failed summary reads nothing and says so', async ($, on) => {
  const { jobs, toasts, model } = machine(on)
  model.reply = () => Promise.resolve({ isAnswered: false, reason: 'empty-reply' })
  await $.command.run({ command: 'speak', args: 'on' })
  await $.turn.complete(turn(LONG))
  expect(jobs.length).toBe(0)
  expect(toasts.at(-1)).toContain('/speak original')
})

test('a summary that comes back after the next turn started is dropped', async ($, on) => {
  const { jobs, model } = machine(on)
  let release = () => {}
  let asked = () => {}
  const summaryAsked = new Promise<void>(done => { asked = done })
  model.reply = () => new Promise(done => { release = () => done({ isAnswered: true, text: 'Too late.' }); asked() })
  await $.command.run({ command: 'speak', args: 'on' })
  const reading = $.turn.complete(turn(LONG))
  await summaryAsked
  await $.turn.start({ text: 'next', turnId: 't2' })
  release()
  await reading
  expect(jobs.length).toBe(0)
})

test('/speak ask reads its own turn only: not one running when it was sent, not after an abort', async ($, on) => {
  const { jobs, prompts, clock } = machine(on)
  await $.turn.start({ text: 'hi', turnId: 't1' })
  await $.command.run({ command: 'speak', args: 'ask what is left?' })
  await clock.advance(0)
  await $.turn.complete(turn('The running turn.', 't1'))
  expect(prompts.at(-1)).toContain('what is left?')
  const asked = prompts.at(-1) ?? ''
  await $.turn.start({ text: asked, turnId: 't2' })
  await $.turn.complete({ ...turn('', 't2'), reason: 'aborted' as const, isAborted: true })
  await $.turn.start({ text: 'hi', turnId: 't3' })
  await $.turn.complete(turn('An unrelated answer.', 't3'))
  expect(jobs.length).toBe(0)
  await $.turn.start({ text: asked, turnId: 't4' })
  await $.turn.complete(turn(LONG, 't4'))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe(LONG.trim())
})

test('only the user stops a reading: a message from another session or a background task does not', async ($, on) => {
  const { jobs } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Reading this.'))
  expect(jobs.length).toBe(1)
  const status = async () => (await $.command.run({ command: 'speak', args: 'status' })).text
  await $.prompt.submit({ ...submit, origin: { kind: 'peer' as const } })
  await $.prompt.submit({ ...submit, origin: { kind: 'task-notification' as const } })
  await $.prompt.submit({ ...submit, origin: { kind: 'plugin' as const, name: 'other-mod' } })
  expect(await status()).not.toContain('idle')
  await $.prompt.submit(submit)
  expect(await status()).toContain('idle')
})

test('a reply from a turn the user did not start is not read, even when that turn starts a subagent', async ($, on) => {
  const { jobs, summaries } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.start({ text: 'hi', turnId: 't1' })
  await $.turn.complete(turn('The answer to the user.', 't1'))
  expect(jobs.length).toBe(1)
  await $.prompt.submit({ ...submit, text: 'a report', origin: { kind: 'peer' as const } })
  await $.turn.start({ text: 'a report', turnId: 't2' })
  await $.turn.start({ text: 'look into it', turnId: 'a1', agentId: 'agent-1' })
  await $.turn.complete(turn(LONG, 't2'))
  expect(jobs.length).toBe(1)
  expect(summaries.length).toBe(0)
  await $.prompt.submit(submit)
  await $.turn.start({ text: 'hi', turnId: 't3' })
  await $.turn.start({ text: 'look into it', turnId: 'a2', agentId: 'agent-2' })
  await $.turn.complete(turn('The next answer.', 't3'))
  expect(jobs.at(-1)?.chunks.join(' ')).toBe('The next answer.')
})

test("the user typing into a running automated turn makes that turn the user's, so its reply is read", async ($, on) => {
  const { jobs } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit({ ...submit, text: 'a report', origin: { kind: 'peer' as const } })
  await $.turn.start({ text: 'a report', turnId: 't1' })
  await $.prompt.submit({ ...submit, turnId: 't1' })
  await $.turn.complete(turn('Now the user is in it.', 't1'))
  expect(jobs.map(j => j.chunks.join(' '))).toEqual(['Now the user is in it.'])
})

test("an automated turn does not drop the user's summary still being written", async ($, on) => {
  const { jobs, model } = machine(on)
  let release = () => {}
  let asked = () => {}
  const summaryAsked = new Promise<void>(done => { asked = done })
  model.reply = () => new Promise(done => { release = () => done({ isAnswered: true, text: 'The user summary.' }); asked() })
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.start({ text: 'hi', turnId: 't1' })
  const reading = $.turn.complete(turn(LONG, 't1'))
  await summaryAsked
  await $.prompt.submit({ ...submit, text: 'a report', origin: { kind: 'task-notification' as const } })
  await $.turn.start({ text: 'a report', turnId: 't2' })
  await $.turn.start({ text: 'look into it', turnId: 'a1', agentId: 'agent-1' })
  await $.turn.complete(turn('The report.', 't2'))
  release()
  await reading
  expect(jobs.map(j => j.chunks.join(' '))).toEqual(['The user summary.'])
})

test('a /clear stops the reading and turns voice mode off', async ($, on) => {
  const { jobs, ids } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Reading this.'))
  expect(jobs.length).toBe(1)
  await $.session.end({ reason: 'clear', sessionId: ids.current, resume: { id: ids.current } })
  expect((await $.command.run({ command: 'speak', args: 'status' })).text).toContain('idle')
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Not read.', 't2'))
  expect(jobs.length).toBe(1)
})

test('after a /clear the player gets the new session id, so the focus gate still knows it', async ($, on) => {
  const { jobs, ids } = machine(on)
  await $.session.end({ reason: 'clear', sessionId: ids.current, resume: { id: ids.current } })
  ids.current = 'session-2'
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Reading this.'))
  expect(jobs[0]?.session).toBe('session-2')
})

test('the band draws its controls on the terminal and in the desktop app', async ($, on) => {
  machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Reading this.'))
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'speak', surface, component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ key: 'speak:stop' })).toBeDefined()
  }
})

test('the terminal band keeps to one row: only the bar gets shorter', async ($, on) => {
  const { player, clock } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('Reading this.'))
  type El = { type: string; props?: { label?: string }; children?: unknown[] }
  const text = (el: unknown): string => (typeof el === 'string' ? el : ((el as El).children ?? []).map(text).join(''))
  // The mark and "«" may draw two cells wide; a Button draws as "[ label ]"; one cell between items.
  const cells = (s: string) => s.length + (s.match(/[♪«]/g)?.length ?? 0)
  // read, and waiting for focus, a long status with the live controls, down to a narrow pane
  for (const [phase, widths] of [['done', [100, 55, 40]], ['held', [100, 55]]] as const) {
    player.state = JSON.stringify({ phase, chunk: 0, n: 1, fraction: phase === 'done' ? 1 : 0, paused: false })
    await clock.advance(300)
    for (const bodyColumns of widths) {
      const ui = await $.ui.mount({ plugin: 'speak', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, bodyColumns } })
      const [mark, status, bar, ...buttons] = ((await ui.drawn()) as El).children as El[]
      expect(buttons.length).toBe(3)
      const row = cells(text(mark)) + 1 + cells(text(status)) + 1 + cells(text(bar))
        + buttons.reduce((w, b) => w + 1 + cells(String(b.props?.label)) + 4, 0)
      expect(row).toBeLessThanOrEqual(bodyColumns)
    }
  }
})

test('desktop: the band reads like the app, from speaking through paused to read', async ($, on) => {
  const { clock, player } = machine(on)
  await $.command.run({ command: 'speak', args: 'on' })
  await $.prompt.submit(submit)
  await $.turn.complete(turn('First part. Second part.'))
  player.state = JSON.stringify({ phase: 'playing', chunk: 0, n: 2, fraction: 0.4, paused: false })
  await clock.advance(300)
  const ui = await $.ui.mount({ plugin: 'speak', surface: 'desktop', component: 'AbovePrompt', props: BAND })
  expect(await ui.find({ type: 'Text', text: 'Reading aloud' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '1 of 2' })).toBeDefined()
  expect((await ui.find({ key: 'speak:toggle' }))?.props.label).toBe('Pause')
  expect(await ui.find({ key: 'speak:back' })).toBeDefined()

  await ui.press({ key: 'speak:toggle' })
  const resume = await ui.find({ key: 'speak:toggle' })
  expect(resume?.text).toBe('Resume')
  expect(resume?.props.plain).toBe(true)

  player.state = JSON.stringify({ phase: 'done', chunk: 1, n: 2, fraction: 1, paused: false })
  await clock.advance(300)
  expect(await ui.find({ key: 'speak:replay' })).toBeDefined()
  expect(await ui.find({ key: 'speak:toggle' })).toBeUndefined()
})
