param(
  [Parameter(Mandatory = $true)]
  [string]$AndroidMatrix,
  [string]$Receiver = ".\bin\phonecam-receiver.exe",
  [string]$SoftcamRoot = ".",
  [string]$Ffmpeg = ".\bin\ffmpeg.exe",
  [string]$CameraName = "PhoneCam Virtual Camera",
  [string]$RtspUrl = "",
  [string]$PairCode = "",
  [int]$DiscoverSeconds = 10,
  [string]$OutputDir = "",
  [switch]$InstallFirewallRules,
  [switch]$SkipPreflight,
  [switch]$PreflightOnly,
  [switch]$FinalizeOnly,
  [string]$RuntimeEvidence = "",
  [string]$ManualEvidence = "",
  [string]$BundleOutputDir = "",
  [switch]$NoBundle,
  [string]$Ruby = "ruby"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-PairCode {
  param([string]$Value)

  if (-not $Value) {
    return ""
  }

  return (([regex]::Matches($Value, "\d") | ForEach-Object { $_.Value }) -join "")
}

if ($PairCode) {
  $PairCode = Normalize-PairCode -Value $PairCode
  if ($PairCode.Length -ne 6) {
    throw "-PairCode must contain exactly six digits."
  }
}

if ($RtspUrl -and $PairCode) {
  throw "Use either -RtspUrl for manual RTSP or -PairCode for auto-discovery, not both."
}

if (-not $RtspUrl -and -not $PairCode -and -not $FinalizeOnly) {
  throw "Pass -PairCode PHONE_CODE for auto-discovery or -RtspUrl rtsp://PHONE_IP:8554/ for manual RTSP."
}

if ($SkipPreflight) {
  throw "-SkipPreflight is not supported by the final evidence collector. Run Test-PhoneCamWindowsRuntime.ps1 directly for debug-only experiments."
}

if ($PreflightOnly -and $FinalizeOnly) {
  throw "-PreflightOnly cannot be combined with -FinalizeOnly."
}

if ($PreflightOnly -and $InstallFirewallRules) {
  throw "-PreflightOnly cannot be combined with -InstallFirewallRules because preflight mode must not change firewall state."
}

if ($PreflightOnly -and ($RuntimeEvidence -or $ManualEvidence -or $BundleOutputDir)) {
  throw "-PreflightOnly cannot be combined with runtime, manual, or bundle output evidence paths."
}

if ($FinalizeOnly -and (-not $RuntimeEvidence -or -not $ManualEvidence)) {
  throw "-FinalizeOnly requires -RuntimeEvidence and -ManualEvidence."
}

if ($DiscoverSeconds -lt 1 -or $DiscoverSeconds -gt 30) {
  throw "-DiscoverSeconds must be between 1 and 30."
}

function Resolve-RequiredFile {
  param(
    [string]$Path,
    [string]$Label
  )

  if (-not (Test-Path $Path -PathType Leaf)) {
    throw "$Label not found: $Path"
  }
  return (Resolve-Path $Path).Path
}

function Resolve-ExternalCommand {
  param(
    [string]$Command,
    [string]$Label
  )

  if (-not $Command) {
    throw "$Label command is required."
  }

  if (Test-Path $Command -PathType Leaf) {
    return (Resolve-Path $Command).Path
  }

  $resolved = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $resolved) {
    throw "$Label command not found: $Command. Install $Label or pass -$Label with the full executable path."
  }
  return $resolved.Source
}

function Find-CompanionScript {
  param([string]$Name)

  $scriptRoot = Split-Path -Parent $PSCommandPath
  $candidates = New-Object System.Collections.Generic.List[string]
  $candidates.Add((Join-Path $scriptRoot $Name)) | Out-Null

  $cursor = $scriptRoot
  for ($i = 0; $i -lt 5; $i++) {
    $candidates.Add((Join-Path (Join-Path $cursor "scripts") $Name)) | Out-Null
    $parent = Split-Path -Parent $cursor
    if (-not $parent -or $parent -eq $cursor) {
      break
    }
    $cursor = $parent
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate -PathType Leaf) {
      return (Resolve-Path $candidate).Path
    }
  }

  throw "Companion script not found: $Name"
}

