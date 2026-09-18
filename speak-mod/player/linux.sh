#!/usr/bin/env bash
# linux.sh - Linux player for the speak mod. One detached process per reply, started by the hooks
# module (see hooks/protocol.ts): bash linux.sh <base>.json
# The job file { base, chunks, voice, speed, model, gate, session, mediaPause } is read once and
# deleted. FISH_API_KEY comes from the environment. Needs curl, python3 and mpv.
#
# Same protocol as win.ps1, files next to <base>:
#   <base>.state  written here a few times a second: {phase, chunk, n, fraction, paused, message}
#   <base>.cmd    written by the module, one word, consumed here: stop pause resume back fwd replay
#
# Clips are fetched two ahead of the one playing; each plays in mpv over an IPC socket, which gives
# pause/resume and ±5 s (within the clip). In gated mode the reply waits until its session is the
# focused Herdr pane (dropped after 15 min). One voice at a time across sessions via flock. After
# the reply the clips stay 20 min for a replay, then everything is deleted. No media pausing here.
# Log: $XDG_RUNTIME_DIR/claude-speak-mod.log
# Stdio mode (--stdio, no job file): the job arrives as the first line of standard input, commands as
# the lines after it, and every state goes out as one JSON line on standard output. This is how a
# remote machine (a dev box, over SSH) plays through this machine's speakers: see remote.sh. End of
# input counts as "stop".
set -uo pipefail
RUN=${XDG_RUNTIME_DIR:-/tmp}
LOG=$RUN/claude-speak-mod.log
[[ -f $LOG && $(stat -c %s "$LOG" 2>/dev/null || echo 0) -gt 200000 ]] && : >"$LOG"
log() { printf '%s [%s] %s\n' "$(date +%H:%M:%S.%3N)" "$$" "$*" >>"$LOG" 2>/dev/null || true; }

STDIO=0; BASE_OVERRIDE=
if [[ ${1:-} == --stdio ]]; then
  STDIO=1; JOB=$(mktemp "$RUN/claude-speak-job.XXXXXX"); IFS= read -r line || true; printf '%s' "$line" >"$JOB"
  BASE_OVERRIDE=$RUN/claude-speak-remote-$$
else
  JOB=${1:?job file}
  # Not the machine the user is sitting at? Hand the reply to remote.sh, which drives that machine's
  # player over SSH. "auto" means: this session came in over SSH.
  REMOTE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("remote") or "auto")' "$JOB" 2>/dev/null || echo auto)
  if [[ $REMOTE != off ]] && { [[ $REMOTE != auto ]] || [[ -n ${SSH_CONNECTION:-} ]]; }; then
    exec bash "$(dirname "${BASH_SOURCE[0]}")/remote.sh" "$JOB"
  fi
fi

# --- the job -------------------------------------------------------------------------------------
eval "$(python3 - "$JOB" "$BASE_OVERRIDE" <<'PY'
import json, shlex, sys
j = json.load(open(sys.argv[1], encoding='utf-8'))
if sys.argv[2]: j['base'] = sys.argv[2]
print('BASE=' + shlex.quote(j['base']))
print('VOICE=' + shlex.quote(j.get('voice') or ''))
print('SPEED=' + shlex.quote(str(j.get('speed', 1.05))))
print('MODEL=' + shlex.quote(j.get('model') or 's2.1-pro-free'))
print('ENGINE=' + shlex.quote(j.get('engine') or 'fish'))
print('GATE=' + ('1' if j.get('gate') else '0'))
print('SID=' + shlex.quote(j.get('session') or ''))
open(j['base'] + '.chunks', 'w', encoding='utf-8').write('\n'.join(j['chunks']))
PY
)"
rm -f "$JOB"
mapfile -t CHUNKS <"$BASE.chunks"; N=${#CHUNKS[@]}
STATE=$BASE.state; CMD=$BASE.cmd; SOCK=$BASE.sock
TOTAL=0; for c in "${CHUNKS[@]}"; do TOTAL=$((TOTAL + ${#c})); done; ((TOTAL > 0)) || TOTAL=1

# --- state and commands ---------------------------------------------------------------------------
PHASE=fetching; CHUNK=0; FRACTION=0; PAUSED=false; MESSAGE=''
write_state() {
  local s
  s=$(python3 -c 'import json,sys; print(json.dumps({"phase":sys.argv[1],"chunk":int(sys.argv[2]),"n":int(sys.argv[3]),"fraction":float(sys.argv[4]),"paused":sys.argv[5]=="true","message":sys.argv[6]}))' \
    "$PHASE" "$CHUNK" "$N" "$FRACTION" "$PAUSED" "$MESSAGE" 2>/dev/null) || return 0
  if ((STDIO)); then printf '%s\n' "$s"; return 0; fi
  printf '%s' "$s" >"$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
}
set_phase() { PHASE=$1; MESSAGE=${2:-}; write_state; log "phase $PHASE $MESSAGE"; }
STOP=0; SEEK=0; REPLAY=0; REPLAY_BACK=0
read_cmd() {   # prints the next command, or returns 1 when there is none yet
  local c rc
  if ((STDIO)); then
    IFS= read -r -t 0.01 c; rc=$?
    if ((rc == 0)); then printf '%s' "${c//[[:space:]]/}"; return 0; fi
    if ((rc < 128)); then printf 'stop'; return 0; fi   # end of input: the other side went away
    return 1
  fi
  [[ -e $CMD ]] || return 1; c=$(<"$CMD"); rm -f "$CMD"; printf '%s' "${c//[[:space:]]/}"
}
# Applies one command from the module, if any; mpv gets pause and seek when a clip is playing.
handle_cmd() {
  local c; c=$(read_cmd) || return 0
  case $c in
    stop)   STOP=1 ;;
    pause)  PAUSED=true;  mpv_cmd '["set_property","pause",true]' >/dev/null; write_state ;;
    resume) PAUSED=false; mpv_cmd '["set_property","pause",false]' >/dev/null; write_state ;;
    back)   if [[ $PHASE == done ]]; then REPLAY_BACK=1; REPLAY=1; else mpv_cmd '["seek",-5]' >/dev/null; fi ;;
    fwd)    [[ $PHASE == done ]] || mpv_cmd '["seek",5]' >/dev/null ;;
    replay) [[ $PHASE == done ]] && REPLAY=1 ;;
  esac
}

