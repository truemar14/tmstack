// Pure text functions: a reply turned into speakable text and cut into clips.

// Turns markdown into something that reads well aloud: tables become "cell, cell, cell." sentences,
// headings and bullets lose their markers (headings gain a period so the voice pauses), links keep
// the label, bare URLs shrink to their host, code blocks are skipped, arrows and rules become words
// or nothing.
export function toSpeakable(input: string): string {
  let s = input.replace(/```[\s\S]*?```/g, '\ncode block omitted.\n')
  s = s.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // [label](url) -> label
  s = s.replace(/https?:\/\/([^/\s)]+)\S*/g, '$1') // bare URL -> host
  const out: string[] = []
  for (const line of s.split(/\r?\n/)) {
    let t = line.trim()
    if (/^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$/.test(t)) continue // table separator row
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(t)) continue // horizontal rule
    if (/^\|.*\|$/.test(t)) {
      // table row -> sentence
      const cells = t.replace(/^\|+|\|+$/g, '').split('|').map(c => c.trim()).filter(Boolean)
      if (cells.length) out.push(cells.join(', ') + '.')
      continue
    }
    t = t.replace(/^#{1,6}\s+(.+?)[.:]?$/, '$1.') // heading -> "Heading."
    t = t.replace(/^>\s?/, '') // blockquote
    t = t.replace(/^([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?/, '') // bullet / numbered / checkbox
    out.push(t)
  }
  s = out.join('\n')
  s = s.replace(/[`*#~]/g, '') // inline emphasis / code markers
  s = s.replace(/\s*(→|->|=>)\s*/g, ' to ')
  s = s.replace(/\s*(←|<-)\s*/g, ' from ')
  return s.replace(/\n{3,}/g, '\n\n').trim()
}

// Splits text at sentence ends into clips: a short first one (fast time-to-first-audio), longer
// after. Fish generates at only ~4x realtime, so the first clip plays after ~3 s while the rest
// are fetched ahead.
export function splitChunks(s: string, first = 150, rest = 300): string[] {
  const sentences = s.split(/(?<=[.!?:])\s+|\r?\n+/).map(x => x.trim()).filter(Boolean)
  const chunks: string[] = []
  let cur = ''
  let limit = first
  for (const sen of sentences) {
    if (cur && cur.length + 1 + sen.length > limit) {
      chunks.push(cur)
      cur = sen
      limit = rest
    } else cur = cur ? `${cur} ${sen}` : sen
  }
  if (cur) chunks.push(cur)
  return chunks
}