function Invoke-External {
  param(
    [string]$Label,
    [string]$Command,
    [string[]]$Arguments
  )

  Write-Host ""
  Write-Host "== $Label =="
  Write-Host "$Command $($Arguments -join ' ')"
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE"
  }
}

function Resolve-PowerShellExecutable {
  $exeName = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }
  $homeCandidate = Join-Path $PSHOME $exeName
  if (Test-Path $homeCandidate -PathType Leaf) {
    return (Resolve-Path $homeCandidate).Path
  }

  foreach ($candidate in @("pwsh", "powershell")) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  throw "Could not find pwsh or powershell for child verification scripts."
}

function Resolve-EvidencePath {
  param(
    [string]$Path,
    [string]$BaseDir
  )

  if (-not $Path) {
    return ""
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return (Join-Path $BaseDir $Path)
}

function Get-JsonPropertyValue {
  param(
    [object]$Object,
    [string]$Name
  )

  if (-not $Object -or -not $Object.PSObject.Properties[$Name]) {
    return $null
  }
  return $Object.PSObject.Properties[$Name].Value
}

function Get-CanonicalRtspEndpoint {
  param([string]$Url)

  if (-not $Url) {
    return ""
  }

  try {
    $uri = [System.Uri]$Url
    if ($uri.Scheme -ne "rtsp" -or -not $uri.Host) {
      return ""
    }
    $port = if ($uri.Port -gt 0) { $uri.Port } else { 554 }
    $path = $uri.AbsolutePath
    if (-not $path) {
      $path = "/"
    }
    return "$($uri.Host.ToLowerInvariant()):$port$path"
  } catch {
    return ""
  }
}

function Add-AndroidMatrixRtspEndpoint {
  param(
    [System.Collections.Generic.HashSet[string]]$Endpoints,
    [string]$Url
  )

  $endpoint = Get-CanonicalRtspEndpoint -Url $Url
  if ($endpoint) {
    $Endpoints.Add($endpoint) | Out-Null
  }
}

function Get-AndroidMatrixRtspEndpoints {
  param([string]$Path)

  $matrixBaseDir = Split-Path -Parent $Path
  $matrix = Get-Content -Raw -Path $Path | ConvertFrom-Json
  $endpoints = [System.Collections.Generic.HashSet[string]]::new()

  foreach ($profile in @($matrix.profiles)) {
    Add-AndroidMatrixRtspEndpoint -Endpoints $endpoints -Url ([string](Get-JsonPropertyValue -Object $profile -Name "rtspUrl"))

    $evidenceJson = Get-JsonPropertyValue -Object $profile -Name "evidenceJson"
    if ($evidenceJson) {
      $profileEvidencePath = Resolve-EvidencePath -Path ([string]$evidenceJson) -BaseDir $matrixBaseDir
      if (Test-Path $profileEvidencePath -PathType Leaf) {
        $profileEvidence = Get-Content -Raw -Path $profileEvidencePath | ConvertFrom-Json
        Add-AndroidMatrixRtspEndpoint -Endpoints $endpoints -Url ([string](Get-JsonPropertyValue -Object $profileEvidence -Name "rtspUrl"))

        $directDecode = Get-JsonPropertyValue -Object $profileEvidence -Name "directDecode"
        Add-AndroidMatrixRtspEndpoint -Endpoints $endpoints -Url ([string](Get-JsonPropertyValue -Object $directDecode -Name "openedRtspUrl"))

        $discoveryDecode = Get-JsonPropertyValue -Object $profileEvidence -Name "pairCodeDiscoveryDecode"
        Add-AndroidMatrixRtspEndpoint -Endpoints $endpoints -Url ([string](Get-JsonPropertyValue -Object $discoveryDecode -Name "selectedRtspUrl"))
        Add-AndroidMatrixRtspEndpoint -Endpoints $endpoints -Url ([string](Get-JsonPropertyValue -Object $discoveryDecode -Name "openedRtspUrl"))

        $frontCamera = Get-JsonPropertyValue -Object $profileEvidence -Name "frontCamera"
        Add-AndroidMatrixRtspEndpoint -Endpoints $endpoints -Url ([string](Get-JsonPropertyValue -Object $frontCamera -Name "openedRtspUrl"))
      }
    }
  }

  return @($endpoints | Sort-Object)
}

function Get-AndroidMatrixPairingCode {
  param([string]$Path)

  $matrixBaseDir = Split-Path -Parent $Path
  $matrix = Get-Content -Raw -Path $Path | ConvertFrom-Json
  $codes = New-Object System.Collections.Generic.List[string]

  foreach ($profile in @($matrix.profiles)) {
    if ($profile.pairingCode) {
      $codes.Add([string]$profile.pairingCode) | Out-Null
    }

    if ($profile.evidenceJson) {
      $profileEvidencePath = Resolve-EvidencePath -Path ([string]$profile.evidenceJson) -BaseDir $matrixBaseDir
      if (Test-Path $profileEvidencePath -PathType Leaf) {
        $profileEvidence = Get-Content -Raw -Path $profileEvidencePath | ConvertFrom-Json
        if ($profileEvidence.pairingCode) {
          $codes.Add([string]$profileEvidence.pairingCode) | Out-Null
        }
      }
    }
  }

  $uniqueCodes = @($codes | Where-Object { $_ -match '^\d{6}$' } | Sort-Object -Unique)
  if ($uniqueCodes.Count -ne 1) {
    throw "Android matrix must expose one stable six-digit pairing code for Windows auto-discovery."
  }

  return $uniqueCodes[0]
}

$runtimeScript = Find-CompanionScript "Test-PhoneCamWindowsRuntime.ps1"
$firewallScript = Find-CompanionScript "Install-PhoneCamFirewallRules.ps1"
$validatorScript = Find-CompanionScript "validate_mvp_evidence.rb"
$bundlerScript = Find-CompanionScript "bundle_mvp_evidence.rb"
$androidMatrixPath = Resolve-RequiredFile -Path $AndroidMatrix -Label "Android matrix evidence"
$powershellExe = Resolve-PowerShellExecutable
$rubyExe = Resolve-ExternalCommand -Command $Ruby -Label "Ruby"

if (-not $OutputDir) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "phonecam-windows-mvp-$stamp"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

Invoke-External -Label "Android matrix evidence preflight" -Command $rubyExe -Arguments @(
  $validatorScript,
  "--android-matrix", $androidMatrixPath,
  "--android-only"
)

if (-not $FinalizeOnly -and $PairCode) {
  $androidMatrixPairingCode = Get-AndroidMatrixPairingCode -Path $androidMatrixPath
  if ($PairCode -ne $androidMatrixPairingCode) {
    throw "PairCode $PairCode does not match Android matrix pairing code $androidMatrixPairingCode."
  }
}

if (-not $FinalizeOnly -and $RtspUrl) {
  $rtspEndpoint = Get-CanonicalRtspEndpoint -Url $RtspUrl
  if (-not $rtspEndpoint) {
    throw "-RtspUrl must be an rtsp:// URL with a host."
  }

  $androidMatrixRtspEndpoints = @(Get-AndroidMatrixRtspEndpoints -Path $androidMatrixPath)
  if ($androidMatrixRtspEndpoints.Count -eq 0) {
    throw "Android matrix must expose at least one RTSP URL for Windows manual RTSP preflight."
  }
  if ($androidMatrixRtspEndpoints -notcontains $rtspEndpoint) {
    throw "RtspUrl $RtspUrl does not match any Android matrix RTSP URL."
  }
}

if ($FinalizeOnly) {
  $runtimeEvidencePath = Resolve-RequiredFile -Path $RuntimeEvidence -Label "Windows runtime evidence"
  $manualEvidencePath = Resolve-RequiredFile -Path $ManualEvidence -Label "Windows manual evidence"

  Invoke-External -Label "Manual OBS/browser evidence validation" -Command $powershellExe -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $runtimeScript,
    "-ValidateManualEvidence", $manualEvidencePath,
    "-RuntimeEvidence", $runtimeEvidencePath
  )

  Invoke-External -Label "Final MVP evidence validation" -Command $rubyExe -Arguments @(
    $validatorScript,
    "--android-matrix", $androidMatrixPath,
    "--windows-runtime", $runtimeEvidencePath,
    "--windows-manual", $manualEvidencePath
  )

  if (-not $NoBundle) {
    if (-not $BundleOutputDir) {
      $BundleOutputDir = Join-Path (Split-Path -Parent $runtimeEvidencePath) "PhoneCam-MVP-Evidence"
    }
    Invoke-External -Label "Portable MVP evidence bundle" -Command $rubyExe -Arguments @(
      $bundlerScript,
      "--android-matrix", $androidMatrixPath,
      "--windows-runtime", $runtimeEvidencePath,
      "--windows-manual", $manualEvidencePath,
      "--output-dir", $BundleOutputDir,
      "--force"
    )
  }

  Write-Host ""
  Write-Host "PhoneCam MVP evidence finalized."
  exit 0
}

