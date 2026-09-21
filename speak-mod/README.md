# speak (mod)

Claude Code replies read aloud with a Fish Audio or ElevenLabs voice, as a
plugin of function hooks ("Claude Mods"), wired into the engine instead of
shelled out around it. Codex has no function hooks and no voice mode.

- In voice mode (`/voice`, or `/speak on`) every reply's final `Spoken:`
  paragraph is read; the model is asked for that paragraph as hidden context
  beside each prompt, so nothing shows in the transcript.
- `/speak` reads the last reply, `/speak say <text>` speaks a text,
  `/speak <request>` asks the model and reads the answer (`/speak summarize
  that in two sentences`), `/speak stop | pause | resume | back | forward |
  replay`, `/speak on | off`, `/speak status`.
- Two engines, Fish Audio and ElevenLabs: `/speak engine elevenlabs` switches
  (kept across sessions), or set the `engine` option under `/config`. Each has
  its own key, voice and model fields; Fish's free tier is unmetered, ElevenLabs
  gives 10,000 credits a month free (roughly 40 to 100 spoken summaries with
  the Flash model) and a commercial licence from the $6 Starter plan.
- A band above the prompt shows what is being read with a progress line and
  buttons: back and forward 5 s, pause, stop; after the reply, replay (kept
  20 minutes) and close.
- A new prompt stops this session's reading. Inside [Herdr](https://herdr.dev),
  a terminal workspace for agent sessions, a reply from a session that is not
  the focused pane is held until you switch to it. Voices
  never overlap across sessions. On Windows, media apps that were playing are
  paused for the duration.

## Files

| Path | Role |
|---|---|
| `.claude-plugin/plugin.json` | Manifest and `userConfig` (engine; per-engine API key in secure storage, voice and model; speed, focus gate, media pause). |
| `hooks/register.tsx` | The hooks module: `session.start`, `prompt.submit`, `turn.complete`, `command.run` for `/speak`, `ui.render` for the band. |
| `hooks/speakable.ts` | Markdown to spoken text, the `Spoken:` extraction, clip splitting. |
| `hooks/args.ts` | `/speak` argument parsing. |
| `hooks/protocol.ts` | The file protocol with the player and the pure helpers around it. |
| `hooks/band.tsx` | The band's tree. |
| `player/win.ps1` | Windows player: Fish fetches two clips ahead, WPF MediaPlayer, Herdr focus gate, cross-session lock, media pausing, replay. |
| `player/linux.sh` | Linux player: same protocol over mpv's IPC socket (needs curl, python3, mpv). Hands over to `remote.sh` when the session came in over SSH. |
| `player/remote.sh` | Drives the SSH client's own player in stdio mode and mirrors its state, so a box without speakers plays through the machine you sit at. |
| `player/authorize-client.ps1` | One-time, elevated: authorizes a box's SSH key on this Windows machine so it can play here. |
| `tests/` | Pure-logic tests: `node --test "tests/*.test.ts"` (Node 22.18 or newer strips the types itself). |

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
3. Linux only: `curl`, `python3` and `mpv` on the PATH.

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
key set under `/config` on the client is not seen), and plays them with its
own media pausing; only text and progress cross the network. The client is found from `SSH_CONNECTION` (tmux keeps it current across
re-attaches) and named through `tailscale whois`; `~/.ssh/config` on the box
supplies the user (`Host <client hostname>` / `User <windows user>`).

One-time per client: the mod installed there, and an SSH server that accepts
the box's key. On Linux, Tailscale SSH does it. On Windows the built-in OpenSSH
server reads administrator keys from `C:\ProgramData\ssh\administrators_authorized_keys`;
`player/authorize-client.ps1`, run once from an elevated PowerShell, fetches
the box's public key over SSH and adds it. That grants the box a full
administrator shell on this machine, not only the player: authorize only a box
you already trust with this one. `remote_playback` can also be `off`
(always play here) or an SSH host name (always play there).

Two Windows details. The launcher runs the player under PowerShell 7 (`pwsh`)
when present: Windows PowerShell 5.1 reads only the first line of the stdin
the Windows SSH server hands a command, so commands would never arrive.
And media pausing is off for remote replies, since an SSH login session cannot
see the desktop's media sessions.

## Platforms

Windows: Windows PowerShell 5.1 (the player), speakers. Linux with speakers:
curl, python3, mpv. Linux without speakers (a remote dev box): curl, python3, ssh and
tailscale, playing through the client as above; PulseAudio over Tailscale is
not needed for playback (dictation input is a separate matter). macOS is not
supported: the Linux player leans on GNU `stat`, `flock`, `mapfile` and
`date +%N`.

Early access: the function-hooks API may change between Claude Code releases.
Built against Claude Code 2.1.