# --- mpv over its IPC socket -----------------------------------------------------------------------
MPV_PID=
mpv_cmd() {   # mpv_cmd '<json array>': prints the reply's data field (or nothing)
  [[ -n $MPV_PID && -S $SOCK ]] || return 1
  python3 - "$SOCK" "$1" <<'PY' 2>/dev/null
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(0.5)
try:
    s.connect(sys.argv[1])
    s.sendall((json.dumps({"command": json.loads(sys.argv[2]), "request_id": 7}) + "\n").encode())
    buf = b''
    while b'\n' not in buf or not any(b'"request_id":7' in l for l in buf.split(b'\n')):
        chunk = s.recv(4096)
        if not chunk: break
        buf += chunk
    for line in buf.split(b'\n'):
        if b'"request_id":7' in line or b'"request_id": 7' in line:
            d = json.loads(line).get('data')
            if d is not None: print(d)
except Exception:
    pass
PY
}

# --- turn taking -----------------------------------------------------------------------------------
focused() {   # true unless Herdr knows this session and another pane is focused
  [[ -n $SID && -n ${HERDR_ENV:-} ]] || return 0
  local cur
  cur=$(env -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID herdr pane current 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["agent_session"]["value"])' 2>/dev/null) || return 0
  [[ $cur == "$SID" ]] && return 0
  herdr agent list 2>/dev/null | python3 -c 'import json,sys; a=json.load(sys.stdin)["result"]["agents"]; sys.exit(0 if any(x.get("agent_session",{}).get("value")==sys.argv[1] for x in a) else 1)' "$SID" 2>/dev/null || return 0
  return 1
}
wait_turn() {   # gate on focus (15 min), then the cross-session lock; returns 1 when stopped/expired
  if [[ $GATE == 1 ]] && ! focused; then
    set_phase held
    local t; for ((t = 0; t < 900; t++)); do handle_cmd; ((STOP)) && return 1; focused && break; sleep 1; done
    focused || { set_phase expired; return 1; }
    set_phase fetching
  fi
  exec 9>"$RUN/claude-speak.lock"
  until flock -n 9; do handle_cmd; ((STOP)) && return 1; sleep 0.2; done
  return 0
}

