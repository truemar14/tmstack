# install.ps1 - Windows counterpart of install.sh: link a skills repo's skills and instructions into
# Claude Code on this machine. The repo is this checkout, or the directory given as -Repo (or the
# first argument), so a private repo with the same layout needs no installer of its own.
# Idempotent: run it after cloning and again after pulling.
# Skill directories become junctions (no admin needed) in ~/.claude/skills when metadata.platform
# allows win32 (default: all). CLAUDE.md (or AGENTS.md when there is no CLAUDE.md) goes into
# ~/.claude when the checkout has it: a symlink when the shell is elevated or Developer Mode is on,
# and a copy otherwise, refreshed on every run. Links into the repo are re-pointed and removed when
# their skill folder is gone; a link to anywhere else, or a real directory in the way, is left alone
# and reported.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-DryRun] [<repo>]
[CmdletBinding()]
param([Parameter(Position = 0)][string]$Repo, [switch]$DryRun)
if (-not $Repo) { $Repo = $PSScriptRoot }
if (-not (Test-Path -LiteralPath $Repo -PathType Container)) { Write-Error "no such directory: $Repo"; exit 2 }
# $repo is $Repo (PowerShell names ignore case): the full path, without a trailing backslash.
$repo = (Resolve-Path -LiteralPath $Repo).Path.TrimEnd('\')
$skills = "$HOME\.claude\skills"
if (-not (Test-Path "$HOME\.claude")) { Write-Error 'no ~/.claude here: install Claude Code first'; exit 1 }
"${repo}: platform win32$(if ($DryRun) { ' (dry run)' })"

# Field <SKILL.md> <key>: the values of "  key: [a, b]" (or "  key: a") inside the frontmatter, quotes
# stripped; empty if absent
function Field($file, $key) {
  $fm = ((Get-Content $file -Raw) -split '(?m)^---\s*$')[1]
  if ($fm -match "(?m)^\s*${key}:\s*(.+)$") { $matches[1] -replace '[\[\]"'']', '' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
}

function Link($target, $path, $kind) {   # kind: dir (junction) or file (symlink, else copy)
  $item = Get-Item $path -Force -ErrorAction SilentlyContinue
  if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    $current = $item.Target -join ''
    if ($current -eq $target) { "  ok     $path"; return }
    if (-not $current.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) { "  SKIP   $path links outside this repo ($current)"; return }
    "  relink $path"
    if (-not $DryRun) { if ($kind -eq 'dir') { [IO.Directory]::Delete($path) } else { [IO.File]::Delete($path) } }
  } elseif ($item -and $kind -eq 'file') {
    if ((Get-Content $path -Raw) -eq (Get-Content $target -Raw)) { "  ok     $path (copy, up to date)"; return }
    "  update $path (copy)"; if (-not $DryRun) { Copy-Item $target $path }; return
  } elseif ($item) {
    "  SKIP   $path exists and is not a link"; return
  } else { "  link   $path" }
  if ($DryRun) { return }
  New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
  if ($kind -eq 'dir') { New-Item -ItemType Junction -Path $path -Target $target | Out-Null; return }
  try { New-Item -ItemType SymbolicLink -Path $path -Target $target -ErrorAction Stop | Out-Null }
  catch { Copy-Item $target $path; "         copied instead: symlinks need an elevated shell or Developer Mode" }
}

# Instruction files are linked only when this checkout has them, so a skills-only repo and a private
# repo holding AGENTS.md can be installed side by side.
# Claude gets CLAUDE.md alone when the repo has one and it is a symlink: it imports AGENTS.md through
# the link's real path, and Claude Code also loads ~/.claude/AGENTS.md in projects without a CLAUDE.md,
# so a link there would load the same file twice. A copied CLAUDE.md imports the AGENTS.md beside it,
# so that one gets a copy too; both name the same path, so it still loads once.
if (Test-Path "$repo\AGENTS.md") {
  "instructions -> ~/.claude"
  if (Test-Path "$repo\CLAUDE.md") {
    Link "$repo\CLAUDE.md" "$HOME\.claude\CLAUDE.md" file
    $claude = Get-Item "$HOME\.claude\CLAUDE.md" -Force -ErrorAction SilentlyContinue
    if (-not ($claude -and ($claude.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
      Link "$repo\AGENTS.md" "$HOME\.claude\AGENTS.md" file
    } else {
      $old = Get-Item "$HOME\.claude\AGENTS.md" -Force -ErrorAction SilentlyContinue
      if ($old -and ($old.Attributes -band [IO.FileAttributes]::ReparsePoint) -and ($old.Target -join '').StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) {
        "  remove $($old.FullName) (CLAUDE.md imports it)"; if (-not $DryRun) { [IO.File]::Delete($old.FullName) }
      }
    }
  } else {
    Link "$repo\AGENTS.md" "$HOME\.claude\AGENTS.md" file
  }
}
foreach ($skill in Get-ChildItem $repo -Directory | Where-Object { Test-Path "$($_.FullName)\SKILL.md" }) {
  $md = "$($skill.FullName)\SKILL.md"; $platforms = @(Field $md platform)
  if ($platforms -and $platforms -notcontains 'win32') { "$($skill.Name): skip ($($platforms -join ', ') only)"; continue }
  $skill.Name
  Link $skill.FullName "$skills\$($skill.Name)" dir
}
# Links into the repo whose skill folder no longer exists are ours to remove.
foreach ($link in Get-ChildItem $skills -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }) {
  $t = $link.Target -join ''
  if ($t.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path "$t\SKILL.md")) { "  remove $($link.FullName) (skill gone)"; if (-not $DryRun) { [IO.Directory]::Delete($link.FullName) } }
}