$sourceArgs = @()
if ($RtspUrl) {
  $sourceArgs += @("-RtspUrl", $RtspUrl)
} else {
  $sourceArgs += @("-AutoDiscover", "-PairCode", $PairCode, "-DiscoverSeconds", $DiscoverSeconds.ToString())
}

if (-not $SkipPreflight) {
  Invoke-External -Label "Windows runtime preflight" -Command $powershellExe -Arguments (@(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $runtimeScript,
    "-Receiver", $Receiver,
    "-SoftcamRoot", $SoftcamRoot,
    "-Ffmpeg", $Ffmpeg,
    "-CameraName", $CameraName,
    "-Register",
    "-KeepReceiverRunning",
    "-OutputDir", $OutputDir,
    "-PreflightOnly"
  ) + $sourceArgs)
}

if ($PreflightOnly) {
  Write-Host ""
  Write-Host "PhoneCam Windows evidence preflight passed."
  Write-Host "Preflight output directory: $OutputDir"
  Write-Host "Preflight summary: $(Join-Path $OutputDir "windows-preflight-summary.txt")"
  Write-Host "Preflight evidence: $(Join-Path $OutputDir "windows-preflight-evidence.json")"
  Write-Host "No DirectShow capture, OBS/browser enumeration, firewall changes, or final MVP bundle were attempted."
  exit 0
}

