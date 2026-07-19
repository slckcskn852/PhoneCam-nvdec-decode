param(
  [string]$Receiver = ".\build\windows-softcam-receiver\Release\phonecam-receiver.exe",
  [string]$SoftcamRoot = "C:\deps\phonecam-softcam",
  [string]$Ffmpeg = "ffmpeg.exe",
  [string]$CameraName = "PhoneCam Virtual Camera",
  [string]$RtspUrl = "",
  [switch]$AutoDiscover,
  [string]$PairCode = "",
  [int]$DiscoverSeconds = 8,
  [int]$Fps = 30,
  [int]$SelfTestFrames = 600,
  [int]$CaptureSeconds = 3,
  [int]$CaptureFrames = 30,
  [int]$CaptureWidth = 0,
  [int]$CaptureHeight = 0,
  [string]$OutputDir = "",
  [switch]$Register,
  [switch]$UnregisterAfter,
  [switch]$UnregisterOnly,
  [switch]$KeepReceiverRunning,
  [switch]$SkipCapture,
  [switch]$PreflightOnly,
  [string]$ValidateManualEvidence = "",
  [string]$RuntimeEvidence = ""
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

if ($RtspUrl -and $AutoDiscover) {
  throw "Use either -RtspUrl or -AutoDiscover, not both."
}

if ($PairCode -and -not $AutoDiscover) {
  throw "-PairCode is only valid with -AutoDiscover."
}

if ($DiscoverSeconds -lt 1 -or $DiscoverSeconds -gt 30) {
  throw "-DiscoverSeconds must be between 1 and 30."
}

if ($Fps -lt 1 -or $Fps -gt 240) {
  throw "-Fps must be between 1 and 240."
}

if ($KeepReceiverRunning -and $UnregisterAfter) {
  throw "Use either -KeepReceiverRunning or -UnregisterAfter, not both."
}

if ($KeepReceiverRunning -and $SkipCapture) {
  throw "-KeepReceiverRunning cannot be combined with -SkipCapture because OBS/browser evidence must be tied to a DirectShow capture and frame snapshot."
}

if ($UnregisterOnly -and ($Register -or $UnregisterAfter -or $KeepReceiverRunning -or $RtspUrl -or $AutoDiscover -or $PairCode)) {
  throw "-UnregisterOnly cannot be combined with registration, receiver, discovery, or RTSP options."
}

if ($PreflightOnly -and ($UnregisterOnly -or $ValidateManualEvidence -or $RuntimeEvidence)) {
  throw "-PreflightOnly cannot be combined with unregister-only or manual-evidence validation options."
}

if ($ValidateManualEvidence -and ($Register -or $UnregisterAfter -or $UnregisterOnly -or $KeepReceiverRunning -or $RtspUrl -or $AutoDiscover -or $PairCode)) {
  throw "-ValidateManualEvidence cannot be combined with registration, receiver, discovery, RTSP, or cleanup options."
}

if ($RuntimeEvidence -and -not $ValidateManualEvidence) {
  throw "-RuntimeEvidence is only valid with -ValidateManualEvidence."
}

if ($KeepReceiverRunning -and -not $RtspUrl -and -not $AutoDiscover) {
  throw "-KeepReceiverRunning requires -RtspUrl or -AutoDiscover so the receiver has a continuous source for OBS/browser checks."
}

function Resolve-CommandPath {
  param([string]$Command)

  if (Test-Path $Command -PathType Leaf) {
    return (Resolve-Path $Command).Path
  }

  $resolved = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $resolved) {
    throw "Command not found: $Command"
  }
  return $resolved.Source
}

