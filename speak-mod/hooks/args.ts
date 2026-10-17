// What `/speak <args>` asks for. Pure, so the parsing is testable without the engine.

export type SpeakCommand =
  | { kind: 'last' } // no args: the last reply, summarized when it is long
  | { kind: 'original' } // the last reply verbatim
  | { kind: 'stop' | 'pause' | 'resume' | 'replay' | 'back' | 'forward' | 'close' }
  | { kind: 'on' | 'off' } // voice mode, for this session only
  | { kind: 'engine'; name?: string } // show the engine, or switch it (kept across sessions)
  | { kind: 'status' | 'help' }
  | { kind: 'say'; text: string } // speak this text as given
  | { kind: 'ask'; instruction: string } // ask the model, then read its answer

const WORDS: Record<string, SpeakCommand['kind']> = {
  original: 'original', verbatim: 'original', full: 'original',
  stop: 'stop', pause: 'pause', resume: 'resume', play: 'resume', replay: 'replay', again: 'replay',
  back: 'back', forward: 'forward', fwd: 'forward', close: 'close',
  on: 'on', off: 'off', status: 'status', help: 'help',
}

export function parseArgs(args: string): SpeakCommand {
  const trimmed = args.trim()
  if (!trimmed) return { kind: 'last' }
  const [head = '', ...tail] = trimmed.split(/\s+/)
  const word = head.toLowerCase()
  if (word === 'say') {
    const text = trimmed.slice(head.length).trim()
    return text ? { kind: 'say', text } : { kind: 'help' }
  }
  if (word === 'ask') {
    const instruction = trimmed.slice(head.length).trim()
    return instruction ? { kind: 'ask', instruction } : { kind: 'help' }
  }
  if (word === 'engine' && tail.length <= 1) return tail[0] ? { kind: 'engine', name: tail[0].toLowerCase() } : { kind: 'engine' }
  const kind = tail.length === 0 ? WORDS[word] : undefined
  // anything else, a typo included, shows the help rather than sending a prompt
  return kind ? ({ kind } as SpeakCommand) : { kind: 'help' }
}

export const HELP = [
  '/speak              read the last reply (a short summary when it is long)',
  '/speak original     read the last reply word for word',
  '/speak say <text>   read this text',
  '/speak ask <request>   ask Claude, then read the answer ("ask what is left to do")',
  '/speak stop | pause | resume | back | forward | replay | close',
  '/speak on | off     read every reply aloud in this session, or not (off at start)',
  '/speak engine [fish | elevenlabs]   show or switch the voice engine',
  '/speak status       what is playing and how it is configured',
  '/speak help         this list',
].join('\n')
