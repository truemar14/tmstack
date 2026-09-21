# install.ps1 - Windows counterpart of install.sh: link this repo's skills and instructions into the
# agent harnesses on this machine. Idempotent: run it after cloning and again after pulling.
# Skill directories become junctions (no admin needed) in ~/.claude/skills and ~/.codex/skills for each
# harness the skill lists (metadata.harness, default both) when metadata.platform allows win32 (default:
# all). CLAUDE.md and AGENTS.md, when the checkout has them, become symlinks when the shell is elevated
# or Developer Mode is on, and copies otherwise, refreshed on every run. Links into this repo
# are re-pointed and removed when their skill folder is gone; a link to anywhere else, or a real
# directory in the way, is left alone and reported.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-DryRun]
[CmdletBinding()]
param([switch]$DryRun)
$repo = $PSScriptRoot
$harnesses = @(); foreach ($h in 'claude', 'codex') { if (Test-Path "$HOME\.$h") { $harnesses += $h } }
if (-not $harnesses) { Write-Error 'no ~/.claude or ~/.codex here: install Claude Code or Codex first'; exit 1 }
"platform win32, harnesses: $($harnesses -join ' ')$(if ($DryRun) { ' (dry run)' })"

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
foreach ($h in $harnesses) {
  if (-not (Test-Path "$repo\AGENTS.md")) { continue }
  "instructions -> ~/.$h"
  Link "$repo\AGENTS.md" "$HOME\.$h\AGENTS.md" file
  if ($h -eq 'claude' -and (Test-Path "$repo\CLAUDE.md")) { Link "$repo\CLAUDE.md" "$HOME\.claude\CLAUDE.md" file }
}
foreach ($skill in Get-ChildItem $repo -Directory | Where-Object { Test-Path "$($_.FullName)\SKILL.md" }) {
  $md = "$($skill.FullName)\SKILL.md"; $platforms = @(Field $md platform); $want = @(Field $md harness)
  if ($platforms -and $platforms -notcontains 'win32') { "$($skill.Name): skip ($($platforms -join ', ') only)"; continue }
  $skill.Name
  foreach ($h in $harnesses) { if (-not $want -or $want -contains $h) { Link $skill.FullName "$HOME\.$h\skills\$($skill.Name)" dir } }
}
# Links into this repo whose skill folder no longer exists are ours to remove.
foreach ($h in $harnesses) {
  foreach ($link in Get-ChildItem "$HOME\.$h\skills" -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }) {
    $t = $link.Target -join ''
    if ($t.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase) -and -not (Test-Path "$t\SKILL.md")) { "  remove $($link.FullName) (skill gone)"; if (-not $DryRun) { [IO.Directory]::Delete($link.FullName) } }
  }
}
