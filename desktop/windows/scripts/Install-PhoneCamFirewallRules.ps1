param(
  [string]$Receiver = ".\bin\phonecam-receiver.exe",
  [string]$RulePrefix = "PhoneCam",
  [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$rules = @(
  @{ Name = "$RulePrefix Receiver Discovery UDP"; Direction = "Inbound"; Protocol = "UDP"; LocalPort = 47821 },
  @{ Name = "$RulePrefix Receiver RTSP TCP Out"; Direction = "Outbound"; Protocol = "TCP"; RemotePort = 8554 },
  @{ Name = "$RulePrefix Receiver Phone TCP In"; Direction = "Inbound"; Protocol = "TCP"; LocalPort = 47823 },
  @{ Name = "$RulePrefix Receiver Media UDP In"; Direction = "Inbound"; Protocol = "UDP"; LocalPort = 5004 },
  @{ Name = "$RulePrefix Receiver Control TCP Out"; Direction = "Outbound"; Protocol = "TCP"; RemotePort = 47822 },
  @{ Name = "$RulePrefix Receiver Bonjour UDP In"; Direction = "Inbound"; Protocol = "UDP"; LocalPort = 5353 },
  @{ Name = "$RulePrefix Receiver Bonjour UDP Out"; Direction = "Outbound"; Protocol = "UDP"; RemotePort = 5353 }
)

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
  foreach ($rule in $rules) { Remove-RuleIfPresent -Name $rule.Name }
  Write-Host "Removed PhoneCam firewall rules if present."
  exit 0
}

$receiverPath = Resolve-ExistingFile $Receiver
foreach ($rule in $rules) {
  Remove-RuleIfPresent -Name $rule.Name
  New-NetFirewallRule @rule -DisplayName $rule.Name -Action Allow -Program $receiverPath -Profile Private | Out-Null
}
Write-Host "Installed PhoneCam firewall rules for private networks."
Write-Host "Receiver: $receiverPath"
Write-Host "Phone connection: inbound TCP 47823. Discovery: mDNS UDP 5353 and legacy UDP 47821."
Write-Host "Advanced: inbound UDP 5004, outbound TCP 47822 and RTSP TCP 8554."