function Resolve-ExistingDirectory {
  param([string]$Path)

  if (-not (Test-Path $Path -PathType Container)) {
    throw "Directory not found: $Path"
  }
  return (Resolve-Path $Path).Path
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Regsvr32Path {
  $candidates = @(
    (Join-Path $env:WINDIR "System32\regsvr32.exe"),
    (Join-Path $env:WINDIR "Sysnative\regsvr32.exe")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "regsvr32.exe was not found."
}

function Find-SoftcamInstaller {
  param([string]$Root)

  $rootPath = Resolve-ExistingDirectory $Root
  $preferred = Get-ChildItem -Path $rootPath -Recurse -Filter "softcam_installer.exe" |
    Where-Object { $_.FullName -match "\\examples\\softcam_installer\\x64\\Release\\" } |
    Sort-Object FullName |
    Select-Object -First 1

  if ($preferred) {
    return $preferred.FullName
  }

  $packaged = Get-ChildItem -Path $rootPath -Recurse -Filter "softcam_installer.exe" |
    Where-Object { $_.FullName -match "\\bin\\softcam_installer\.exe$" } |
    Sort-Object FullName |
    Select-Object -First 1

  if ($packaged) {
    return $packaged.FullName
  }

  return ""
}

function Find-FirstFile {
  param(
    [string]$Root,
    [string]$Filter,
    [string]$PathRegex
  )

  if (-not (Test-Path $Root)) {
    throw "Path not found: $Root"
  }

  $match = Get-ChildItem -Path $Root -Recurse -Filter $Filter |
    Where-Object { $_.FullName -match $PathRegex } |
    Sort-Object FullName |
    Select-Object -First 1

  if (-not $match) {
    throw "$Filter not found under $Root with path regex $PathRegex"
  }

  return $match.FullName
}

function Find-SoftcamDll {
  param([string]$Root)

  $rootPath = Resolve-ExistingDirectory $Root
  $preferred = Get-ChildItem -Path $rootPath -Recurse -Filter "softcam.dll" |
    Where-Object { $_.FullName -match "\\dist\\bin\\x64\\" } |
    Sort-Object FullName |
    Select-Object -First 1

  if ($preferred) {
    return $preferred.FullName
  }

  $packaged = Get-ChildItem -Path $rootPath -Recurse -Filter "softcam.dll" |
    Where-Object { $_.FullName -match "\\bin\\softcam\.dll$" } |
    Sort-Object FullName |
    Select-Object -First 1

  if ($packaged) {
    return $packaged.FullName
  }

  throw "softcam.dll not found under $rootPath."
}

function Invoke-Regsvr32 {
  param(
    [string]$DllPath,
    [switch]$Unregister
  )

  if (-not (Test-IsAdministrator)) {
    throw "Registering or unregistering Softcam requires an elevated PowerShell session."
  }

  $regsvr32 = Get-Regsvr32Path
  $args = @("/s")
  if ($Unregister) {
    $args += "/u"
  }
  $args += $DllPath

  & $regsvr32 @args
  if ($LASTEXITCODE -ne 0) {
    $action = if ($Unregister) { "unregister" } else { "register" }
    throw "regsvr32 failed to $action $DllPath with exit code $LASTEXITCODE"
  }
}

function Invoke-SoftcamRegistration {
  param(
    [string]$InstallerPath,
    [string]$DllPath,
    [switch]$Unregister
  )

  if (-not (Test-IsAdministrator)) {
    throw "Registering or unregistering Softcam requires an elevated PowerShell session."
  }

  if ($InstallerPath) {
    $action = if ($Unregister) { "unregister" } else { "register" }
    & $InstallerPath $action $DllPath
    if ($LASTEXITCODE -ne 0) {
      throw "softcam_installer.exe failed to $action $DllPath with exit code $LASTEXITCODE"
    }
    return
  }

  Invoke-Regsvr32 -DllPath $DllPath -Unregister:$Unregister
}

function Stop-IfRunning {
  param([System.Diagnostics.Process]$Process)

  if ($Process -and -not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    $Process.WaitForExit(5000) | Out-Null
  }
}

function Write-RuntimeEvidence {
  param(
    [string]$Path,
    [string]$Status,
    [string]$Mode,
    [string]$FailureMessage = "",
    [System.Collections.IDictionary]$Details = $null
  )

  $evidence = [ordered]@{
    status = $Status
    generatedAt = (Get-Date -Format o)
    mode = $Mode
  }

  if ($FailureMessage) {
    $evidence["failure"] = $FailureMessage
  }

  if ($Details) {
    foreach ($key in $Details.Keys) {
      $evidence[$key] = $Details[$key]
    }
  }

  $evidence | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
}

function Get-ReceiverRtspUrls {
  param([string]$Path)

  $urls = [ordered]@{
    selectedRtspUrl = $null
    openedRtspUrl = $null
  }

  if (-not (Test-Path $Path -PathType Leaf)) {
    return $urls
  }

  $text = Get-Content -Raw -Path $Path -ErrorAction SilentlyContinue
  if (-not $text) {
    return $urls
  }

  if ($text -match "(?m)^Auto-discovery selected:\s+(rtsp://\S+)") {
    $urls["selectedRtspUrl"] = $Matches[1]
  } elseif ($text -match "(?m)^Auto-discovery self-test selected:\s+(rtsp://\S+)") {
    $urls["selectedRtspUrl"] = $Matches[1]
  }

  if ($text -match "(?m)^Opening\s+(rtsp://\S+)\s+with RTSP-over-TCP") {
    $urls["openedRtspUrl"] = $Matches[1]
  }

  return $urls
}

function Get-MaxFfmpegFrameCount {
  param([string]$Text)

  if (-not $Text) {
    return $null
  }

  $maxFrameCount = 0
  foreach ($match in [regex]::Matches($Text, "frame=\s*([0-9]+)")) {
    $frameCount = [int]$match.Groups[1].Value
    if ($frameCount -gt $maxFrameCount) {
      $maxFrameCount = $frameCount
    }
  }

  if ($maxFrameCount -gt 0) {
    return $maxFrameCount
  }
  return $null
}

function Select-EffectiveRtspUrl {
  param(
    [string]$SelectedRtspUrl,
    [string]$OpenedRtspUrl,
    [string]$SuppliedRtspUrl
  )

  if ($SelectedRtspUrl) {
    return $SelectedRtspUrl
  }
  if ($OpenedRtspUrl) {
    return $OpenedRtspUrl
  }
  if ($SuppliedRtspUrl) {
    return $SuppliedRtspUrl
  }
  return $null
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

function Assert-ReceiverRtspEvidence {
  param(
    [string]$SourceMode,
    [string]$SelectedRtspUrl,
    [string]$OpenedRtspUrl,
    [string]$SuppliedRtspUrl,
    [string]$ReceiverLog
  )

  if ($SourceMode -eq "generated self-test") {
    return
  }

  if (-not $OpenedRtspUrl) {
    throw "Receiver stdout did not record openedRtspUrl for $SourceMode. Logs: $ReceiverLog"
  }

  if ($SourceMode -eq "auto-discovered Android RTSP" -and -not $SelectedRtspUrl) {
    throw "Receiver stdout did not record selectedRtspUrl for auto-discovered Android RTSP. Logs: $ReceiverLog"
  }

  $endpoints = @()
  foreach ($url in @($SelectedRtspUrl, $OpenedRtspUrl, $SuppliedRtspUrl)) {
    if ($url) {
      $endpoint = Get-CanonicalRtspEndpoint -Url $url
      if (-not $endpoint) {
        throw "Receiver RTSP evidence contains an invalid RTSP URL: $url"
      }
      $endpoints += $endpoint
    }
  }

  $uniqueEndpoints = @($endpoints | Sort-Object -Unique)
  if ($uniqueEndpoints.Count -gt 1) {
    throw "Receiver RTSP evidence fields point to different endpoints. Logs: $ReceiverLog"
  }
}

function Get-EvidenceString {
  param(
    [object]$Evidence,
    [string]$Name
  )

  if (-not $Evidence -or -not $Evidence.PSObject.Properties[$Name]) {
    return ""
  }

  $value = $Evidence.PSObject.Properties[$Name].Value
  if ($value -is [string]) {
    return $value.Trim()
  }

  return ""
}

function Get-EvidenceRtspUrl {
  param([object]$Evidence)

  foreach ($name in @("effectiveRtspUrl", "selectedRtspUrl", "openedRtspUrl", "rtspUrl")) {
    $value = Get-EvidenceString -Evidence $Evidence -Name $name
    if ($value) {
      return $value
    }
  }

  return ""
}

function Add-ValidationIssue {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$Message
  )

  $Issues.Add($Message) | Out-Null
}

function Test-RequiredString {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [object]$Value,
    [string]$Name
  )

  if (-not ($Value -is [string]) -or -not $Value.Trim()) {
    Add-ValidationIssue -Issues $Issues -Message "$Name must be a non-empty string."
  }
}

function Test-RequiredTrue {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [object]$Value,
    [string]$Name
  )

  if ($Value -ne $true) {
    Add-ValidationIssue -Issues $Issues -Message "$Name must be true."
  }
}

function Test-RequiredPositiveInteger {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [object]$Value,
    [string]$Name
  )

  $isInteger = $Value -is [int] -or $Value -is [long]
  if (-not $isInteger -or [int64]$Value -le 0) {
    Add-ValidationIssue -Issues $Issues -Message "$Name must be a positive integer."
  }
}

function Resolve-EvidenceFilePath {
  param(
    [string]$EvidenceRoot,
    [string]$Path
  )

  if (-not $Path) {
    return ""
  }
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path $EvidenceRoot $Path)
}

function Test-RequiredEvidenceFile {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$EvidenceRoot,
    [object]$Value,
    [object]$FallbackValue,
    [string]$Name
  )

  $pathValue = ""
  if ($Value -is [string] -and $Value.Trim()) {
    $pathValue = $Value.Trim()
  } elseif ($FallbackValue -is [string] -and $FallbackValue.Trim()) {
    $pathValue = $FallbackValue.Trim()
  }

  if (-not $pathValue) {
    Add-ValidationIssue -Issues $Issues -Message "$Name screenshotPath must be a non-empty string."
    return ""
  }

  $resolvedPath = Resolve-EvidenceFilePath -EvidenceRoot $EvidenceRoot -Path $pathValue
  if (-not (Test-Path $resolvedPath -PathType Leaf)) {
    Add-ValidationIssue -Issues $Issues -Message "$Name screenshotPath file must exist: $pathValue"
    return ""
  }

  $file = Get-Item -Path $resolvedPath -ErrorAction SilentlyContinue
  if (-not $file -or $file.Length -le 0) {
    Add-ValidationIssue -Issues $Issues -Message "$Name screenshotPath file must be non-empty: $pathValue"
    return ""
  }

  return (Resolve-Path $resolvedPath).Path
}

function Test-RequiredEvidencePath {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$EvidenceRoot,
    [object]$Value,
    [string]$Name
  )

  if (-not ($Value -is [string]) -or -not $Value.Trim()) {
    Add-ValidationIssue -Issues $Issues -Message "$Name path must be a non-empty string."
    return ""
  }

  $pathValue = $Value.Trim()
  $resolvedPath = Resolve-EvidenceFilePath -EvidenceRoot $EvidenceRoot -Path $pathValue
  if (-not (Test-Path $resolvedPath -PathType Leaf)) {
    Add-ValidationIssue -Issues $Issues -Message "$Name file must exist: $pathValue"
    return ""
  }

  $file = Get-Item -Path $resolvedPath -ErrorAction SilentlyContinue
  if (-not $file -or $file.Length -le 0) {
    Add-ValidationIssue -Issues $Issues -Message "$Name file must be non-empty: $pathValue"
    return ""
  }

  return (Resolve-Path $resolvedPath).Path
}

