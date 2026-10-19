/* @jsx h */
// The playback band drawn above the prompt while a reply is being read (and afterwards, for a
// replay): a status word, a progress line and the controls, on one row.
import type { Elements, RenderElement } from 'claude-code'
import type { Job } from './protocol.ts'

export type BandActions = {
  pause: () => void
  resume: () => void
  back: () => void
  stop: () => void
  replay: () => void
  close: () => void
}

// What the status word says for each phase.
function statusOf(job: Job): string {
  const { phase, chunk, n, paused, message } = job.state
  const pos = n > 1 ? ` ${Math.min(chunk + 1, n)}/${n}` : ''
  switch (phase) {
    case 'starting': return 'starting voice'
    case 'held': return 'waiting for focus'
    case 'fetching': return `fetching voice${pos}`
    case 'playing': return paused ? `paused${pos}` : `speaking${pos}`
    case 'done': return 'read'
    case 'stopped': return 'stopped'
    case 'expired': return 'expired'
    case 'error': return `voice failed: ${message ?? 'unknown error'}`
  }
}

// Cells a string takes, counting the characters some terminals draw two cells wide.
const cells = (text: string) => text.length + (text.match(/[♪«]/g)?.length ?? 0)

// The terminal's band: text marks sized to the terminal's columns.
export function bandTree(el: Elements['terminal'], job: Job, columns: number, on: BandActions): RenderElement {
  const { Box, Text, Button } = el
  const { phase, paused, fraction } = job.state
  const live = phase === 'playing' || phase === 'fetching' || phase === 'held' || phase === 'starting'
  const status = statusOf(job)
  // Controls: back, pause/resume, stop while live; replay and close once read.
  const controls = live
    ? [
        <Button key="speak:back" label="« 5" dimColor onPress={on.back} />,
        <Button key="speak:toggle" label={paused ? 'resume' : 'pause'} onPress={paused ? on.resume : on.pause} />,
        <Button key="speak:stop" label="stop" onPress={on.stop} />,
      ]
    : phase === 'done'
      ? [
          <Button key="speak:replay" label="replay" onPress={on.replay} />,
          <Button key="speak:back" label="« 5" dimColor onPress={on.back} />,
          <Button key="speak:close" label="close" dimColor onPress={on.close} />,
        ]
      : [<Button key="speak:close" label="close" dimColor onPress={on.close} />]
  // The progress line takes what the rest of the row leaves, so the row never wraps: the mark, the
  // status, and each button as "[ label ]", with one cell between items. The mark and "«" count two
  // cells, as some terminals draw them; in a narrow column the bar shrinks to nothing first.
  const labels = controls.map(b => String((b as { props?: { label?: string } }).props?.label ?? ''))
  const rest = cells('♪') + 1 + cells(status) + 1 + labels.reduce((w, l) => w + 1 + cells(l) + 4, 0)
  const width = Math.max(0, Math.min(40, columns - rest))
  const filled = Math.round(Math.max(0, Math.min(1, phase === 'done' ? 1 : fraction)) * width)
  return (
    <Box flexDirection="row" alignItems="center" columnGap={1}>
      <Text color={phase === 'error' ? 'red' : 'cyan'}>♪</Text>
      <Text dimColor={!live}>{status}</Text>
      <Text>
        <Text color="cyan">{'━'.repeat(filled)}</Text>
        <Text dimColor>{'─'.repeat(width - filled)}</Text>
      </Text>
      {controls}
    </Box>
  )
}

// The desktop app's band (variant A of the desktop mocks): a sound mark, what is happening, a slim
// progress bar and the app's own buttons, on one row that wraps in a narrow window. Every button is
// plain, so the row is one line of text high: the frame around it (fill, corners, padding) is the
// app's own and no prop reaches it. Resume stands out by its clay label instead. The two Svgs are
// images, which cannot read the app's theme, so their colors are ones that read on both.
const CLAY = '#d97757'
const QUIET = 'rgba(128,128,128,0.55)'
const TRACK = 'rgba(128,128,128,0.3)'

// Five bars of a sound mark: clay while speaking, grey otherwise.
const markSvg = (color: string) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="16" viewBox="0 0 18 16">${
    [6, 11, 16, 11, 6].map((h, i) => `<rect x="${i * 4}" y="${(16 - h) / 2}" width="2.5" height="${h}" rx="1.25" fill="${color}"/>`).join('')
  }</svg>`

// A 4 px bar filled to `fraction`; it stretches to the width it is given.
const progressSvg = (fraction: number) => {
  const pct = Math.round(Math.max(0, Math.min(1, fraction)) * 1000) / 10
  return `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="4" viewBox="0 0 100 4" preserveAspectRatio="none"><rect width="100" height="4" rx="2" fill="${TRACK}"/><rect width="${pct}" height="4" rx="2" fill="${CLAY}"/></svg>`
}

// What the desktop band says for each phase.
function desktopStatus(job: Job): string {
  const { phase, paused, message } = job.state
  switch (phase) {
    case 'starting': return 'Starting voice'
    case 'held': return 'Waiting for this session to be in front'
    case 'fetching': return 'Fetching voice'
    case 'playing': return paused ? 'Paused' : 'Reading aloud'
    case 'done': return 'Read aloud'
    case 'stopped': return 'Stopped'
    case 'expired': return 'Expired'
    case 'error': return `Voice failed: ${message ?? 'unknown error'}`
  }
}

export function desktopBandTree(el: Elements['desktop'], job: Job, on: BandActions): RenderElement {
  const { Box, Text, Button, Svg } = el
  const { phase, paused, fraction, chunk, n } = job.state
  const live = phase === 'playing' || phase === 'fetching' || phase === 'held' || phase === 'starting'
  const speaking = phase === 'playing' && !paused
  const status = desktopStatus(job)
  const mark = <Svg key="speak:mark" source={markSvg(speaking ? CLAY : QUIET)} alt={status} width={18} height={16} />
  if (live) {
    return (
      <Box flexDirection="row" alignItems="center" columnGap={1} flexWrap="wrap">
        {mark}
        <Text bold>{status}</Text>
        {n > 1 ? <Text dimColor>{`${Math.min(chunk + 1, n)} of ${n}`}</Text> : null}
        <Box flexGrow={1} minWidth={40}>
          <Svg key="speak:progress" source={progressSvg(fraction)} alt={`${Math.round(fraction * 100)}% read`} height={4} />
        </Box>
        <Button key="speak:back" label="Back 5s" plain onPress={on.back} />
        {paused
          ? <Button key="speak:toggle" plain onPress={on.resume}><Text bold color={CLAY}>Resume</Text></Button>
          : <Button key="speak:toggle" label="Pause" plain onPress={on.pause} />}
        <Button key="speak:stop" label="Stop" role="dismiss" onPress={on.stop} />
      </Box>
    )
  }
  return (
    <Box flexDirection="row" alignItems="center" columnGap={1}>
      {phase === 'error' ? null : mark}
      <Text color={phase === 'error' ? 'error' : undefined} dimColor={phase !== 'error'}>{status}</Text>
      <Box flexGrow={1} />
      {phase === 'done' ? <Button key="speak:replay" label="Replay" plain onPress={on.replay} /> : null}
      <Button key="speak:close" label="Close" role="dismiss" onPress={on.close} />
    </Box>
  )
}
