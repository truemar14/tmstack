// node --test "tests/*.test.ts"  (Node 22.18+ strips the types itself)
import { describe, test } from 'node:test'
import assert from 'node:assert/strict'
import { splitChunks, toSpeakable } from '../hooks/speakable.ts'

describe('toSpeakable', () => {
  test('tables become sentences, separators and rules go', () => {
    const s = toSpeakable('| App | Port |\n|-----|-----|\n| api | 3001 |\n---\ndone')
    assert.equal(s, 'App, Port.\napi, 3001.\ndone')
  })
  test('headings, bullets, links, urls, code blocks, arrows', () => {
    const s = toSpeakable('## Result:\n- **bold** item\n1. [docs](https://x.y/z) at https://api.fish.audio/v1/tts\n```js\nx()\n```\na -> b')
    assert.equal(s, 'Result.\nbold item\ndocs at api.fish.audio\n\ncode block omitted.\n\na to b')
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
