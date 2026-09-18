/* @jsx h */
// The playback band drawn above the prompt while a reply is being read (and afterwards, for a
// replay): a status word, a progress line and the controls, on one row.
import type { Elements, RenderElement } from 'claude-code'
import type { Job } from './protocol.ts'

export type BandActions = {
  pause: () => void
  resume: () => void
  back: () => void
  forward: () => void
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
    case 'held': return 'waiting for this pane to be focused'
    case 'fetching': return `fetching voice${pos}`
    case 'playing': return paused ? `paused${pos}` : `speaking${pos}`
    case 'done': return 'read'
    case 'stopped': return 'stopped'
    case 'expired': return 'expired'
    case 'error': return `voice failed: ${message ?? 'unknown error'}`
  }
}

export function bandTree(el: Elements['terminal'], job: Job, columns: number, on: BandActions): RenderElement {
  const { Box, Text, Button } = el
  const { phase, paused, fraction } = job.state
  const live = phase === 'playing' || phase === 'fetching' || phase === 'held' || phase === 'starting'
  const status = statusOf(job)
  // Controls: back, pause/resume, forward, stop while live; replay and close once read.
  const controls = live
    ? [
        <Button key="speak:back" label="« 5" dimColor onPress={on.back} />,
        <Button key="speak:toggle" label={paused ? 'resume' : 'pause'} onPress={paused ? on.resume : on.pause} />,
        <Button key="speak:fwd" label="5 »" dimColor onPress={on.forward} />,
        <Button key="speak:stop" label="stop" onPress={on.stop} />,
      ]
    : phase === 'done'
      ? [
          <Button key="speak:replay" label="replay" onPress={on.replay} />,
          <Button key="speak:back" label="« 5" dimColor onPress={on.back} />,
          <Button key="speak:close" label="close" dimColor onPress={on.close} />,
        ]
      : [<Button key="speak:close" label="close" dimColor onPress={on.close} />]
  // The progress line takes what the status and the controls leave: "♪ " + status + gaps + buttons
  // (each label plus two cells of chrome) + a little slack.
  const controlCells = controls.reduce((w, b) => w + String((b as { props?: { label?: string } }).props?.label ?? '').length + 3, 0)
  const width = Math.max(8, Math.min(40, columns - status.length - controlCells - 8))
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