function Test-EvidenceImageFile {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$Path,
    [string]$Name
  )

  if (-not $Path) {
    return
  }

  try {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $isPng = $bytes.Length -ge 8 -and
      $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47 -and
      $bytes[4] -eq 0x0D -and $bytes[5] -eq 0x0A -and $bytes[6] -eq 0x1A -and $bytes[7] -eq 0x0A
    $isJpeg = $bytes.Length -ge 3 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF
    $isBmp = $bytes.Length -ge 2 -and $bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D
    if (-not ($isPng -or $isJpeg -or $isBmp)) {
      Add-ValidationIssue -Issues $Issues -Message "$Name file must be a PNG, JPEG, or BMP image."
    }
  } catch {
    Add-ValidationIssue -Issues $Issues -Message "$Name file could not be read as image evidence: $($_.Exception.Message)"
  }
}

function Get-EvidenceFileHash {
  param(
    [string]$Path
  )

  if (-not $Path -or -not (Test-Path $Path -PathType Leaf)) {
    return ""
  }

  try {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
  } catch {
    return ""
  }
}

function Get-EvidencePropertyValue {
  param(
    [object]$Evidence,
    [string]$Name
  )

  if (-not $Evidence -or -not $Evidence.PSObject.Properties[$Name]) {
    return $null
  }

  return $Evidence.PSObject.Properties[$Name].Value
}

function Test-MatchingRuntimeArtifact {
  param(
    [System.Collections.Generic.List[string]]$Issues,
    [string]$ManualEvidenceRoot,
    [string]$RuntimeEvidenceRoot,
    [object]$ManualRuntimeArtifacts,
    [object]$RuntimeContainer,
    [string]$ManualName,
    [string]$RuntimeName
  )

  $manualValue = Get-EvidencePropertyValue -Evidence $ManualRuntimeArtifacts -Name $ManualName
  $runtimeValue = Get-EvidencePropertyValue -Evidence $RuntimeContainer -Name $RuntimeName
  $manualPath = Test-RequiredEvidencePath -Issues $Issues -EvidenceRoot $ManualEvidenceRoot -Value $manualValue -Name "runtimeArtifacts.$ManualName"
  $runtimePath = Test-RequiredEvidencePath -Issues $Issues -EvidenceRoot $RuntimeEvidenceRoot -Value $runtimeValue -Name "runtime $RuntimeName"
  if ($manualPath -and $runtimePath -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($manualPath, $runtimePath)) {
    Add-ValidationIssue -Issues $Issues -Message "runtimeArtifacts.$ManualName must match runtime evidence."
  }
}

