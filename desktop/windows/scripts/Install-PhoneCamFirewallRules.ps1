param(
  [string]$Receiver = ".\bin\phonecam-receiver.exe",
  [string]$RulePrefix = "PhoneCam",
  [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$discoveryRuleName = "$RulePrefix Receiver Discovery UDP"
$rtspRuleName = "$RulePrefix Receiver RTSP TCP Out"

function Resolve-ExistingFile {
  param([string]$Path)

  if (-not (Test-Path $Path -PathType Leaf)) {
    throw "File not found: $Path"
  }
  return (Resolve-Path $Path).Path
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-NetSecurityAvailable {
  if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
    throw "New-NetFirewallRule was not found. Run this on Windows with the NetSecurity module available."
  }
}

function Remove-RuleIfPresent {
  param([string]$Name)

  $existing = Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue
  if ($existing) {
    Remove-NetFirewallRule -Name $Name
  }
}

if (-not (Test-IsAdministrator)) {
  throw "Firewall rule changes require an elevated PowerShell session."
}

Assert-NetSecurityAvailable

if ($Remove) {
  Remove-RuleIfPresent -Name $discoveryRuleName
  Remove-RuleIfPresent -Name $rtspRuleName
  Write-Host "Removed PhoneCam firewall rules if present."
  exit 0
}

$receiverPath = Resolve-ExistingFile $Receiver

Remove-RuleIfPresent -Name $discoveryRuleName
Remove-RuleIfPresent -Name $rtspRuleName

New-NetFirewallRule `
  -Name $discoveryRuleName `
  -DisplayName $discoveryRuleName `
  -Direction Inbound `
  -Action Allow `
  -Program $receiverPath `
  -Protocol UDP `
  -LocalPort 47821 `
  -Profile Private | Out-Null

New-NetFirewallRule `
  -Name $rtspRuleName `
  -DisplayName $rtspRuleName `
  -Direction Outbound `
  -Action Allow `
  -Program $receiverPath `
  -Protocol TCP `
  -RemotePort 8554 `
  -Profile Private | Out-Null

Write-Host "Installed PhoneCam firewall rules for private networks."
Write-Host "Receiver: $receiverPath"
Write-Host "Discovery: inbound UDP 47821"
Write-Host "RTSP: outbound TCP 8554"
