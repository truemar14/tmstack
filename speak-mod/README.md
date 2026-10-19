# speak (mod)

Claude Code replies read aloud with a Fish Audio or ElevenLabs voice, as a
plugin of function hooks ("Claude Mods"), wired into the engine instead of
shelled out around it. Codex has no function hooks and no voice mode.

- Voice mode is off at every session start. `/speak on` turns it on for that
  session only, and `/speak off` turns it off. Claude Code's own `/voice`
  dictation does not touch it.
- In voice mode every reply is read once its turn ends. A short reply is read
  as it is. A longer one is summarized in one to three plain sentences by a
  separate Haiku call through the session's own credentials, with no view of
  the conversation. If that call fails, a toast says so and nothing is read.
  The model doing the work is never told about the voice, so nothing is added
  to the conversation and no summary is written into the reply.
- In the Claude desktop app, a turn that ends with the app's recap box is read
  from that box instead: its recap, then its question. The band below draws
  there too, in the app's own buttons with a sound mark and a slim progress
  bar; `/speak` is terminal only.
- `/speak` reads the last reply (summarized when it is long), `/speak
  original` reads it word for word, `/speak say <text>` speaks a text, `/speak
  ask <request>` asks the model and reads the answer (`/speak ask summarize
  that in two sentences`), `/speak stop | pause | resume | back | forward |
  replay`, `/speak on | off`, `/speak status`, `/speak help`. Any other word
  shows the help, so a typo never sends a prompt.
- Two engines, Fish Audio and ElevenLabs: `/speak engine elevenlabs` switches
  (kept across sessions), or set the `engine` option under `/config`. Each has
  its own key, voice and model fields; Fish's free tier is unmetered, ElevenLabs
  gives 10,000 credits a month free (roughly 40 to 100 spoken summaries with
  the Flash model) and a commercial licence from the $6 Starter plan.
- A band above the prompt shows what is being read with a progress line and
  buttons: back 5 s, pause, stop; after the reply, replay (kept
  20 minutes) and close.
- A new prompt stops this session's reading. Inside [Herdr](https://herdr.dev),
  a terminal workspace for agent sessions, a reply from a session that is not
  the focused pane is held until you switch to it. Voices
  never overlap across sessions. On Windows, other audio fades down to a twelfth
  under the voice and back up after it. The `media` setting can instead fade
  media apps out and pause them (`pause`), or leave audio alone (`off`).

## Files

| Path | Role |
|---|---|
| `.claude-plugin/plugin.json` | Manifest and `userConfig` (engine; per-engine API key in secure storage, voice and model; speed, focus gate, what happens to other audio). |
| `hooks/register.tsx` | The hooks module: `session.start`, `prompt.submit`, `tool.call` for the desktop recap, `turn.complete` with the Haiku summary, `command.run` for `/speak`, `ui.render` for the band. |
| `hooks/speakable.ts` | Markdown to spoken text, clip splitting. |
| `hooks/args.ts` | `/speak` argument parsing. |
| `hooks/protocol.ts` | The file protocol with the player and the pure helpers around it. |
| `hooks/band.tsx` | The band's tree: text marks on the terminal, the app's buttons and two SVGs in the desktop app. |
| `player/win.ps1` | Windows player: Fish fetches two clips ahead, WPF MediaPlayer, Herdr focus gate, cross-session lock, ducking or pausing other audio, replay. |
| `player/linux.sh` | Linux player: same protocol over mpv's IPC socket (needs curl, python3, mpv). Hands over to `remote.sh` when the session came in over SSH. |
| `player/remote.sh` | Drives the SSH client's own player in stdio mode and mirrors its state, so a box without speakers plays through the machine you sit at. |
| `player/authorize-client.ps1` | One-time, elevated: authorizes a box's SSH key on this Windows machine so it can play here. |
| `tests/*.spec.ts` | Pure-logic tests: `npm test` (Node 22.18 or newer strips the types itself). |
| `tests/engine/` | Hook tests against the engine: `claude plugin test speak-mod` (Claude Code 2.1.295 or newer): what voice mode reads, `/speak ask`, and the band on both surfaces. |

## How it works