function Test-ManualAppEvidence {
  param(
    [string]$Path,
    [string]$RuntimeEvidencePath = ""
  )

  if (-not (Test-Path $Path -PathType Leaf)) {
    throw "Manual evidence file not found: $Path"
  }

  $evidence = Get-Content -Raw -Path $Path | ConvertFrom-Json
  $evidenceRoot = Split-Path -Parent (Resolve-Path $Path).Path
  $runtimeEvidence = $null
  if ($RuntimeEvidencePath) {
    if (-not (Test-Path $RuntimeEvidencePath -PathType Leaf)) {
      throw "Runtime evidence file not found: $RuntimeEvidencePath"
    }
    $runtimeEvidence = Get-Content -Raw -Path $RuntimeEvidencePath | ConvertFrom-Json
    $runtimeEvidenceRoot = Split-Path -Parent (Resolve-Path $RuntimeEvidencePath).Path
  }
  $issues = [System.Collections.Generic.List[string]]::new()

  Test-RequiredString -Issues $issues -Value $evidence.cameraName -Name "cameraName"
  Test-RequiredTrue -Issues $issues -Value $evidence.receiverKeptRunning -Name "receiverKeptRunning"
  Test-RequiredPositiveInteger -Issues $issues -Value $evidence.receiverProcessId -Name "receiverProcessId"
  Test-RequiredTrue -Issues $issues -Value (Get-EvidencePropertyValue -Evidence $evidence -Name "directShowFrameMatchesExpectedAndroidStream") -Name "directShowFrameMatchesExpectedAndroidStream"
  Test-RequiredString -Issues $issues -Value (Get-EvidenceString -Evidence $evidence -Name "directShowFrameReviewNote") -Name "directShowFrameReviewNote"
  $manualRuntimeArtifacts = Get-EvidencePropertyValue -Evidence $evidence -Name "runtimeArtifacts"

  if ($evidence.status -ne "passed") {
    Add-ValidationIssue -Issues $issues -Message "status must be passed."
  }

  if ($runtimeEvidence) {
    $manualRtspUrl = Get-EvidenceRtspUrl -Evidence $evidence
    $runtimeRtspUrl = Get-EvidenceRtspUrl -Evidence $runtimeEvidence
    Test-RequiredString -Issues $issues -Value $manualRtspUrl -Name "manual RTSP URL"
    Test-RequiredString -Issues $issues -Value $runtimeRtspUrl -Name "runtime RTSP URL"
    if ($manualRtspUrl -and $runtimeRtspUrl -and $manualRtspUrl -ne $runtimeRtspUrl) {
      Add-ValidationIssue -Issues $issues -Message "manual RTSP URL must match runtime evidence."
    }
    $manualCameraName = Get-EvidenceString -Evidence $evidence -Name "cameraName"
    $runtimeCameraName = Get-EvidenceString -Evidence $runtimeEvidence -Name "cameraName"
    if ($runtimeCameraName -and $manualCameraName -ne $runtimeCameraName) {
      Add-ValidationIssue -Issues $issues -Message "cameraName must match runtime evidence."
    }
    $manualSourceMode = Get-EvidenceString -Evidence $evidence -Name "sourceMode"
    $runtimeSourceMode = Get-EvidenceString -Evidence $runtimeEvidence -Name "sourceMode"
    if ($runtimeSourceMode -and $manualSourceMode -ne $runtimeSourceMode) {
      Add-ValidationIssue -Issues $issues -Message "sourceMode must match runtime evidence."
    }
    $manualReceiverProcessId = $evidence.receiverProcessId
    $runtimeReceiverProcessId = $runtimeEvidence.receiverProcessId
    Test-RequiredPositiveInteger -Issues $issues -Value $runtimeReceiverProcessId -Name "runtime receiverProcessId"
    $manualReceiverProcessIdIsInteger = $manualReceiverProcessId -is [int] -or $manualReceiverProcessId -is [long]
    $runtimeReceiverProcessIdIsInteger = $runtimeReceiverProcessId -is [int] -or $runtimeReceiverProcessId -is [long]
    if ($manualReceiverProcessIdIsInteger -and $runtimeReceiverProcessIdIsInteger -and
        [int64]$manualReceiverProcessId -ne [int64]$runtimeReceiverProcessId) {
      Add-ValidationIssue -Issues $issues -Message "receiverProcessId must match runtime evidence."
    }
    $runtimeLogs = $null
    if ($runtimeEvidence.PSObject.Properties["logs"]) {
      $runtimeLogs = $runtimeEvidence.PSObject.Properties["logs"].Value
    }
    if (-not $runtimeLogs) {
      Add-ValidationIssue -Issues $issues -Message "runtime logs must be present."
    } else {
      $runtimeChecklistPathValue = $null
      $runtimeManualTemplatePathValue = $null
      if ($runtimeLogs.PSObject.Properties["manualAppChecklist"]) {
        $runtimeChecklistPathValue = $runtimeLogs.PSObject.Properties["manualAppChecklist"].Value
      }
      if ($runtimeLogs.PSObject.Properties["manualEvidenceTemplate"]) {
        $runtimeManualTemplatePathValue = $runtimeLogs.PSObject.Properties["manualEvidenceTemplate"].Value
      }
      $runtimeChecklistPath = Test-RequiredEvidencePath -Issues $issues -EvidenceRoot $runtimeEvidenceRoot -Value $runtimeChecklistPathValue -Name "runtime manualAppChecklist"
      $runtimeManualTemplatePath = Test-RequiredEvidencePath -Issues $issues -EvidenceRoot $runtimeEvidenceRoot -Value $runtimeManualTemplatePathValue -Name "runtime manualEvidenceTemplate"
      $manualEvidencePath = (Resolve-Path $Path).Path
      if ($runtimeManualTemplatePath -and -not [System.StringComparer]::OrdinalIgnoreCase.Equals($runtimeManualTemplatePath, $manualEvidencePath)) {
        Add-ValidationIssue -Issues $issues -Message "manualEvidenceTemplate must match runtime evidence."
      }
      if (-not $manualRuntimeArtifacts) {
        Add-ValidationIssue -Issues $issues -Message "runtimeArtifacts must be present."
      } else {
        $runtimeCapture = Get-EvidencePropertyValue -Evidence $runtimeEvidence -Name "capture"
        Test-MatchingRuntimeArtifact -Issues $issues -ManualEvidenceRoot $evidenceRoot -RuntimeEvidenceRoot $runtimeEvidenceRoot -ManualRuntimeArtifacts $manualRuntimeArtifacts -RuntimeContainer $runtimeCapture -ManualName "directShowFrameSnapshot" -RuntimeName "snapshot"
        Test-MatchingRuntimeArtifact -Issues $issues -ManualEvidenceRoot $evidenceRoot -RuntimeEvidenceRoot $runtimeEvidenceRoot -ManualRuntimeArtifacts $manualRuntimeArtifacts -RuntimeContainer $runtimeLogs -ManualName "directShowSnapshotLog" -RuntimeName "directShowSnapshot"
        Test-MatchingRuntimeArtifact -Issues $issues -ManualEvidenceRoot $evidenceRoot -RuntimeEvidenceRoot $runtimeEvidenceRoot -ManualRuntimeArtifacts $manualRuntimeArtifacts -RuntimeContainer $runtimeLogs -ManualName "directShowCaptureLog" -RuntimeName "capture"
      }
    }
  }

  Test-RequiredString -Issues $issues -Value $evidence.obs.version -Name "obs.version"
  Test-RequiredTrue -Issues $issues -Value $evidence.obs.cameraListed -Name "obs.cameraListed"
  Test-RequiredTrue -Issues $issues -Value $evidence.obs.liveFramesRendered -Name "obs.liveFramesRendered"
  $obsScreenshotPath = Test-RequiredEvidenceFile -Issues $issues -EvidenceRoot $evidenceRoot -Value $evidence.obs.screenshotPath -FallbackValue $evidence.obs.screenshotOrNote -Name "obs"
  Test-EvidenceImageFile -Issues $issues -Path $obsScreenshotPath -Name "obs screenshotPath"

  Test-RequiredString -Issues $issues -Value $evidence.browserOrCameraApp.app -Name "browserOrCameraApp.app"
  Test-RequiredString -Issues $issues -Value $evidence.browserOrCameraApp.version -Name "browserOrCameraApp.version"
  Test-RequiredTrue -Issues $issues -Value $evidence.browserOrCameraApp.cameraListed -Name "browserOrCameraApp.cameraListed"
  Test-RequiredTrue -Issues $issues -Value $evidence.browserOrCameraApp.liveFramesRendered -Name "browserOrCameraApp.liveFramesRendered"
  $browserScreenshotPath = Test-RequiredEvidenceFile -Issues $issues -EvidenceRoot $evidenceRoot -Value $evidence.browserOrCameraApp.screenshotPath -FallbackValue $evidence.browserOrCameraApp.screenshotOrNote -Name "browserOrCameraApp"
  Test-EvidenceImageFile -Issues $issues -Path $browserScreenshotPath -Name "browserOrCameraApp screenshotPath"

  if ($obsScreenshotPath -and $browserScreenshotPath -and
      [System.StringComparer]::OrdinalIgnoreCase.Equals($obsScreenshotPath, $browserScreenshotPath)) {
    Add-ValidationIssue -Issues $issues -Message "obs and browserOrCameraApp screenshots must be distinct files."
  }
  $obsScreenshotHash = Get-EvidenceFileHash -Path $obsScreenshotPath
  $browserScreenshotHash = Get-EvidenceFileHash -Path $browserScreenshotPath
  if ($obsScreenshotHash -and $browserScreenshotHash -and
      [System.StringComparer]::OrdinalIgnoreCase.Equals($obsScreenshotHash, $browserScreenshotHash)) {
    Add-ValidationIssue -Issues $issues -Message "obs and browserOrCameraApp screenshots must have different image content."
  }

  $directShowFrameSnapshotPath = ""
  if ($manualRuntimeArtifacts) {
    $directShowFrameSnapshotValue = Get-EvidencePropertyValue -Evidence $manualRuntimeArtifacts -Name "directShowFrameSnapshot"
    if ($directShowFrameSnapshotValue -is [string] -and $directShowFrameSnapshotValue.Trim()) {
      $directShowFrameSnapshotCandidate = Resolve-EvidenceFilePath -EvidenceRoot $evidenceRoot -Path $directShowFrameSnapshotValue.Trim()
      if (Test-Path $directShowFrameSnapshotCandidate -PathType Leaf) {
        $directShowFrameSnapshotPath = (Resolve-Path $directShowFrameSnapshotCandidate).Path
      }
    }
  }
  if ($directShowFrameSnapshotPath) {
    if ($obsScreenshotPath -and [System.StringComparer]::OrdinalIgnoreCase.Equals($obsScreenshotPath, $directShowFrameSnapshotPath)) {
      Add-ValidationIssue -Issues $issues -Message "obs screenshotPath must be a separate app screenshot, not the DirectShow frame snapshot."
    }
    if ($browserScreenshotPath -and [System.StringComparer]::OrdinalIgnoreCase.Equals($browserScreenshotPath, $directShowFrameSnapshotPath)) {
      Add-ValidationIssue -Issues $issues -Message "browserOrCameraApp screenshotPath must be a separate app screenshot, not the DirectShow frame snapshot."
    }
    $directShowFrameSnapshotHash = Get-EvidenceFileHash -Path $directShowFrameSnapshotPath
    if ($obsScreenshotHash -and $directShowFrameSnapshotHash -and
        [System.StringComparer]::OrdinalIgnoreCase.Equals($obsScreenshotHash, $directShowFrameSnapshotHash)) {
      Add-ValidationIssue -Issues $issues -Message "obs screenshotPath must not duplicate the DirectShow frame snapshot content."
    }
    if ($browserScreenshotHash -and $directShowFrameSnapshotHash -and
        [System.StringComparer]::OrdinalIgnoreCase.Equals($browserScreenshotHash, $directShowFrameSnapshotHash)) {
      Add-ValidationIssue -Issues $issues -Message "browserOrCameraApp screenshotPath must not duplicate the DirectShow frame snapshot content."
    }
  }

  if ($issues.Count -gt 0) {
    throw "Manual app evidence validation failed:`n - $($issues -join "`n - ")"
  }

  Write-Host "Manual app evidence validation passed: $Path"
}

if ($ValidateManualEvidence) {
  Test-ManualAppEvidence -Path $ValidateManualEvidence -RuntimeEvidencePath $RuntimeEvidence
  exit 0
}

if (-not $OutputDir) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "phonecam-windows-runtime-$stamp"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$receiverLog = Join-Path $OutputDir "receiver.stdout.log"
$receiverErr = Join-Path $OutputDir "receiver.stderr.log"
$devicesLog = Join-Path $OutputDir "ffmpeg-dshow-devices.log"
$captureLog = Join-Path $OutputDir "ffmpeg-capture.log"
$directShowSnapshot = Join-Path $OutputDir "directshow-frame.bmp"
$directShowSnapshotLog = Join-Path $OutputDir "ffmpeg-directshow-snapshot.log"
$summaryLog = Join-Path $OutputDir "runtime-summary.txt"
$evidenceLog = Join-Path $OutputDir "runtime-evidence.json"
$preflightSummaryLog = Join-Path $OutputDir "windows-preflight-summary.txt"
$preflightEvidenceLog = Join-Path $OutputDir "windows-preflight-evidence.json"
$manualAppChecklist = Join-Path $OutputDir "manual-app-enumeration-checklist.txt"
$manualEvidenceTemplate = Join-Path $OutputDir "manual-app-evidence-template.json"

if ($PreflightOnly) {
  $issues = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $receiverPath = $null
  $ffmpegPath = $null
  $softcamDll = $null
  $softcamInstaller = $null
  $ffmpegVersionLine = ""

  try {
    $receiverPath = Resolve-CommandPath $Receiver
  } catch {
    Add-ValidationIssue -Issues $issues -Message "Receiver not found or not executable: $Receiver"
  }

  try {
    $ffmpegPath = Resolve-CommandPath $Ffmpeg
    $ffmpegVersionOutput = & $ffmpegPath -version 2>&1
    $ffmpegVersionLine = ($ffmpegVersionOutput | Select-Object -First 1 | Out-String).Trim()
  } catch {
    Add-ValidationIssue -Issues $issues -Message "FFmpeg command could not be resolved or executed: $Ffmpeg"
  }

  try {
    $softcamDll = Find-SoftcamDll -Root $SoftcamRoot
  } catch {
    Add-ValidationIssue -Issues $issues -Message "Softcam DLL not found under SoftcamRoot: $SoftcamRoot"
  }

  try {
    $softcamInstaller = Find-SoftcamInstaller -Root $SoftcamRoot
    if (-not $softcamInstaller) {
      Add-ValidationIssue -Issues $warnings -Message "softcam_installer.exe was not found; runtime registration will fall back to regsvr32."
    }
  } catch {
    Add-ValidationIssue -Issues $warnings -Message "softcam_installer.exe lookup failed; runtime registration will fall back to regsvr32 if softcam.dll exists."
  }

  $isAdministrator = Test-IsAdministrator
  $adminRequired = [bool]($Register -or $UnregisterAfter)
  if ($adminRequired -and -not $isAdministrator) {
    Add-ValidationIssue -Issues $issues -Message "Elevated PowerShell is required for -Register or -UnregisterAfter."
  }

  $sourceMode = "generated self-test"
  if ($RtspUrl) {
    $sourceMode = "manual RTSP"
  } elseif ($AutoDiscover) {
    $sourceMode = "auto-discovered Android RTSP"
    if (-not $PairCode) {
      Add-ValidationIssue -Issues $warnings -Message "Auto-discovery preflight has no -PairCode; final MVP evidence should use the Android matrix pairing code."
    }
  }

  $preflightStatus = if ($issues.Count -eq 0) { "passed" } else { "failed" }
  $summary = @(
    "PhoneCam Windows runtime preflight $preflightStatus.",
    "Receiver: $(if ($receiverPath) { $receiverPath } else { 'not resolved' })",
    "Softcam root: $SoftcamRoot",
    "Softcam DLL: $(if ($softcamDll) { $softcamDll } else { 'not resolved' })",
    "Softcam installer: $(if ($softcamInstaller) { $softcamInstaller } else { 'not found; regsvr32 fallback' })",
    "FFmpeg: $(if ($ffmpegPath) { $ffmpegPath } else { 'not resolved' })",
    "FFmpeg version: $(if ($ffmpegVersionLine) { $ffmpegVersionLine } else { 'not resolved' })",
    "Camera name: $CameraName",
    "Source mode: $sourceMode",
    "RTSP URL: $(if ($RtspUrl) { $RtspUrl } else { 'not supplied' })",
    "Auto-discover: $AutoDiscover",
    "Pair code: $(if ($PairCode) { $PairCode } else { 'not supplied' })",
    "Register requested: $Register",
    "UnregisterAfter requested: $UnregisterAfter",
    "Admin: $isAdministrator",
    "Issues: $(if ($issues.Count -gt 0) { $issues -join '; ' } else { 'none' })",
    "Warnings: $(if ($warnings.Count -gt 0) { $warnings -join '; ' } else { 'none' })"
  )
  Set-Content -Path $preflightSummaryLog -Value $summary -Encoding UTF8

  Write-RuntimeEvidence -Path $preflightEvidenceLog -Status $preflightStatus -Mode "windows-runtime-preflight" -Details ([ordered]@{
    receiver = $receiverPath
    receiverRequested = $Receiver
    softcamRoot = $SoftcamRoot
    softcamDll = $softcamDll
    softcamInstaller = if ($softcamInstaller) { $softcamInstaller } else { $null }
    ffmpeg = $ffmpegPath
    ffmpegRequested = $Ffmpeg
    ffmpegVersion = $ffmpegVersionLine
    cameraName = $CameraName
    sourceMode = $sourceMode
    rtspUrl = if ($RtspUrl) { $RtspUrl } else { $null }
    autoDiscover = [bool]$AutoDiscover
    pairCode = if ($PairCode) { $PairCode } else { $null }
    discoverSeconds = $DiscoverSeconds
    registerRequested = [bool]$Register
    unregisterAfterRequested = [bool]$UnregisterAfter
    keepReceiverRunning = [bool]$KeepReceiverRunning
    skipCapture = [bool]$SkipCapture
    isAdministrator = [bool]$isAdministrator
    adminRequired = [bool]$adminRequired
    issues = $issues.ToArray()
    warnings = $warnings.ToArray()
    logs = [ordered]@{
      summary = $preflightSummaryLog
      evidence = $preflightEvidenceLog
    }
    doesNotProve = @(
      "DirectShow camera registration",
      "DirectShow capture",
      "OBS/browser camera enumeration",
      "Android-to-Windows runtime streaming"
    )
  })

  Write-Host "PhoneCam Windows runtime preflight $preflightStatus."
  Write-Host "Summary: $preflightSummaryLog"
  Write-Host "Evidence: $preflightEvidenceLog"
  if ($issues.Count -gt 0) {
    throw "Windows runtime preflight failed:`n - $($issues -join "`n - ")"
  }
  exit 0
}

