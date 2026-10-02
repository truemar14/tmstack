#!/usr/bin/env bash
# check-skills.sh - lint every skill's frontmatter and keep private names out of this public repo.
# For every top-level directory with a SKILL.md: the frontmatter opens on line 1 and closes, `name`
# matches the directory, `description` is not empty, and metadata.platform and metadata.harness hold
# only values install.sh and install.ps1 understand. Then, when PRIVATE_NAMES is set (one term per
# line, matched as whole words, any case), no tracked file may contain any of its terms. The terms
# live outside this repo, in a CI secret, because listing them here would publish them.
# Usage: ./check-skills.sh            (exits 1 and prints one line per problem; run it from anywhere)
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLATFORMS=" win32 linux darwin "; HARNESSES=" claude codex "
fail=0
problem() { echo "$1"; fail=1; }

# field <SKILL.md> <key>: the value of "key: [a, b]" (or "key: a") inside the frontmatter, as "a b",
# quotes stripped; empty if absent. The same parser as install.sh, so the lint sees what it sees.
field() { sed -n '2,/^---$/p' "$1" | sed -n "s/^ *$2: *//p" | tr -d '[],"'"'"'' ; }

for skill in "$REPO"/*/SKILL.md; do
  name=$(basename "$(dirname "$skill")"); rel=$name/SKILL.md
  if [[ $(head -n 1 "$skill") != --- ]] || (( $(grep -c '^---$' "$skill") < 2 )); then
    problem "$rel: frontmatter must open on line 1 and close with ---"; continue
  fi
  [[ $(field "$skill" name) == "$name" ]] || problem "$rel: name is '$(field "$skill" name)', expected '$name'"
  # A folded description ("description: >-") puts its text on the following indented lines.
  desc=$(sed -n '2,/^---$/p' "$skill" | awk '
    in_desc && /^ / { print; next }
    { in_desc = 0 }
    /^description:/ { in_desc = 1; sub(/^description:[ ]*([>|][-+]?)?/, ""); print }' | tr -d '[:space:]')
  [[ -n $desc ]] || problem "$rel: description is missing or empty"
  for v in $(field "$skill" platform); do
    [[ $PLATFORMS == *" $v "* ]] || problem "$rel: unknown platform '$v' (expected one of${PLATFORMS% })"
  done
  for v in $(field "$skill" harness); do
    [[ $HARNESSES == *" $v "* ]] || problem "$rel: unknown harness '$v' (expected one of${HARNESSES% })"
  done
done

if [[ -n ${PRIVATE_NAMES:-} ]]; then
  terms=$(printf '%s\n' "$PRIVATE_NAMES" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d')
  # Print file and line only: the matched text is private, and CI logs are public. A UTF-8 locale
  # makes -i fold case outside ASCII too, so a Cyrillic term matches in any case.
  hits=$(LC_ALL=C.UTF-8 git -C "$REPO" grep -n -i -w -F -I -f <(printf '%s\n' "$terms") | cut -d: -f1,2 || true)
  [[ -z $hits ]] || problem "private names found at:"$'\n'"$hits"
else
  echo "PRIVATE_NAMES not set: skipped the private-name check"
fi

(( fail == 0 )) && echo "skills ok"
exit "$fail"
