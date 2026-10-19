#!/usr/bin/env bash
# install.sh - link a skills repo's skills and instructions into the agent harnesses on this machine.
# The repo is this checkout, or the directory given as an argument: a private repo with the same
# layout is installed with this same script, so it carries no installer of its own.
# Idempotent: run it after cloning and again after pulling. For every top-level directory with a
# SKILL.md it reads the frontmatter's metadata.platform (default: all) and metadata.harness (default:
# claude and codex) and symlinks the directory into ~/.claude/skills/<name> and, for Codex,
# ~/.agents/skills/<name>, for each listed harness that exists here (~/.claude or ~/.codex present).
# When the checkout has them, it also links CLAUDE.md (or AGENTS.md when there is no CLAUDE.md) into
# ~/.claude, and AGENTS.md into ~/.codex, so a skills-only repo and a private repo holding AGENTS.md
# install side by side.
# Links into the repo are re-pointed and removed when their skill folder is gone, and removed from
# ~/.codex/skills, the deprecated Codex root earlier runs used; a symlink to anywhere else, or a real
# file or directory in the way, is left alone and reported.
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

# skills <harness>: where that harness reads user skills. Codex reads ~/.agents/skills.
skills() { if [[ $1 == codex ]]; then echo "$HOME/.agents/skills"; else echo "$HOME/.$1/skills"; fi; }

harnesses=(); [[ -d ~/.claude ]] && harnesses+=(claude); [[ -d ~/.codex ]] && harnesses+=(codex)
if ((${#harnesses[@]} == 0)); then echo "no ~/.claude or ~/.codex here: install Claude Code or Codex first" >&2; exit 1; fi
echo "$REPO: platform $PLATFORM, harnesses: ${harnesses[*]}${DRY:+ (dry run)}"

# Claude gets CLAUDE.md alone when the repo has one: it imports AGENTS.md through the link's real
# path, and Claude Code also loads ~/.claude/AGENTS.md in projects without a CLAUDE.md, so a link
# there would load the same file twice. An earlier run's link there is removed.
[[ -f $REPO/AGENTS.md ]] && for h in "${harnesses[@]}"; do
  echo "instructions -> ~/.$h"
  if [[ $h == claude && -f $REPO/CLAUDE.md ]]; then
    link "$REPO/CLAUDE.md" ~/.claude/CLAUDE.md
    if [[ -L ~/.claude/AGENTS.md && $(readlink ~/.claude/AGENTS.md) == "$REPO"/* ]]; then
      echo "  remove $HOME/.claude/AGENTS.md (CLAUDE.md imports it)"; [[ -n $DRY ]] || rm ~/.claude/AGENTS.md
    fi
  else
    link "$REPO/AGENTS.md" ~/."$h"/AGENTS.md
  fi
done

for skill in "$REPO"/*/SKILL.md; do
  dir=$(dirname "$skill"); name=$(basename "$dir")
  platforms=$(field "$skill" platform); want=$(field "$skill" harness)
  if [[ -n $platforms && " $platforms " != *" $PLATFORM "* ]]; then echo "$name: skip ($platforms only)"; continue; fi
  echo "$name"
  for h in "${harnesses[@]}"; do
    [[ -z $want || " $want " == *" $h "* ]] || continue
    link "$dir" "$(skills "$h")/$name"
  done
done

# Links into the repo whose skill folder no longer exists are ours to remove.
for h in "${harnesses[@]}"; do
  for l in "$(skills "$h")"/*; do
    [[ -L $l ]] || continue; t=$(readlink "$l")
    [[ $t == "$REPO"/* && ! -f $t/SKILL.md ]] || continue
    echo "  remove $l (skill gone)"; [[ -n $DRY ]] || rm "$l"
  done
done

# Codex once read ~/.codex/skills, and earlier runs linked there. Every link into the repo there is ours.
for l in ~/.codex/skills/*; do
  [[ -L $l && $(readlink "$l") == "$REPO"/* ]] || continue
  echo "  remove $l (Codex reads ~/.agents/skills)"; [[ -n $DRY ]] || rm "$l"
done