if ($InstallFirewallRules) {
  Invoke-External -Label "Windows firewall rule setup" -Command $powershellExe -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $firewallScript,
    "-Receiver", $Receiver
  )
}

Invoke-External -Label "Windows Android-to-DirectShow runtime evidence" -Command $powershellExe -Arguments (@(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $runtimeScript,
  "-Receiver", $Receiver,
  "-SoftcamRoot", $SoftcamRoot,
  "-Ffmpeg", $Ffmpeg,
  "-CameraName", $CameraName,
  "-Register",
  "-KeepReceiverRunning",
  "-OutputDir", $OutputDir
) + $sourceArgs)

$runtimeEvidencePath = Join-Path $OutputDir "runtime-evidence.json"
$manualEvidencePath = Join-Path $OutputDir "manual-app-evidence-template.json"
$manualChecklistPath = Join-Path $OutputDir "manual-app-enumeration-checklist.txt"

Write-Host ""
Write-Host "Runtime evidence captured. Keep the receiver running while completing OBS/browser checks."
Write-Host "Runtime evidence: $runtimeEvidencePath"
Write-Host "Manual evidence template: $manualEvidencePath"
Write-Host "Manual checklist: $manualChecklistPath"
Write-Host ""
Write-Host "After inspecting the DirectShow snapshot, setting directShowFrameMatchesExpectedAndroidStream/directShowFrameReviewNote, and adding screenshotPath files, run:"
$rubyFinalizeArg = if ($Ruby -ne "ruby") { " -Ruby `"$Ruby`"" } else { "" }
Write-Host "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -FinalizeOnly -AndroidMatrix `"$androidMatrixPath`" -RuntimeEvidence `"$runtimeEvidencePath`" -ManualEvidence `"$manualEvidencePath`"$rubyFinalizeArg"
