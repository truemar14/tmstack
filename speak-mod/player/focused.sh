#!/usr/bin/env bash
# focused.sh <session>: exits 0 when the Claude session may speak now, 1 when it must wait. It waits
# only when Herdr lists the session and another pane is focused. Not inside Herdr, or Herdr not
# answering: speak, better than staying silent. Used by linux.sh and, on a box that plays on its SSH
# client, by remote.sh before the handoff (the client's Herdr does not know a remote session).
[[ -n ${1:-} && -n ${HERDR_ENV:-} ]] || exit 0
# With the inherited caller context set, `pane current` reports the calling pane; without it, the
# pane focused in the UI, which is what we want.
unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
exec python3 - "$1" <<'PY'
import json, subprocess, sys
sid = sys.argv[1]
def herdr(*args):
    out = subprocess.run(['herdr', *args], capture_output=True, text=True, timeout=5, check=True).stdout
    return json.loads(out)['result']
def session(x):   # a pane or agent's Claude session; None for a pane with no agent in it
    return ((x or {}).get('agent_session') or {}).get('value')
try:
    if session(herdr('pane', 'current').get('pane')) == sid: sys.exit(0)
    known = any(session(a) == sid for a in herdr('agent', 'list').get('agents') or [])
except (OSError, ValueError, KeyError, AttributeError, subprocess.SubprocessError):
    sys.exit(0)
sys.exit(1 if known else 0)
PY