# --- fetching and playing ----------------------------------------------------------------------------
fetch() {   # fetch <i>: one request in the background, per engine; writes <base>-<i>.mp3, or .fail
  local i=$1 body url
  local -a auth
  if [[ $ENGINE == elevenlabs ]]; then
    # POST /v1/text-to-speech/<voice> with the model in the body; its speed range is 0.7..1.2
    body=$(python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"model_id":sys.argv[2],"voice_settings":{"speed":max(0.7,min(1.2,float(sys.argv[3])))}}))' "${CHUNKS[$i]}" "$MODEL" "$SPEED")
    url="https://api.elevenlabs.io/v1/text-to-speech/$VOICE?output_format=mp3_44100_128"
    auth=(-H "xi-api-key: $KEY")
  else
    body=$(python3 -c 'import json,sys; b={"text":sys.argv[1],"format":"mp3","latency":"balanced","prosody":{"speed":float(sys.argv[3])}}
if sys.argv[2]: b["reference_id"]=sys.argv[2]
print(json.dumps(b))' "${CHUNKS[$i]}" "$VOICE" "$SPEED")
    url=https://api.fish.audio/v1/tts
    auth=(-H "Authorization: Bearer $KEY" -H "model: $MODEL")
  fi
  (
    if curl -sS --fail --max-time 120 -X POST "$url" "${auth[@]}" -H 'Content-Type: application/json' \
         --data-binary "$body" -o "$BASE-$i.part" 2>>"$LOG"; then mv "$BASE-$i.part" "$BASE-$i.mp3"
    else log "fetch $i failed"; : >"$BASE-$i.fail"; fi
  ) &
}
play_clip() {   # play_clip <i> <from> <to> [<start seconds>]: 0 played to the end, 1 stopped
  local i=$1 from=$2 to=$3 start=${4:-0} pct
  rm -f "$SOCK"
  # SPEAK_MPV_OPTS adds mpv options (e.g. --ao=null to test without a sound device)
  # shellcheck disable=SC2086
  mpv --no-terminal --really-quiet --input-ipc-server="$SOCK" --start="$start" --pause="$([[ $PAUSED == true ]] && echo yes || echo no)" ${SPEAK_MPV_OPTS:-} "$BASE-$i.mp3" </dev/null &
  MPV_PID=$!
  while kill -0 "$MPV_PID" 2>/dev/null; do
    handle_cmd
    if ((STOP)); then kill "$MPV_PID" 2>/dev/null; wait "$MPV_PID" 2>/dev/null; MPV_PID=; return 1; fi
    pct=$(mpv_cmd '["get_property","percent-pos"]'); pct=${pct:-0}
    FRACTION=$(python3 -c 'import sys; f,t,p=map(float,sys.argv[1:]); print(round(f+(t-f)*p/100,4))' "$from" "$to" "$pct")
    write_state
    sleep 0.1
  done
  wait "$MPV_PID" 2>/dev/null; MPV_PID=
  return 0
}
play_round() {   # play_round <first> <start seconds>: 0 when everything played, 1 otherwise
  local first=$1 start=$2 i j done=0 t
  for ((i = 0; i < first; i++)); do done=$((done + ${#CHUNKS[$i]})); done
  for ((i = first; i < N; i++)); do
    CHUNK=$i
    for ((j = i; j < i + 3 && j < N; j++)); do
      [[ -e $BASE-$j.mp3 || -e $BASE-$j.part || -e $BASE-$j.fail ]] || fetch "$j"
    done
    if ((i == first)); then wait_turn || return 1; fi
    if [[ ! -e $BASE-$i.mp3 ]]; then
      set_phase fetching
      for ((t = 0; t < 1200; t++)); do handle_cmd; ((STOP)) && return 1; [[ -e $BASE-$i.mp3 || -e $BASE-$i.fail ]] && break; sleep 0.1; done
      [[ -e $BASE-$i.mp3 ]] || { log "chunk $i missing, skipped"; continue; }
    fi
    set_phase playing
    play_clip "$i" "$(python3 -c 'print(int(__import__("sys").argv[1])/int(__import__("sys").argv[2]))' "$done" "$TOTAL")" \
                   "$(python3 -c 'print((int(__import__("sys").argv[1])+int(__import__("sys").argv[2]))/int(__import__("sys").argv[3]))' "$done" "${#CHUNKS[$i]}" "$TOTAL")" "$start" || return 1
    start=0; done=$((done + ${#CHUNKS[$i]})); log "played $i"
  done
  flock -u 9 2>/dev/null
  ls "$BASE"-*.mp3 >/dev/null 2>&1 || { set_phase error "$ENGINE request failed (see claude-speak-mod.log)"; return 1; }
  return 0
}
wait_replay() {   # after a full read: 0 on replay (REPLAY_BACK set for "back"), 1 on stop or after 20 min
  REPLAY=0; REPLAY_BACK=0; PAUSED=false
  local t; for ((t = 0; t < 12000; t++)); do handle_cmd; ((STOP)) && return 1; ((REPLAY)) && return 0; sleep 0.1; done
  set_phase expired; return 1
}

cleanup() { kill "${MPV_PID:-}" 2>/dev/null; rm -f "$BASE"-*.mp3 "$BASE"-*.part "$BASE"-*.fail "$BASE.chunks" "$CMD" "$SOCK"; }
trap 'cleanup; exit 143' TERM
# The engine's key: SPEAK_API_KEY from the module, else the engine's own variable (from ~/.secrets too).
KEYVAR=FISH_API_KEY; [[ $ENGINE == elevenlabs ]] && KEYVAR=ELEVENLABS_API_KEY
KEY=${SPEAK_API_KEY:-${!KEYVAR:-}}
if [[ -z $KEY && -r ~/.secrets ]]; then set +u; source ~/.secrets; set -u; KEY=${!KEYVAR:-}; fi
[[ -n $KEY ]] || { set_phase error "$KEYVAR is not set on $(hostname)"; ((STDIO)) || { sleep 5; rm -f "$STATE"; }; rm -f "$BASE.chunks"; exit 1; }
log "start, $N chunks, gate=$GATE, session=$SID"
write_state
first=0; start=0
while play_round "$first" "$start"; do
  FRACTION=1; set_phase done
  wait_replay || break
  first=0; start=0
  if ((REPLAY_BACK)); then first=$((N - 1)); start=0; fi   # "back" after the end: the last clip again
  log "replay from chunk $first"
done
((STOP)) && set_phase stopped
wait
cleanup
log "exit ($PHASE)"
((STDIO)) && exit 0
sleep 5
rm -f "$STATE"