The module never plays audio itself: on Windows the engine has no audio
player, and a hook may not run for longer than a few seconds anyway. Instead
`turn.complete` (or `/speak`) cuts the text into clips, writes a job file and
starts one detached player process per reply. The two talk through files next
to a per-reply `<base>` path in the temp directory: the player writes
`<base>.state` a few times a second (phase, clip, progress, paused), the module
writes `<base>.cmd` (`stop`, `pause`, `resume`, `back`, `fwd`, `replay`) and
polls the state for the band. The Fish key reaches the player as an
environment variable, never on disk.

## Setup

1. Function hooks on: `"CLAUDE_CODE_ENABLE_FUNCTION_HOOKS": "1"` under `env`
   in `~/.claude/settings.json`.
2. The tmstack checkout is a directory marketplace named `tmstack`
   (`.claude-plugin/marketplace.json` at the repo root):

   ```sh
   claude plugin marketplace add /path/to/tmstack
   claude plugin install speak@tmstack
   ```

   Then set the engine's key under `/config` (rows "speak: Fish Audio API
   key" / "speak: ElevenLabs API key"); without it the `FISH_API_KEY` /
   `ELEVENLABS_API_KEY` environment variable is used. Keys come from
   [fish.audio](https://fish.audio) and [elevenlabs.io](https://elevenlabs.io).
   The Linux player also reads a key from `~/.secrets` when that file exists,
   as a `KEY=value` line.
3. Linux only: `curl`, `python3`, `mpv` and util-linux (`flock`, `setsid`)
   on the PATH.

Develop with `claude --plugin-dir speak-mod` (`--debug` names what the engine
refused); `claude plugin validate speak-mod` shows what the module hooks and
calls; `npx -p typescript tsc -p speak-mod/tsconfig.json` typechecks against
the declarations `/plugin-types` writes into `speak-mod/.claude/types`.

## Playing on the machine you connected from

A session on a box without speakers (a remote dev box) does not stream audio anywhere.
When the session came in over SSH (`remote_playback` is `auto`), the Linux
player hands the reply to `player/remote.sh`, which opens one SSH session back
to the client, runs that client's own player in stdio mode through the launcher
the mod writes at `~/.claude/speak-player[.cmd]`, and mirrors its state lines
into the usual state file. The client fetches the clips with its own keys, read from
its environment or secrets file (the launcher starts the player directly, so a
key set under `/config` on the client is not seen), and plays them through
its own speakers; only text and progress cross the network. The client is the address in `SSH_CONNECTION` (tmux keeps it current across
re-attaches) or, when that peer is offline (a Herdr server keeps the address of
whoever started it), the live SSH login from `who` whose Tailscale peer is
online. It is named through `tailscale whois`; `~/.ssh/config` on the box
supplies the user (`Host <client hostname>` / `User <windows user>`).

One-time per client: the mod installed there and one session started (that
writes the launcher), and an SSH server that accepts the box's key. On Linux, Tailscale SSH does it. On Windows the built-in OpenSSH
server reads administrator keys from `C:\ProgramData\ssh\administrators_authorized_keys`;
`player/authorize-client.ps1`, run once from an elevated PowerShell, fetches
the box's public key over SSH and adds it. That grants the box a full
administrator shell on this machine, not only the player: authorize only a box
you already trust with this one. `remote_playback` can also be `off`
(always play here) or an SSH host name (always play there).

Two Windows details. The launcher runs the player under PowerShell 7 (`pwsh`)
when present: Windows PowerShell 5.1 reads only the first line of the stdin
the Windows SSH server hands a command, so commands would never arrive.
And other audio is left alone for remote replies, since an SSH login session
cannot see the desktop's audio sessions.

## Platforms

Windows: Windows PowerShell 5.1 (the player), speakers. Linux with speakers:
curl, python3, mpv. Linux without speakers (a remote dev box): curl, python3, ssh and
tailscale, playing through the client as above; PulseAudio over Tailscale is
not needed for playback (dictation input is a separate matter). macOS is not
supported: the Linux player leans on GNU `stat`, `flock`, `mapfile` and
`date +%N`.

Early access: the function-hooks API may change between Claude Code releases.
Built against Claude Code 2.1.
