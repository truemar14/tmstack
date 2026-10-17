// node --test "tests/*.test.ts"  (Node 22.18+ strips the types itself)
import { describe, test } from 'node:test'
import assert from 'node:assert/strict'
import { splitChunks, toSpeakable } from '../hooks/speakable.ts'

describe('toSpeakable', () => {
  test('tables become sentences, separators and rules go', () => {
    const s = toSpeakable('| App | Port |\n|-----|-----|\n| api | 3001 |\n---\ndone')
    assert.equal(s, 'App, Port.\napi, 3001.\ndone.')
  })
  test('headings, bullets, links, urls, code blocks, arrows', () => {
    const s = toSpeakable('## Result:\n- **bold** item\n1. [docs](https://x.y/z) at https://api.fish.audio/v1/tts\n```js\nx()\n```\na -> b')
    assert.equal(s, 'Result.\nbold item.\ndocs at api.fish.audio.\ncode block omitted.\na to b.')
  })
  test('list items and bare lines end as sentences; ones with punctuation keep it', () => {
    assert.equal(toSpeakable('Changes:\n- fixed the gate\n- **kept** the lock?\n- see (the log)'), 'Changes:\nfixed the gate.\nkept the lock?\nsee (the log).')
  })
  test('a bare URL keeps the punctuation after it', () => {
    assert.equal(toSpeakable('Read https://x.y/a/b. Then (https://z.io), or https://q.dev!'), 'Read x.y. Then (z.io), or q.dev!')
  })
  test('tilde and unclosed fences are skipped', () => {
    assert.equal(toSpeakable('Before.\n~~~\nsecret()\n~~~\nMiddle.\n````sh\nrm -rf x\n```\nstill code'), 'Before.\ncode block omitted.\nMiddle.\ncode block omitted.')
  })
})

describe('splitChunks', () => {
  test('a short first clip, longer ones after, cut at sentence ends', () => {
    const sentence = 'This sentence has forty characters in it.'
    const chunks = splitChunks(Array(12).fill(sentence).join(' '))
    assert.ok(chunks[0]!.length <= 150, 'first clip is short')
    assert.ok(chunks.slice(1, -1).every(c => c.length > 150 && c.length <= 300), 'later clips are longer')
    assert.equal(chunks.join(' '), Array(12).fill(sentence).join(' '))
  })
  test('nothing in, nothing out', () => {
    assert.deepEqual(splitChunks('  \n '), [])
  })
})
