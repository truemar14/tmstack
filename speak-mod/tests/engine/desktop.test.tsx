/* @jsx h */
// Engine tests, run with `claude plugin test speak-mod` (the pure tests in tests/ run under node):
// what voice mode reads (the wrap_up recap, a short reply, a Haiku summary), `/speak ask`, and the
// band on both surfaces.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

type JobFile = { chunks: string[] }
type Summary = { isAnswered: true; text: string } | { isAnswered: false; reason: 'empty-reply' }

// Stands in for the machine beneath the mod: a key, a session, a player that starts, and a
// summarizer. `jobs` are the job files the mod writes, one per reply it hands to the
// player; `player.state` is what the player's state file holds, read on the band's next poll;
// `player.start` answers each process the mod runs with its exit code, and `runs` are their argv;
// `summaries` are the prompts the mod sent to the summary model, and `model.reply` what it answers;
// `prompts` are the prompt texts that reached core; `toasts` what the mod showed.
function machine(on: On) {
  const jobs: JobFile[] = []
  const summaries: string[] = []
  const prompts: string[] = []
  const toasts: string[] = []
  const runs: string[][] = []
  const player = { state: '', start: (): Promise<number> => Promise.resolve(0) }
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
  on('session.id', () => Promise.resolve({ value: 'session-1' }))
  on('fs.write', (_$, e) => {
    if (e.path.endsWith('.json')) jobs.push(JSON.parse(e.text) as JobFile)
    return Promise.resolve({ value: undefined })
  })
  on('fs.read', () => Promise.resolve(player.state ? { value: player.state } : { deny: 'no state yet' }))
  on('process.run', async (_$, e) => {
    runs.push([...e.argv])
    return { value: { exitCode: await player.start(), stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('prompt.submit', (_$, e) => (prompts.push(e.text), Promise.resolve({ text: e.text, context: e.context })))
  on('turn.start', (_$, e) => Promise.resolve({ turnId: e.turnId }))
  on('turn.complete', (_$, e) => Promise.resolve({ text: e.answer }))
  return { jobs, runs, summaries, prompts, toasts, model, clock, player }
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

test('a player that stops answering ends the band with a toast; a paused one does not', async ($, on) => {
  const { toasts, clock, player } = machine(on)
  const status = async () => (await $.command.run({ command: 'speak', args: 'status' })).text
  await $.command.run({ command: 'speak', args: 'say Reading this.' })
  player.state = JSON.stringify({ phase: 'playing', chunk: 0, n: 1, fraction: 0.2, paused: true })
  await clock.advance(30_000)
  expect(await status()).toContain('playing')
  player.state = ''
  await clock.advance(16_000)
  expect(await status()).toContain('idle')
  expect(toasts.at(-1)).toContain('stopped answering')
})

test('a player that does not start leaves no files behind', async ($, on) => {
  const { runs, player } = machine(on)
  player.start = () => Promise.resolve(1)
  const r = await $.command.run({ command: 'speak', args: 'say Reading this.' })
  expect(r.text).toContain('player did not start')
  expect(runs.at(-1)?.join(' ')).toContain('Remove-Item')
  expect(runs.at(-1)?.join(' ')).toContain('.state')
})

test('a reply started while another player was starting keeps its progress', async ($, on) => {
  const { clock, player } = machine(on)
  let release = () => {}
  const starting = new Promise<void>(reached => {
    player.start = () => new Promise(done => { release = () => done(0); player.start = () => Promise.resolve(0); reached() })
  })
  const first = $.command.run({ command: 'speak', args: 'say First.' })
  await starting
  await clock.advance(1) // a later base for the second reply
  await $.command.run({ command: 'speak', args: 'say Second.' })
  release()
  await first
  player.state = JSON.stringify({ phase: 'playing', chunk: 0, n: 1, fraction: 0.4, paused: false })
  await clock.advance(300)
  expect((await $.command.run({ command: 'speak', args: 'status' })).text).toContain('playing 1/1')
})
