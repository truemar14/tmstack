#!/usr/bin/env bash
# remote.sh - plays a reply on the machine the user is sitting at, not on this one. For any box
# reached over SSH: it opens one SSH session back to the client and runs that machine's
# own player in stdio mode (win.ps1 -Stdio or linux.sh --stdio, through the launcher the speak
# module writes at ~/.claude/speak-player[.cmd] there). The job goes down as the first line,
# commands as the lines after it, and the player's state lines come back up; this shim mirrors them
# into the same <base>.state / <base>.cmd files the module reads, so nothing else changes. Only text
# and a few bytes of progress cross the network: the clips are fetched and played on the client,
# with its keys, its media pausing and its speakers.
#
# Which client: the job's "remote" field when it names a host; else the address this SSH session
# came from (tmux keeps SSH_CONNECTION current across re-attaches), turned into a Tailscale peer
# name when tailscale is around. The SSH user and key come from ~/.ssh/config as usual.
# Usage: bash remote.sh <base>.json   (linux.sh hands over here by itself; see its header)
set -uo pipefail
JOB=${1:?job file}
RUN=${XDG_RUNTIME_DIR:-/tmp}
LOG=$RUN/claude-speak-mod.log
log() { printf '%s [%s] remote: %s\n' "$(date +%H:%M:%S.%3N)" "$$" "$*" >>"$LOG" 2>/dev/null || true; }

eval "$(python3 - "$JOB" <<'PY'
import json, shlex, sys
j = json.load(open(sys.argv[1], encoding='utf-8'))
print('BASE=' + shlex.quote(j['base']))
print('REMOTE=' + shlex.quote(j.get('remote') or 'auto'))
j['gate'] = False        # the client's Herdr does not know this session; play right away
j['mediaPause'] = False  # an SSH login session cannot see the desktop's media sessions
print('JOBLINE=' + shlex.quote(json.dumps(j)))
PY
)"
rm -f "$JOB"
STATE=$BASE.state; CMD=$BASE.cmd
state() {   # state <phase> [message]: one state line the module understands, written the file way
  printf '{"phase":"%s","chunk":0,"n":0,"fraction":0,"paused":false,"message":"%s"}' "$1" "${2:-}" >"$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
}
fail() { log "$1"; state error "$1"; sleep 5; rm -f "$STATE"; exit 1; }

# --- which machine ---------------------------------------------------------------------------------
client_ip() {
  local conn=${SSH_CONNECTION:-}
  if [[ -n ${TMUX:-} ]]; then conn=$(tmux show-environment -g SSH_CONNECTION 2>/dev/null | cut -d= -f2-); fi
  [[ -n $conn ]] && printf '%s' "${conn%% *}"
}
target=$REMOTE
if [[ $target == auto || -z $target ]]; then
  ip=$(client_ip)
  [[ -n $ip ]] || fail "no SSH client to play on (not an SSH session?)"
  target=$ip
  if command -v tailscale >/dev/null 2>&1; then
    name=$(tailscale whois --json "$ip" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("Node") or {}).get("ComputedName") or (d.get("Node") or {}).get("Name") or "")' 2>/dev/null)
    [[ -n $name ]] && target=${name%%.*}
  fi
fi
# accept-new: a first contact with a tailnet peer must not stall on a host-key prompt nobody sees
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -o ServerAliveInterval=15 "$target")
log "target $target"

# The client's OS decides the launcher. `uname -s` says Linux or Darwin there; on Windows it is
# either not found (nothing on stdout) or Git's copy answering MINGW/MSYS, so anything else is
# Windows. (Windows sshd re-quotes the command line, so keep the probe a bare word.)
os=$("${SSH[@]}" 'uname -s' 2>/dev/null | tr -d '\r\n')
rc=$?; [[ $rc -eq 255 ]] && fail "cannot reach $target over SSH"
case $os in
  Linux*|Darwin*) launcher='~/.claude/speak-player' ;;
  *) launcher='.\.claude\speak-player.cmd' ;;
esac
log "client uname '${os}', launcher $launcher"

# --- bridge ------------------------------------------------------------------------------------------
coproc PLAYER { "${SSH[@]}" "$launcher" 2>>"$LOG"; }
PIN=${PLAYER[1]}; POUT=${PLAYER[0]}
printf '%s\n' "$JOBLINE" >&"$PIN" || fail "player on $target did not start"
trap 'printf "stop\n" >&"$PIN" 2>/dev/null; exit 143' TERM
got=0
while kill -0 "$PLAYER_PID" 2>/dev/null; do
  if [[ -e $CMD ]]; then c=$(<"$CMD"); rm -f "$CMD"; c=${c//[[:space:]]/}; log "command $c"; printf '%s\n' "$c" >&"$PIN" 2>/dev/null || { log "player pipe closed"; break; }; fi
  if IFS= read -r -t 0.1 line <&"$POUT"; then
    [[ $line == \{* ]] || continue
    got=1; printf '%s' "$line" >"$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
  fi
done
wait "$PLAYER_PID" 2>/dev/null
((got)) || fail "no player answered on $target (is the speak mod installed there?)"
log "done"
sleep 5
rm -f "$STATE" "$CMD"
