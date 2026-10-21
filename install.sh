#!/usr/bin/env bash
# install.sh - link a skills repo's skills and instructions into Claude Code on this machine.
# The repo is this checkout, or the directory given as an argument: a private repo with the same
# layout is installed with this same script, so it carries no installer of its own.
# Idempotent: run it after cloning and again after pulling. For every top-level directory with a
# SKILL.md it reads the frontmatter's metadata.platform (default: all) and symlinks the directory
# into ~/.claude/skills/<name>. When the checkout has them, it also links CLAUDE.md (or AGENTS.md
# when there is no CLAUDE.md) into ~/.claude, so a skills-only repo and a private repo holding
# AGENTS.md install side by side.
# Links into the repo are re-pointed and removed when their skill folder is gone; a symlink to
# anywhere else, or a real file or directory in the way, is left alone and reported.
# Usage: ./install.sh [--dry-run] [<repo>]     (Linux and macOS; on Windows use install.ps1, since
# Git Bash makes copies instead of symlinks unless Developer Mode is on)
set -euo pipefail
usage() { echo "usage: $0 [--dry-run] [<repo>]" >&2; exit 2; }
DRY=; SRC=
for a in "$@"; do
  case $a in --dry-run) DRY=1 ;; -*) usage ;; *) [[ -z $SRC ]] || usage; SRC=$a ;; esac
done
[[ -z $SRC || -d $SRC ]] || { echo "no such directory: $SRC" >&2; exit 2; }
REPO=$(cd "${SRC:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)
case $(uname -s) in Linux) PLATFORM=linux ;; Darwin) PLATFORM=darwin ;; *) echo "install.sh supports Linux and macOS; on Windows run install.ps1" >&2; exit 2 ;; esac

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

SKILLS=$HOME/.claude/skills
[[ -d ~/.claude ]] || { echo "no ~/.claude here: install Claude Code first" >&2; exit 1; }
echo "$REPO: platform $PLATFORM${DRY:+ (dry run)}"

# Claude gets CLAUDE.md alone when the repo has one: it imports AGENTS.md through the link's real
# path, and Claude Code also loads ~/.claude/AGENTS.md in projects without a CLAUDE.md, so a link
# there would load the same file twice. An earlier run's link there is removed.
if [[ -f $REPO/AGENTS.md ]]; then
  echo "instructions -> ~/.claude"
  if [[ -f $REPO/CLAUDE.md ]]; then
    link "$REPO/CLAUDE.md" ~/.claude/CLAUDE.md
    if [[ -L ~/.claude/AGENTS.md && $(readlink ~/.claude/AGENTS.md) == "$REPO"/* ]]; then
      echo "  remove $HOME/.claude/AGENTS.md (CLAUDE.md imports it)"; [[ -n $DRY ]] || rm ~/.claude/AGENTS.md
    fi
  else
    link "$REPO/AGENTS.md" ~/.claude/AGENTS.md
  fi
fi

for skill in "$REPO"/*/SKILL.md; do
  [[ -f $skill ]] || continue   # a repo with no skills leaves the glob unexpanded
  dir=$(dirname "$skill"); name=$(basename "$dir")
  platforms=$(field "$skill" platform)
  if [[ -n $platforms && " $platforms " != *" $PLATFORM "* ]]; then echo "$name: skip ($platforms only)"; continue; fi
  echo "$name"
  link "$dir" "$SKILLS/$name"
done

# Links into the repo whose skill folder no longer exists are ours to remove.
for l in "$SKILLS"/*; do
  [[ -L $l ]] || continue; t=$(readlink "$l")
  [[ $t == "$REPO"/* && ! -f $t/SKILL.md ]] || continue
  echo "  remove $l (skill gone)"; [[ -n $DRY ]] || rm "$l"
done