$softcamDll = Find-SoftcamDll -Root $SoftcamRoot
$softcamInstaller = Find-SoftcamInstaller -Root $SoftcamRoot

if ($UnregisterOnly) {
  if (-not (Test-IsAdministrator)) {
    throw "Elevated PowerShell is required for -UnregisterOnly."
  }
  Write-Host "Unregistering Softcam DLL: $softcamDll"
  Invoke-SoftcamRegistration -InstallerPath $softcamInstaller -DllPath $softcamDll -Unregister
  $summary = @(
    "PhoneCam Softcam unregister completed.",
    "Softcam DLL: $softcamDll",
    "Softcam installer: $(if ($softcamInstaller) { $softcamInstaller } else { 'not found; used regsvr32 fallback' })"
  )
  Set-Content -Path $summaryLog -Value $summary -Encoding UTF8
  Write-RuntimeEvidence -Path $evidenceLog -Status "passed" -Mode "unregister-only" -Details ([ordered]@{
    cameraName = $CameraName
    softcamDll = $softcamDll
    softcamInstaller = if ($softcamInstaller) { $softcamInstaller } else { "not found; used regsvr32 fallback" }
    outputDir = $OutputDir
    logs = [ordered]@{
      summary = $summaryLog
    }
  })
  Write-Host "PhoneCam Softcam unregister completed."
  Write-Host "Summary: $summaryLog"
  Write-Host "Evidence: $evidenceLog"
  exit 0
}

