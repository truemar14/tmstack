#!/usr/bin/env bash
# install.sh - link this repo's skills and instructions into the agent harnesses on this machine.
# Idempotent: run it after cloning and again after pulling. For every top-level directory with a
# SKILL.md it reads the frontmatter's metadata.platform (default: all) and metadata.harness (default:
# claude and codex) and symlinks the directory into ~/.claude/skills/<name> and ~/.codex/skills/<name>
# for each listed harness that exists here (~/.claude or ~/.codex present). When the checkout has them,
# it also links CLAUDE.md and AGENTS.md into ~/.claude, and AGENTS.md into ~/.codex, so a skills-only
# repo and a private repo holding AGENTS.md install side by side.
# Links into this repo are re-pointed and removed when their skill folder is gone; a symlink to anywhere
# else, or a real file or directory in the way, is left alone and reported.
# Usage: ./install.sh [--dry-run]     (on Windows use install.ps1: Git Bash cannot make symlinks)
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
case ${1:-} in '') DRY= ;; --dry-run) DRY=1 ;; *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;; esac
case $(uname -s) in Linux) PLATFORM=linux ;; Darwin) PLATFORM=darwin ;; *) echo "on Windows run install.ps1" >&2; exit 2 ;; esac

# field <SKILL.md> <key>: the value of "  key: [a, b]" (or "  key: a") inside the frontmatter, as "a b",
# quotes stripped; empty if absent
field() { sed -n '2,/^---$/p' "$1" | sed -n "s/^ *$2: *//p" | tr -d '[],"'"'"'' ; }

link() {   # link <target> <path>
  local target=$1 path=$2
  if [[ -L $path ]]; then
    local current; current=$(readlink "$path")
    [[ $current == "$target" ]] && { echo "  ok    $path"; return; }
    [[ $current == "$REPO"/* ]] || { echo "  SKIP  $path links outside this repo ($current)"; return; }
    [[ -n $DRY ]] || ln -sfn "$target" "$path"; echo "  relink $path"
  elif [[ -e $path ]]; then
    echo "  SKIP  $path exists and is not a symlink"
  else
    [[ -n $DRY ]] || { mkdir -p "$(dirname "$path")"; ln -s "$target" "$path"; }; echo "  link  $path"
  fi
}

harnesses=(); [[ -d ~/.claude ]] && harnesses+=(claude); [[ -d ~/.codex ]] && harnesses+=(codex)
if ((${#harnesses[@]} == 0)); then echo "no ~/.claude or ~/.codex here: install Claude Code or Codex first" >&2; exit 1; fi
echo "platform $PLATFORM, harnesses: ${harnesses[*]}${DRY:+ (dry run)}"

[[ -f $REPO/AGENTS.md ]] && for h in "${harnesses[@]}"; do
  echo "instructions -> ~/.$h"
  link "$REPO/AGENTS.md" ~/."$h"/AGENTS.md
  [[ $h == claude && -f $REPO/CLAUDE.md ]] && link "$REPO/CLAUDE.md" ~/.claude/CLAUDE.md
done

for skill in "$REPO"/*/SKILL.md; do
  dir=$(dirname "$skill"); name=$(basename "$dir")
  platforms=$(field "$skill" platform); want=$(field "$skill" harness)
  if [[ -n $platforms && " $platforms " != *" $PLATFORM "* ]]; then echo "$name: skip ($platforms only)"; continue; fi
  echo "$name"
  for h in "${harnesses[@]}"; do
    [[ -z $want || " $want " == *" $h "* ]] || continue
    link "$dir" ~/."$h"/skills/"$name"
  done
done

# Links into this repo whose skill folder no longer exists are ours to remove.
for h in "${harnesses[@]}"; do
  for l in ~/."$h"/skills/*; do
    [[ -L $l ]] || continue; t=$(readlink "$l")
    [[ $t == "$REPO"/* && ! -f $t/SKILL.md ]] || continue
    echo "  remove $l (skill gone)"; [[ -n $DRY ]] || rm "$l"
  done
done
