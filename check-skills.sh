#!/usr/bin/env bash
# check-skills.sh - lint every skill's frontmatter and keep private names out of this public repo.
# The repo is this checkout, or the directory given as an argument: a private repo with the same
# layout is checked with this same script, as install.sh installs it.
# For every top-level directory with a SKILL.md: the frontmatter opens on line 1 and closes, `name`
# matches the directory, `description` is not empty, and metadata.platform holds only values
# install.sh and install.ps1 understand. The README's skill table names every skill directory, and
# only those. No tracked file holds an em dash, an en dash or an arrow, the house rule for every
# document here (unslop/SKILL.md quotes them as examples, so it is exempt). Then, when PRIVATE_NAMES is set (one term per
# line, matched as whole words, any case), no tracked file may contain any of its terms. The terms
# live outside this repo, in a CI secret, because listing them here would publish them.
# Usage: ./check-skills.sh [<repo>]   (exits 1 and prints one line per problem; run it from anywhere)
set -euo pipefail
usage() { echo "usage: $0 [<repo>]" >&2; exit 2; }
(( $# <= 1 )) || usage
[[ -z ${1:-} || -d ${1:-} ]] || { echo "no such directory: $1" >&2; exit 2; }
REPO=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)
PLATFORMS=" win32 linux darwin "
fail=0
problem() { echo "$1"; fail=1; }

# field <SKILL.md> <key>: the value of "key: [a, b]" (or "key: a") inside the frontmatter, as "a b",
# quotes stripped; empty if absent. The same parser as install.sh, so the lint sees what it sees.
field() { sed -n '2,/^---$/p' "$1" | sed -n "s/^ *$2: *//p" | tr -d '[],"'"'"'' ; }

for skill in "$REPO"/*/SKILL.md; do
  [[ -f $skill ]] || continue   # a repo with no skills leaves the glob unexpanded
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
done

# The README table's rows read "| `name/` | ...": each must be a skill directory, and each skill
# directory a row.
if [[ -f $REPO/README.md ]]; then
  listed=$(sed -n 's/^| `\([^`/]*\)\/` |.*/\1/p' "$REPO/README.md" | sort)
  present=$(for s in "$REPO"/*/SKILL.md; do if [[ -f $s ]]; then basename "$(dirname "$s")"; fi; done | sort)
  for n in $(comm -23 <(echo "$present") <(echo "$listed")); do problem "README.md: no row for skill '$n'"; done
  for n in $(comm -13 <(echo "$present") <(echo "$listed")); do problem "README.md: row for '$n', which is not a skill directory"; done
fi

# Em dash, en dash and arrows (U+2014, U+2013, U+2190, U+2192, U+2194, U+21D2, U+27F6), as fixed
# UTF-8 bytes, so the check needs neither PCRE nor a UTF-8 locale. git grep exits 1 on no match;
# anything above that is a problem, not a pass. A directory outside git has no tracked files to check.
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repo: skipped the dash and arrow check"
else
  set +e
  marks=$(git -C "$REPO" grep -n -I -F -e $'\xe2\x80\x94' -e $'\xe2\x80\x93' -e $'\xe2\x86\x90' -e $'\xe2\x86\x92' \
    -e $'\xe2\x86\x94' -e $'\xe2\x87\x92' -e $'\xe2\x9f\xb6' -- . ':!unslop/SKILL.md' 2>&1)
  status=$?
  set -e
  if (( status == 0 )); then
    problem "em dash, en dash or arrow at (write a period, a comma or words):"$'\n'"$(cut -d: -f1,2 <<<"$marks")"
  elif (( status > 1 )); then
    problem "could not check for dashes and arrows: $marks"
  fi
fi

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