$receiverPath = Resolve-CommandPath $Receiver
$ffmpegPath = Resolve-CommandPath $Ffmpeg

$receiverProcess = $null
$registeredByThisRun = $false
$sourceMode = "generated self-test"
$keepReceiverAfterSuccess = $false
$capturedFrameCount = $null
$directShowSnapshotPath = $null
$receiverArgs = @()
$receiverSelectedRtspUrl = $null
$receiverOpenedRtspUrl = $null
$effectiveRtspUrl = $null

try {
  if ($Register) {
    Write-Host "Registering Softcam DLL: $softcamDll"
    Invoke-SoftcamRegistration -InstallerPath $softcamInstaller -DllPath $softcamDll
    $registeredByThisRun = $true
  }

  if ($RtspUrl) {
    $sourceMode = "manual RTSP"
    $receiverArgs = @(
      "--rtsp", $RtspUrl,
      "--fps", $Fps.ToString(),
      "--no-preview"
    )
  } elseif ($AutoDiscover) {
    $sourceMode = "auto-discovered Android RTSP"
    $receiverArgs = @(
      "--auto-discover",
      "--discover-seconds", $DiscoverSeconds.ToString(),
      "--no-preview"
    )
    if ($PairCode) {
      $receiverArgs += @("--pair-code", $PairCode)
    }
  } else {
    $receiverArgs = @(
      "--self-test", "--frames", $SelfTestFrames.ToString(),
      "--fps", $Fps.ToString(),
      "--no-preview"
    )
  }

  if ($sourceMode -eq "generated self-test" -and ($CaptureWidth -le 0 -or $CaptureHeight -le 0)) {
    $CaptureWidth = 320
    $CaptureHeight = 240
  }

  Write-Host "Starting receiver ($sourceMode) with Softcam enabled..."
  $receiverProcess = Start-Process -FilePath $receiverPath -ArgumentList $receiverArgs `
    -RedirectStandardOutput $receiverLog -RedirectStandardError $receiverErr -PassThru

  $startupWaitSeconds = if ($AutoDiscover) { $DiscoverSeconds + 3 } else { 3 }
  Start-Sleep -Seconds $startupWaitSeconds
  if ($receiverProcess.HasExited) {
    Get-Content -Path $receiverLog, $receiverErr -ErrorAction SilentlyContinue | Write-Error
    throw "Receiver exited before DirectShow verification could run. Logs: $receiverLog, $receiverErr"
  }

  Write-Host "Listing DirectShow video devices with FFmpeg..."
  $deviceOutput = & $ffmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1
  $deviceText = $deviceOutput | Out-String
  Set-Content -Path $devicesLog -Value $deviceText

  if ($deviceText -notmatch [regex]::Escape($CameraName)) {
    throw "DirectShow device list did not contain '$CameraName'. Device log: $devicesLog"
  }

  if (-not $SkipCapture) {
    Write-Host "Capturing frames from '$CameraName' through FFmpeg..."
    $captureInput = "video=$CameraName"
    $captureArgs = @("-hide_banner", "-f", "dshow")
    if ($CaptureWidth -gt 0 -and $CaptureHeight -gt 0) {
      $captureArgs += @("-video_size", "$($CaptureWidth)x$($CaptureHeight)")
    }
    if ($Fps -gt 0) {
      $captureArgs += @("-framerate", $Fps.ToString())
    }
    $captureArgs += @("-t", $CaptureSeconds.ToString(), "-i", $captureInput, "-frames:v", $CaptureFrames.ToString(), "-f", "null", "-")
    $captureOutput = & $ffmpegPath @captureArgs 2>&1
    $captureText = $captureOutput | Out-String
    Set-Content -Path $captureLog -Value $captureText

    if ($LASTEXITCODE -ne 0) {
      throw "FFmpeg could not capture from '$CameraName'. Capture log: $captureLog"
    }
    $capturedFrameCount = Get-MaxFfmpegFrameCount -Text $captureText
    if (-not $capturedFrameCount) {
      throw "FFmpeg capture from '$CameraName' did not report captured frames. Capture log: $captureLog"
    }
    if (-not $captureText.Contains($CameraName)) {
      throw "FFmpeg capture log did not name '$CameraName'. Capture log: $captureLog"
    }
    if ($capturedFrameCount -lt $CaptureFrames) {
      throw "FFmpeg capture from '$CameraName' reported $capturedFrameCount frame(s), fewer than requested $CaptureFrames. Capture log: $captureLog"
    }

    Write-Host "Capturing one DirectShow frame snapshot from '$CameraName'..."
    $snapshotArgs = @("-hide_banner", "-y", "-f", "dshow")
    if ($CaptureWidth -gt 0 -and $CaptureHeight -gt 0) {
      $snapshotArgs += @("-video_size", "$($CaptureWidth)x$($CaptureHeight)")
    }
    if ($Fps -gt 0) {
      $snapshotArgs += @("-framerate", $Fps.ToString())
    }
    $snapshotArgs += @(
      "-i", $captureInput,
      "-t", $CaptureSeconds.ToString(),
      "-frames:v", "1",
      "-f", "image2",
      "-update", "1",
      $directShowSnapshot
    )
    $snapshotOutput = & $ffmpegPath @snapshotArgs 2>&1
    $snapshotText = $snapshotOutput | Out-String
    Set-Content -Path $directShowSnapshotLog -Value $snapshotText

    if ($LASTEXITCODE -ne 0) {
      throw "FFmpeg could not write a DirectShow frame snapshot from '$CameraName'. Snapshot log: $directShowSnapshotLog"
    }
    if (-not (Test-Path $directShowSnapshot -PathType Leaf)) {
      throw "FFmpeg DirectShow frame snapshot was not created. Snapshot log: $directShowSnapshotLog"
    }
    if ((Get-Item $directShowSnapshot).Length -le 0) {
      throw "FFmpeg DirectShow frame snapshot was empty. Snapshot path: $directShowSnapshot"
    }
    $snapshotIssues = [System.Collections.Generic.List[string]]::new()
    Test-EvidenceImageFile -Issues $snapshotIssues -Path $directShowSnapshot -Name "DirectShow frame snapshot"
    if ($snapshotIssues.Count -gt 0) {
      throw "FFmpeg DirectShow frame snapshot was not a PNG, JPEG, or BMP image. $($snapshotIssues -join ' ') Snapshot path: $directShowSnapshot"
    }
    $directShowSnapshotPath = $directShowSnapshot
  }

  $receiverRtspUrls = Get-ReceiverRtspUrls -Path $receiverLog
  $receiverSelectedRtspUrl = $receiverRtspUrls["selectedRtspUrl"]
  $receiverOpenedRtspUrl = $receiverRtspUrls["openedRtspUrl"]
  $effectiveRtspUrl = Select-EffectiveRtspUrl `
    -SelectedRtspUrl $receiverSelectedRtspUrl `
    -OpenedRtspUrl $receiverOpenedRtspUrl `
    -SuppliedRtspUrl $RtspUrl
  Assert-ReceiverRtspEvidence `
    -SourceMode $sourceMode `
    -SelectedRtspUrl $receiverSelectedRtspUrl `
    -OpenedRtspUrl $receiverOpenedRtspUrl `
    -SuppliedRtspUrl $RtspUrl `
    -ReceiverLog $receiverLog

  $summary = @(
    "PhoneCam Windows runtime verification passed.",
    "Receiver: $receiverPath",
    "Softcam DLL: $softcamDll",
    "Softcam installer: $(if ($softcamInstaller) { $softcamInstaller } else { 'not found; used regsvr32 fallback' })",
    "FFmpeg: $ffmpegPath",
    "Camera name: $CameraName",
    "Source mode: $sourceMode",
    "RTSP URL: $(if ($RtspUrl) { $RtspUrl } else { 'not supplied' })",
    "Selected RTSP URL: $(if ($receiverSelectedRtspUrl) { $receiverSelectedRtspUrl } else { 'not discovered' })",
    "Opened RTSP URL: $(if ($receiverOpenedRtspUrl) { $receiverOpenedRtspUrl } else { 'not recorded' })",
    "Effective RTSP URL: $(if ($effectiveRtspUrl) { $effectiveRtspUrl } else { 'not applicable' })",
    "Auto-discover: $AutoDiscover",
    "Pair code: $(if ($PairCode) { $PairCode } else { 'not supplied' })",
    "Receiver kept running: $KeepReceiverRunning",
    "Receiver process id: $(if ($receiverProcess -and -not $receiverProcess.HasExited) { $receiverProcess.Id } else { 'not running' })",
    "Receiver stdout: $receiverLog",
    "Receiver stderr: $receiverErr",
    "DirectShow devices: $devicesLog",
    "Capture log: $(if ($SkipCapture) { 'skipped' } else { $captureLog })",
    "DirectShow frame snapshot: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotPath })",
    "DirectShow snapshot log: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotLog })"
  )
  Set-Content -Path $summaryLog -Value $summary -Encoding UTF8

  if ($KeepReceiverRunning) {
    $manualEvidence = [ordered]@{
      status = "pending-manual-verification"
      generatedAt = (Get-Date -Format o)
      cameraName = $CameraName
      sourceMode = $sourceMode
      selectedRtspUrl = $receiverSelectedRtspUrl
      openedRtspUrl = $receiverOpenedRtspUrl
      effectiveRtspUrl = $effectiveRtspUrl
      receiverProcessId = $receiverProcess.Id
      receiverKeptRunning = $true
      directShowFrameMatchesExpectedAndroidStream = $null
      directShowFrameReviewNote = ""
      requiredChecks = @("obs", "browserOrCameraApp")
      obs = [ordered]@{
        app = "OBS Studio"
        version = ""
        cameraListed = $null
        liveFramesRendered = $null
        screenshotPath = ""
        note = ""
      }
      browserOrCameraApp = [ordered]@{
        app = ""
        version = ""
        cameraListed = $null
        liveFramesRendered = $null
        screenshotPath = ""
        note = ""
      }
      screenshotRequirements = "OBS and browser/camera-app screenshots must be separate app screenshots with different image content and cannot reuse the DirectShow frame snapshot path or content."
      cleanup = [ordered]@{
        stopReceiverProcessId = $receiverProcess.Id
        unregisterCommand = "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -SoftcamRoot `"$SoftcamRoot`" -UnregisterOnly"
      }
      runtimeArtifacts = [ordered]@{
        directShowFrameSnapshot = if ($SkipCapture) { $null } else { $directShowSnapshotPath }
        directShowSnapshotLog = if ($SkipCapture) { $null } else { $directShowSnapshotLog }
        directShowCaptureLog = if ($SkipCapture) { $null } else { $captureLog }
      }
      logs = [ordered]@{
        summary = $summaryLog
        evidence = $evidenceLog
        receiverStdout = $receiverLog
        receiverStderr = $receiverErr
        directShowDevices = $devicesLog
        capture = if ($SkipCapture) { $null } else { $captureLog }
        directShowSnapshot = if ($SkipCapture) { $null } else { $directShowSnapshotLog }
        manualAppChecklist = $manualAppChecklist
      }
    }
    $manualEvidence | ConvertTo-Json -Depth 8 | Set-Content -Path $manualEvidenceTemplate -Encoding UTF8

    $checklist = @(
      "PhoneCam manual camera-app enumeration checklist",
      "Generated: $(Get-Date -Format o)",
      "Camera name: $CameraName",
      "Source mode: $sourceMode",
      "Effective RTSP URL: $(if ($effectiveRtspUrl) { $effectiveRtspUrl } else { 'not applicable' })",
      "Receiver process id: $($receiverProcess.Id)",
      "Receiver stdout: $receiverLog",
      "Receiver stderr: $receiverErr",
      "DirectShow devices: $devicesLog",
      "FFmpeg capture log: $(if ($SkipCapture) { 'skipped' } else { $captureLog })",
      "DirectShow frame snapshot: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotPath })",
      "DirectShow snapshot log: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotLog })",
      "Manual evidence template: $manualEvidenceTemplate",
      "",
      "Manual checks to complete before stopping the receiver:",
      "1. Open OBS Studio.",
      "2. Add or edit a Video Capture Device source.",
      "3. Select '$CameraName'.",
      "4. Confirm the preview shows live PhoneCam frames.",
      "5. Record the OBS version, whether the device was listed, and whether live frames rendered.",
      "6. Open a browser or camera app that can request a webcam.",
      "7. Select '$CameraName' and confirm live frames render.",
      "8. Open the saved DirectShow frame snapshot and confirm it is a real frame from the expected Android stream: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotPath })",
      "9. Save non-empty OBS and browser/camera-app screenshots beside this evidence file. They must be distinct app screenshots with different image content and must not reuse the DirectShow frame snapshot path or content.",
      "10. Set directShowFrameMatchesExpectedAndroidStream to true and write directShowFrameReviewNote after inspecting the saved DirectShow snapshot.",
      "11. Fill manual-app-evidence-template.json with app versions, pass/fail values, and screenshotPath values.",
      "12. Set status to passed after both manual checks render live frames.",
      "13. Validate the completed manual evidence file:",
      "    powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ValidateManualEvidence `"$manualEvidenceTemplate`" -RuntimeEvidence `"$evidenceLog`"",
      "14. Stop receiver process id $($receiverProcess.Id) when done.",
      "15. If Softcam was registered for this run, unregister it after app checks are finished:",
      "    powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -SoftcamRoot `"$SoftcamRoot`" -UnregisterOnly"
    )
    Set-Content -Path $manualAppChecklist -Value $checklist -Encoding UTF8
    $keepReceiverAfterSuccess = $true
  }

  Write-RuntimeEvidence -Path $evidenceLog -Status "passed" -Mode "windows-runtime-verification" -Details ([ordered]@{
    receiver = $receiverPath
    receiverArguments = $receiverArgs
    softcamDll = $softcamDll
    softcamInstaller = if ($softcamInstaller) { $softcamInstaller } else { "not found; used regsvr32 fallback" }
    ffmpeg = $ffmpegPath
    cameraName = $CameraName
    sourceMode = $sourceMode
    rtspUrl = if ($RtspUrl) { $RtspUrl } else { $null }
    selectedRtspUrl = $receiverSelectedRtspUrl
    openedRtspUrl = $receiverOpenedRtspUrl
    effectiveRtspUrl = $effectiveRtspUrl
    autoDiscover = [bool]$AutoDiscover
    pairCode = if ($PairCode) { $PairCode } else { $null }
    discoverSeconds = $DiscoverSeconds
    directShowCameraFound = $true
    receiverKeptRunning = [bool]$KeepReceiverRunning
    receiverProcessId = if ($receiverProcess -and -not $receiverProcess.HasExited) { $receiverProcess.Id } else { $null }
    capture = [ordered]@{
      skipped = [bool]$SkipCapture
      frames = $capturedFrameCount
      requestedFrames = $CaptureFrames
      seconds = $CaptureSeconds
      width = $CaptureWidth
      height = $CaptureHeight
      fps = $Fps
      snapshot = if ($SkipCapture) { $null } else { $directShowSnapshotPath }
    }
    logs = [ordered]@{
      summary = $summaryLog
      evidence = $evidenceLog
      receiverStdout = $receiverLog
      receiverStderr = $receiverErr
      directShowDevices = $devicesLog
      capture = if ($SkipCapture) { $null } else { $captureLog }
      directShowSnapshot = if ($SkipCapture) { $null } else { $directShowSnapshotLog }
      manualAppChecklist = if ($KeepReceiverRunning) { $manualAppChecklist } else { $null }
      manualEvidenceTemplate = if ($KeepReceiverRunning) { $manualEvidenceTemplate } else { $null }
    }
  })

  Write-Host "PhoneCam Windows runtime verification passed."
  Write-Host "Logs: $OutputDir"
  Write-Host "Summary: $summaryLog"
  Write-Host "Evidence: $evidenceLog"
  if ($KeepReceiverRunning) {
    Write-Host "Receiver is still running for OBS/browser checks. Process id: $($receiverProcess.Id)"
    Write-Host "Manual app checklist: $manualAppChecklist"
  }
} catch {
  $failureMessage = $_.Exception.Message
  $receiverRtspUrls = Get-ReceiverRtspUrls -Path $receiverLog
  $receiverSelectedRtspUrl = $receiverRtspUrls["selectedRtspUrl"]
  $receiverOpenedRtspUrl = $receiverRtspUrls["openedRtspUrl"]
  $effectiveRtspUrl = Select-EffectiveRtspUrl `
    -SelectedRtspUrl $receiverSelectedRtspUrl `
    -OpenedRtspUrl $receiverOpenedRtspUrl `
    -SuppliedRtspUrl $RtspUrl
  $summary = @(
    "PhoneCam Windows runtime verification failed.",
    "Failure: $failureMessage",
    "Receiver: $(if ($receiverPath) { $receiverPath } else { 'not resolved' })",
    "Softcam DLL: $softcamDll",
    "Softcam installer: $(if ($softcamInstaller) { $softcamInstaller } else { 'not found; used regsvr32 fallback' })",
    "FFmpeg: $(if ($ffmpegPath) { $ffmpegPath } else { 'not resolved' })",
    "Camera name: $CameraName",
    "Source mode: $sourceMode",
    "RTSP URL: $(if ($RtspUrl) { $RtspUrl } else { 'not supplied' })",
    "Selected RTSP URL: $(if ($receiverSelectedRtspUrl) { $receiverSelectedRtspUrl } else { 'not discovered' })",
    "Opened RTSP URL: $(if ($receiverOpenedRtspUrl) { $receiverOpenedRtspUrl } else { 'not recorded' })",
    "Effective RTSP URL: $(if ($effectiveRtspUrl) { $effectiveRtspUrl } else { 'not applicable' })",
    "Auto-discover: $AutoDiscover",
    "Pair code: $(if ($PairCode) { $PairCode } else { 'not supplied' })",
    "Receiver stdout: $receiverLog",
    "Receiver stderr: $receiverErr",
    "DirectShow devices: $devicesLog",
    "Capture log: $(if ($SkipCapture) { 'skipped' } else { $captureLog })",
    "DirectShow frame snapshot: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotPath })",
    "DirectShow snapshot log: $(if ($SkipCapture) { 'skipped' } else { $directShowSnapshotLog })"
  )
  Set-Content -Path $summaryLog -Value $summary -Encoding UTF8
  Write-RuntimeEvidence -Path $evidenceLog -Status "failed" -Mode "windows-runtime-verification" -FailureMessage $failureMessage -Details ([ordered]@{
    receiver = if ($receiverPath) { $receiverPath } else { $null }
    receiverArguments = $receiverArgs
    softcamDll = $softcamDll
    softcamInstaller = if ($softcamInstaller) { $softcamInstaller } else { "not found; used regsvr32 fallback" }
    ffmpeg = if ($ffmpegPath) { $ffmpegPath } else { $null }
    cameraName = $CameraName
    sourceMode = $sourceMode
    rtspUrl = if ($RtspUrl) { $RtspUrl } else { $null }
    selectedRtspUrl = $receiverSelectedRtspUrl
    openedRtspUrl = $receiverOpenedRtspUrl
    effectiveRtspUrl = $effectiveRtspUrl
    autoDiscover = [bool]$AutoDiscover
    pairCode = if ($PairCode) { $PairCode } else { $null }
    discoverSeconds = $DiscoverSeconds
    receiverKeptRunning = $false
    receiverProcessId = if ($receiverProcess -and -not $receiverProcess.HasExited) { $receiverProcess.Id } else { $null }
    capture = [ordered]@{
      skipped = [bool]$SkipCapture
      frames = $capturedFrameCount
      requestedFrames = $CaptureFrames
      seconds = $CaptureSeconds
      width = $CaptureWidth
      height = $CaptureHeight
      fps = $Fps
      snapshot = if ($SkipCapture) { $null } else { $directShowSnapshotPath }
    }
    logs = [ordered]@{
      summary = $summaryLog
      evidence = $evidenceLog
      receiverStdout = $receiverLog
      receiverStderr = $receiverErr
      directShowDevices = $devicesLog
      capture = if ($SkipCapture) { $null } else { $captureLog }
      directShowSnapshot = if ($SkipCapture) { $null } else { $directShowSnapshotLog }
    }
  })
  Write-Host "PhoneCam Windows runtime verification failed."
  Write-Host "Summary: $summaryLog"
  Write-Host "Evidence: $evidenceLog"
  throw
}
finally {
  if (-not $keepReceiverAfterSuccess) {
    Stop-IfRunning $receiverProcess
  }

  if ($UnregisterAfter -and $registeredByThisRun) {
    Write-Host "Unregistering Softcam DLL: $softcamDll"
    Invoke-SoftcamRegistration -InstallerPath $softcamInstaller -DllPath $softcamDll -Unregister
  }
}
