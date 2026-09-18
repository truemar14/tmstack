# authorize-client.ps1 - lets a remote machine (a dev box reached over SSH) play through this Windows machine's speakers
# by adding its SSH public key to the file Windows OpenSSH reads for administrator accounts.
# Run once from an ELEVATED PowerShell (the file is admin-only by design):
#   powershell -ExecutionPolicy Bypass -File authorize-client.ps1 [-Box <ssh host>]
# It fetches ~/.ssh/id_ed25519.pub from that host over SSH (so nothing is pasted by hand), appends
# it unless present, and (re)sets the ACL the sshd service insists on: Administrators and SYSTEM only.
# The OpenSSH server itself must already be installed and running (Get-Service sshd).
param([Parameter(Mandatory)][string]$Box)
$file = 'C:\ProgramData\ssh\administrators_authorized_keys'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Error 'run this from an elevated PowerShell'; exit 1 }
$key = (ssh -o BatchMode=yes -o ConnectTimeout=8 $Box 'cat ~/.ssh/id_ed25519.pub' 2>$null | Select-Object -First 1)
if (-not $key -or $key -notmatch '^ssh-') { Write-Error "could not read the public key from $Box over SSH"; exit 1 }
if (-not (Test-Path $file)) { New-Item -ItemType File -Path $file -Force | Out-Null }
if ((Get-Content $file -ErrorAction SilentlyContinue) -contains $key) { "already authorized: $($key.Split(' ')[2])" }
else { Add-Content -Path $file -Value $key; "authorized: $($key.Split(' ')[2])" }
icacls $file /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
"keys in ${file}: $((Get-Content $file | Where-Object { $_ -match '^ssh-' }).Count)"
"sshd: $((Get-Service sshd).Status)"
