import { describe, test } from 'node:test'
import assert from 'node:assert/strict'
import { parseArgs } from '../hooks/args.ts'
import { mediaMode, parseState, pluginRoot, spawnArgv, tempDirOf } from '../hooks/protocol.ts'

describe('parseArgs', () => {
  test('words', () => {
    assert.deepEqual(parseArgs(''), { kind: 'last' })
    assert.deepEqual(parseArgs(' Original '), { kind: 'original' })
    assert.deepEqual(parseArgs('stop'), { kind: 'stop' })
    assert.deepEqual(parseArgs('fwd'), { kind: 'forward' })
    assert.deepEqual(parseArgs('off'), { kind: 'off' })
  })
  test('say keeps the text as typed', () => {
    assert.deepEqual(parseArgs('say Hello, world. Stop!'), { kind: 'say', text: 'Hello, world. Stop!' })
    assert.deepEqual(parseArgs('say'), { kind: 'help' })
  })
  test('engine shows or switches', () => {
    assert.deepEqual(parseArgs('engine'), { kind: 'engine' })
    assert.deepEqual(parseArgs('engine ElevenLabs'), { kind: 'engine', name: 'elevenlabs' })
  })
  test('ask sends a request to the model', () => {
    assert.deepEqual(parseArgs('ask summarize that in two sentences'), { kind: 'ask', instruction: 'summarize that in two sentences' })
    assert.deepEqual(parseArgs('ask'), { kind: 'help' })
  })
  test('a typo or stray words show the help, never a prompt', () => {
    assert.deepEqual(parseArgs('stauts'), { kind: 'help' })
    assert.deepEqual(parseArgs('stop being so verbose'), { kind: 'help' })
    assert.deepEqual(parseArgs('engine the car'), { kind: 'help' })
  })
})

describe('pluginRoot', () => {
  test('windows and posix module urls', () => {
    assert.equal(pluginRoot('file:///C:/Users/User/Work/tmstack/speak-mod/hooks/register.tsx'), 'C:/Users/User/Work/tmstack/speak-mod')
    assert.equal(pluginRoot('file:///home/user/projects/tmstack/speak-mod/hooks/register.tsx'), '/home/user/projects/tmstack/speak-mod')
    assert.equal(pluginRoot('file:///C:/Users/User/My%20Plugins/speak-mod/hooks/register.tsx'), 'C:/Users/User/My Plugins/speak-mod')
  })
})

describe('protocol helpers', () => {
  test('parseState tolerates a partial write', () => {
    assert.equal(parseState('{"phase":"play'), undefined)
    assert.deepEqual(parseState('{"phase":"playing","chunk":1,"n":3,"fraction":0.4,"paused":false}'), { phase: 'playing', chunk: 1, n: 3, fraction: 0.4, paused: false, message: undefined })
  })
  test('tempDirOf normalises slashes', () => {
    assert.equal(tempDirOf('win32', 'C:\\Users\\User\\AppData\\Local\\Temp\\', undefined), 'C:/Users/User/AppData/Local/Temp')
    assert.equal(tempDirOf('linux', undefined, undefined), '/tmp')
  })
  test('spawnArgv quotes paths for PowerShell and detaches on Linux', () => {
    const win = spawnArgv('win32', "C:/My Plugins/it's", 'C:/t/job.json')
    assert.equal(win[0], 'powershell')
    assert.ok(win[3]!.includes("'C:/My Plugins/it''s/player/win.ps1','C:/t/job.json'"))
    assert.deepEqual(spawnArgv('linux', '/p', '/t/job.json').slice(-2), ['/p/player/linux.sh', '/t/job.json'])
  })
})


describe('mediaMode', () => {
  test('keeps duck, pause and off, and falls back to duck', () => {
    assert.equal(mediaMode('pause'), 'pause')
    assert.equal(mediaMode('off'), 'off')
    assert.equal(mediaMode('duck'), 'duck')
    assert.equal(mediaMode('Pause'), 'duck')
    assert.equal(mediaMode(''), 'duck')
  })
})
