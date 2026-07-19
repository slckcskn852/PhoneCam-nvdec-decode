param(
  [string]$Receiver = ".\build\windows-softcam-receiver\Release\phonecam-receiver.exe",
  [string]$SoftcamRoot = "C:\deps\phonecam-softcam",
  [string]$FfmpegBinDir = "",
  [string]$OutputDir = ".\dist\PhoneCam-Windows",
  [switch]$NoZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExistingFile {
  param([string]$Path)

  if (-not (Test-Path $Path -PathType Leaf)) {
    throw "File not found: $Path"
  }
  return (Resolve-Path $Path).Path
}

function Resolve-ExistingDirectory {
  param([string]$Path)

  if (-not (Test-Path $Path -PathType Container)) {
    throw "Directory not found: $Path"
  }
  return (Resolve-Path $Path).Path
}

function Find-FirstFile {
  param(
    [string]$Root,
    [string]$Filter,
    [string]$PathRegex
  )

  $rootPath = Resolve-ExistingDirectory $Root
  $match = Get-ChildItem -Path $rootPath -Recurse -Filter $Filter |
    Where-Object { $_.FullName -match $PathRegex } |
    Sort-Object FullName |
    Select-Object -First 1

  if (-not $match) {
    throw "$Filter not found under $rootPath with path regex $PathRegex"
  }

  return $match.FullName
}

function Copy-RequiredFile {
  param(
    [string]$Source,
    [string]$Destination
  )

  $sourcePath = Resolve-ExistingFile $Source
  New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
  Copy-Item -Path $sourcePath -Destination $Destination -Force
}

function Find-FfmpegBinDir {
  param([string]$ReceiverPath)

  if ($FfmpegBinDir) {
    return Resolve-ExistingDirectory $FfmpegBinDir
  }

  $candidates = @()
  $receiverDir = Split-Path -Parent $ReceiverPath
  $configBuildDir = Split-Path -Parent $receiverDir
  $candidates += $receiverDir

  $buildRoot = Split-Path -Parent $configBuildDir
  $candidates += Join-Path $configBuildDir "vcpkg_installed\x64-windows\bin"
  $candidates += Join-Path $configBuildDir "vcpkg_installed\x64-windows\debug\bin"
  $candidates += Join-Path $buildRoot "vcpkg_installed\x64-windows\bin"
  $candidates += Join-Path $buildRoot "vcpkg_installed\x64-windows\debug\bin"

  if ($env:FFMPEG_ROOT) {
    $candidates += Join-Path $env:FFMPEG_ROOT "bin"
  }

  foreach ($candidate in $candidates) {
    if ((Test-Path $candidate -PathType Container) -and
        (Get-ChildItem -Path $candidate -Filter "avcodec*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
      return (Resolve-Path $candidate).Path
    }
  }

  throw "Could not find FFmpeg DLLs. Pass -FfmpegBinDir C:\path\to\ffmpeg\bin."
}

function Copy-FfmpegDlls {
  param(
    [string]$SourceDir,
    [string]$DestinationDir
  )

  $copied = New-Object System.Collections.Generic.List[string]

  Get-ChildItem -Path $SourceDir -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $DestinationDir $_.Name) -Force
    $copied.Add($_.Name)
  }

  foreach ($required in @("avcodec", "avformat", "avutil", "swscale")) {
    if (-not ($copied | Where-Object { $_ -like "$required*.dll" })) {
      throw "Required FFmpeg runtime DLL was not copied: $required*.dll"
    }
  }

  return $copied
}

function Get-SoftcamBrandingReport {
  param(
    [string]$Root,
    [string]$SoftcamDll,
    [string]$SoftcamInstaller
  )

  $rootPath = Resolve-ExistingDirectory $Root
  $metadataPath = Join-Path $rootPath "PHONECAM-SOFTCAM-BUILD.txt"
  $softcamCpp = Join-Path $rootPath "src\softcam\softcam.cpp"
  $dshowCpp = Join-Path $rootPath "src\softcamcore\DShowSoftcam.cpp"
  $issues = New-Object System.Collections.Generic.List[string]
  $report = New-Object System.Collections.Generic.List[string]

  $report.Add("PhoneCam Softcam branding check") | Out-Null
  $report.Add("Generated: $(Get-Date -Format o)") | Out-Null
  $report.Add("Softcam root: $rootPath") | Out-Null
  $report.Add("Softcam DLL: $SoftcamDll") | Out-Null
  $report.Add("Softcam installer: $SoftcamInstaller") | Out-Null
  $report.Add("Expected filter name: PhoneCam Virtual Camera") | Out-Null
  $report.Add("Expected CLSID: {1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}") | Out-Null

  if (Test-Path $softcamCpp -PathType Leaf) {
    $softcamText = Get-Content -Raw -Path $softcamCpp
    if (-not $softcamText.Contains('FILTER_NAME[] = L"PhoneCam Virtual Camera"')) {
      $issues.Add("src\softcam\softcam.cpp does not contain the PhoneCam virtual camera filter name.") | Out-Null
    }
    if (-not ($softcamText.Contains("0x1bf2f2f1") -and $softcamText.Contains("0x5c41") -and $softcamText.Contains("0x4c0b"))) {
      $issues.Add("src\softcam\softcam.cpp does not contain the expected PhoneCam CLSID fields.") | Out-Null
    }
    $report.Add("Source branding check: src\softcam\softcam.cpp inspected") | Out-Null
  } else {
    $report.Add("Source branding check: src\softcam\softcam.cpp not present") | Out-Null
  }

  if (Test-Path $dshowCpp -PathType Leaf) {
    $dshowText = Get-Content -Raw -Path $dshowCpp
    if (-not $dshowText.Contains("PhoneCam Virtual Camera")) {
      $issues.Add("src\softcamcore\DShowSoftcam.cpp does not contain the PhoneCam virtual camera display name.") | Out-Null
    }
    $report.Add("Source branding check: src\softcamcore\DShowSoftcam.cpp inspected") | Out-Null
  } else {
    $report.Add("Source branding check: src\softcamcore\DShowSoftcam.cpp not present") | Out-Null
  }

  if (Test-Path $metadataPath -PathType Leaf) {
    $metadataText = Get-Content -Raw -Path $metadataPath
    if (-not $metadataText.Contains("PhoneCam Virtual Camera")) {
      $issues.Add("PHONECAM-SOFTCAM-BUILD.txt does not contain the PhoneCam virtual camera filter name.") | Out-Null
    }
    if (-not $metadataText.Contains("{1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}")) {
      $issues.Add("PHONECAM-SOFTCAM-BUILD.txt does not contain the expected PhoneCam CLSID.") | Out-Null
    }
    $report.Add("") | Out-Null
    $report.Add("Prepared Softcam metadata:") | Out-Null
    $metadataText -split '\r?\n' | ForEach-Object { $report.Add("  $_") | Out-Null }
  } elseif (-not (Test-Path $softcamCpp -PathType Leaf) -or -not (Test-Path $dshowCpp -PathType Leaf)) {
    $issues.Add("Softcam branding could not be verified: source files and PHONECAM-SOFTCAM-BUILD.txt are missing.") | Out-Null
  }

  if ($issues.Count -gt 0) {
    throw "Softcam branding verification failed:`n - $($issues -join "`n - ")"
  }

  $report.Add("") | Out-Null
  $report.Add("Result: passed") | Out-Null
  return $report.ToArray()
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$receiverPath = Resolve-ExistingFile $Receiver
$softcamRootPath = Resolve-ExistingDirectory $SoftcamRoot
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
$binDir = Join-Path $outputPath "bin"
$scriptDir = Join-Path $outputPath "scripts"
$docDir = Join-Path $outputPath "docs"

if (Test-Path $outputPath) {
  Remove-Item -Path $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $binDir, $scriptDir, $docDir -Force | Out-Null

$softcamDll = Find-FirstFile -Root $softcamRootPath -Filter "softcam.dll" -PathRegex "\\dist\\bin\\x64\\"
$softcamInstaller = Find-FirstFile -Root $softcamRootPath -Filter "softcam_installer.exe" -PathRegex "\\examples\\softcam_installer\\x64\\Release\\"
$resolvedFfmpegBinDir = Find-FfmpegBinDir -ReceiverPath $receiverPath
$softcamBrandingReport = Get-SoftcamBrandingReport -Root $softcamRootPath -SoftcamDll $softcamDll -SoftcamInstaller $softcamInstaller

Copy-RequiredFile -Source $receiverPath -Destination (Join-Path $binDir "phonecam-receiver.exe")
Copy-RequiredFile -Source $softcamDll -Destination (Join-Path $binDir "softcam.dll")
Copy-RequiredFile -Source $softcamInstaller -Destination (Join-Path $binDir "softcam_installer.exe")

$ffmpegDlls = Copy-FfmpegDlls -SourceDir $resolvedFfmpegBinDir -DestinationDir $binDir
$ffmpegExe = Get-ChildItem -Path $resolvedFfmpegBinDir -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ffmpegExe) {
  Copy-Item -Path $ffmpegExe.FullName -Destination (Join-Path $binDir "ffmpeg.exe") -Force
}
$ffmpegExeManifest = if ($ffmpegExe) { $ffmpegExe.FullName } else { "not included" }
$runtimeFfmpegPath = if ($ffmpegExe) { ".\bin\ffmpeg.exe" } else { "C:\deps\ffmpeg\bin\ffmpeg.exe" }
$runtimeFfmpegNote = if ($ffmpegExe) {
  "This package includes bin\ffmpeg.exe for DirectShow runtime verification."
} else {
  "This package does not include bin\ffmpeg.exe because the CI vcpkg manifest builds only FFmpeg runtime libraries. Install an LGPL-clean FFmpeg CLI build separately and pass its ffmpeg.exe path."
}

Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1") -Destination (Join-Path $scriptDir "Test-PhoneCamWindowsRuntime.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1") -Destination (Join-Path $scriptDir "Collect-PhoneCamWindowsEvidence.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\scripts\Test-PhoneCamReceiverFixture.ps1") -Destination (Join-Path $scriptDir "Test-PhoneCamReceiverFixture.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\scripts\Prepare-PhoneCamSoftcam.ps1") -Destination (Join-Path $scriptDir "Prepare-PhoneCamSoftcam.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\scripts\Install-PhoneCamFirewallRules.ps1") -Destination (Join-Path $scriptDir "Install-PhoneCamFirewallRules.ps1")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\validate_mvp_evidence.rb") -Destination (Join-Path $scriptDir "validate_mvp_evidence.rb")
Copy-RequiredFile -Source (Join-Path $repoRoot "scripts\bundle_mvp_evidence.rb") -Destination (Join-Path $scriptDir "bundle_mvp_evidence.rb")
Copy-RequiredFile -Source (Join-Path $repoRoot "README.md") -Destination (Join-Path $docDir "README.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\README.md") -Destination (Join-Path $docDir "WINDOWS-README.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "desktop\windows\SOFTCAM_BRANDING.md") -Destination (Join-Path $docDir "SOFTCAM_BRANDING.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\testing.md") -Destination (Join-Path $docDir "testing.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\verification-report.md") -Destination (Join-Path $docDir "verification-report.md")
Copy-RequiredFile -Source (Join-Path $repoRoot "docs\third-party-notices.md") -Destination (Join-Path $docDir "third-party-notices.md")
Set-Content -Path (Join-Path $docDir "SOFTCAM-BUILD.txt") -Value $softcamBrandingReport -Encoding UTF8

$packageReadmeTemplate = @'
PhoneCam Windows MVP Package
============================

Contents:
- bin\phonecam-receiver.exe
- bin\softcam.dll
- bin\softcam_installer.exe
- FFmpeg and vcpkg runtime DLLs required by the receiver
- scripts\Test-PhoneCamWindowsRuntime.ps1
- scripts\Collect-PhoneCamWindowsEvidence.ps1
- scripts\Test-PhoneCamReceiverFixture.ps1
- scripts\Prepare-PhoneCamSoftcam.ps1
- scripts\Install-PhoneCamFirewallRules.ps1
- scripts\validate_mvp_evidence.rb
- scripts\bundle_mvp_evidence.rb
- docs\README.md
- docs\WINDOWS-README.md
- docs\SOFTCAM_BRANDING.md
- docs\SOFTCAM-BUILD.txt
- docs\testing.md
- docs\verification-report.md
- docs\third-party-notices.md

__RUNTIME_FFMPEG_NOTE__

Prerequisites for final evidence capture:
- Elevated PowerShell for Softcam registration, DirectShow capture, and cleanup.
- Ruby available as `ruby` on PATH, or pass `-Ruby C:\path\to\ruby.exe` to `Collect-PhoneCamWindowsEvidence.ps1`. The collector uses Ruby for the Android matrix preflight, final MVP validator, and portable evidence bundler.
- An LGPL-clean FFmpeg CLI executable for DirectShow device enumeration and capture.

This package verified the bundled Softcam root before copying `softcam.dll`. `docs\SOFTCAM-BUILD.txt` records the expected `PhoneCam Virtual Camera` filter name, PhoneCam CLSID, copied Softcam DLL/installer paths, and any build metadata written by `Prepare-PhoneCamSoftcam.ps1`. Packaging fails if the Softcam source or metadata cannot prove the PhoneCam-branded filter name.

Recommended full Android-to-Windows evidence flow, from an elevated PowerShell after copying the physical Android matrix evidence onto the Windows host:

  .\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
    -PreflightOnly `
    -AndroidMatrix PATH\TO\matrix-evidence.json `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -PairCode PHONE_CODE

  .\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
    -AndroidMatrix PATH\TO\matrix-evidence.json `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -PairCode PHONE_CODE `
    -InstallFirewallRules

Use the first command for a no-capture collector preflight. It validates the Android matrix, pair code or manual RTSP URL, receiver, FFmpeg, Softcam DLL/installer, and elevation state, then writes windows-preflight-summary.txt and windows-preflight-evidence.json without changing firewall state, registering/capturing DirectShow, starting OBS/browser checks, or bundling final evidence. The full collector run first validates the Android matrix with scripts\validate_mvp_evidence.rb --android-only, so stale, emulator-derived, or missing orientation evidence stops the Windows run before DirectShow registration. The Android matrix must come from a physical phone and include accepted direct/back and front-camera orientation evidence with orientationEvidenceVersion >= 4, rotationControlMode per-camera-output, orientationLockMode fixed-landscape, device posture, recorded Rotate Left/Rotate Right direction, rotation request mode, output-rotation degrees, requested absolute output-rotation target when used, target/output consistency, and sender camera diagnostics.

If the Android matrix was collected on macOS, create a portable Android handoff before copying it to Windows:

  ruby scripts\bundle_mvp_evidence.rb `
    --android-matrix PATH\TO\matrix-evidence.json `
    --android-only `
    --output-dir PATH\TO\PhoneCam-Android-Matrix-Handoff

Copy that whole folder to Windows and pass PhoneCam-Android-Matrix-Handoff\android\matrix-evidence.json to Collect-PhoneCamWindowsEvidence.ps1. The handoff bundle validates only the Android matrix and rewrites per-profile artifact paths to relative paths; it does not replace Windows DirectShow, OBS, or browser evidence.

When `-PairCode` is supplied, the collector normalizes it to digits, requires exactly six digits, and checks it against the stable six-digit pairing code recorded in the Android matrix before Windows preflight or DirectShow registration starts. A mistyped code fails early, before Softcam registration or capture work. When manual `-RtspUrl` is supplied, the collector also checks that URL against the physical Android matrix before Windows preflight or DirectShow registration starts. The collector refuses `-SkipPreflight`; use `Test-PhoneCamWindowsRuntime.ps1` directly for debug-only experiments. The collector then runs preflight, optional private-LAN firewall setup, pair-code auto-discovery, DirectShow capture from `PhoneCam Virtual Camera`, and leaves the receiver running for OBS/browser checks. Use `-RtspUrl rtsp://PHONE_IP:8554/` instead of `-PairCode PHONE_CODE` only when UDP discovery is blocked.

After filling the generated manual app evidence template with OBS and browser/camera-app screenshot paths, finalize and bundle the MVP evidence:

  .\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
    -FinalizeOnly `
    -AndroidMatrix PATH\TO\matrix-evidence.json `
    -RuntimeEvidence PATH\TO\runtime-evidence.json `
    -ManualEvidence PATH\TO\manual-app-evidence-template.json

The collector validates manual OBS/browser evidence, runs the final MVP gate, and writes a portable `PhoneCam-MVP-Evidence` bundle unless `-NoBundle` is supplied.

Quick verification, from an elevated PowerShell:

  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -Register `
    -PreflightOnly

This writes windows-preflight-summary.txt and windows-preflight-evidence.json under %TEMP%\phonecam-windows-runtime-* without registering Softcam or capturing DirectShow frames. Use it first to catch missing receiver, FFmpeg, Softcam DLL/installer, or elevation prerequisites.

  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -Register `
    -UnregisterAfter

This writes receiver, DirectShow device-list, capture, DirectShow frame snapshot, runtime-summary.txt, and runtime-evidence.json logs under %TEMP%\phonecam-windows-runtime-*.

Physical Android to Windows DirectShow verification, after starting the Android camera server:

  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -AutoDiscover `
    -PairCode PHONE_CODE `
    -DiscoverSeconds 10 `
    -Register `
    -KeepReceiverRunning

This keeps the receiver running after FFmpeg DirectShow capture so OBS or a browser camera picker can select the same live `PhoneCam Virtual Camera` stream. It cannot be combined with `-SkipCapture`; OBS/browser evidence must be tied to a real FFmpeg DirectShow capture and saved `directshow-frame.bmp` artifact. It writes runtime-evidence.json, receiver process id, selected/opened RTSP URL details, DirectShow capture logs naming the camera, a saved PNG/JPEG/BMP DirectShow frame snapshot, manual-app-enumeration-checklist.txt, and manual-app-evidence-template.json beside runtime-summary.txt. Final evidence requires openedRtspUrl from receiver stdout for the actual stream and selectedRtspUrl for auto-discovery runs, and all recorded runtime RTSP URL fields must point at the same endpoint. The generated manual template includes runtimeArtifacts.directShowFrameSnapshot, runtimeArtifacts.directShowSnapshotLog, runtimeArtifacts.directShowCaptureLog, directShowFrameMatchesExpectedAndroidStream, and directShowFrameReviewNote so the Windows operator must inspect the virtual-camera frame before filling OBS/browser evidence. The manual-evidence validator cross-checks those runtimeArtifacts paths against runtime-evidence.json and requires the DirectShow snapshot review fields. Save non-empty OBS and browser/camera-app screenshots beside the evidence file; they must be separate app screenshots in PNG, JPEG, or BMP format with different image content and must not reuse the DirectShow frame snapshot path or content. Fill the generated manual evidence template with versions, pass/fail values, matching receiverProcessId, DirectShow snapshot review values, and screenshotPath values, set status to passed, then validate it before cleanup:

  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -ValidateManualEvidence PATH\TO\manual-app-evidence-template.json `
    -RuntimeEvidence PATH\TO\runtime-evidence.json

After OBS/browser checks, stop the reported receiver process and unregister Softcam:

  Stop-Process -Id RECEIVER_PROCESS_ID
  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -SoftcamRoot . `
    -UnregisterOnly

Final MVP evidence gate, after physical Android Wi-Fi matrix evidence and Windows runtime/manual evidence are all captured:

  ruby .\scripts\validate_mvp_evidence.rb `
    --android-matrix PATH\TO\matrix-evidence.json `
    --windows-runtime PATH\TO\runtime-evidence.json `
    --windows-manual PATH\TO\manual-app-evidence-template.json

The final gate cross-checks the Windows runtime RTSP URL and auto-discovery pair code against the physical Android matrix evidence, requires openedRtspUrl and auto-discovery selectedRtspUrl from receiver stdout, requires physical Android decode/discovery metrics plus accepted direct/back and front-camera orientation evidence with orientationEvidenceVersion >= 4, rotationControlMode per-camera-output, orientationLockMode fixed-landscape, device posture, recorded Rotate Left/Rotate Right direction, rotation request mode, output-rotation degrees, requested absolute output-rotation target when used, target/output consistency, and sender camera diagnostics, then requires DirectShow logs and capture logs to name the expected camera, show enough captured frames, and include a non-empty PNG/JPEG/BMP saved DirectShow frame snapshot. Capture the Android matrix and Windows DirectShow run against the same phone on the same LAN.

Portable evidence bundle, after the final gate passes:

  ruby .\scripts\bundle_mvp_evidence.rb `
    --android-matrix PATH\TO\matrix-evidence.json `
    --windows-runtime PATH\TO\runtime-evidence.json `
    --windows-manual PATH\TO\manual-app-evidence-template.json `
    --output-dir PATH\TO\PhoneCam-MVP-Evidence

The bundle copies the evidence folders, rewrites JSON file references to portable relative paths, copies validate_mvp_evidence.rb under tools\, and writes README.txt plus bundle-manifest.json with relative evidence paths, source input SHA-256 fingerprints, validation-skipped status, and a validation command for the bundled copies. Re-run the bundled validation command from the evidence bundle root before treating the archive as final evidence.
It validates the source evidence before copying and validates the bundled evidence after path rewriting. Use --skip-validation only while debugging evidence path issues; do not use it for the final MVP archive.
Use --android-only only for the Android matrix handoff before Windows evidence exists. A final MVP archive must be created without --android-only and without --skip-validation.

For a self-contained generated-frame verification without app checks:

  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -Register `
    -UnregisterAfter

Manual RTSP fallback when UDP discovery is blocked:

  .\scripts\Test-PhoneCamWindowsRuntime.ps1 `
    -Receiver .\bin\phonecam-receiver.exe `
    -SoftcamRoot . `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__ `
    -RtspUrl rtsp://PHONE_IP:8554/ `
    -Register `
    -KeepReceiverRunning

When -CaptureWidth and -CaptureHeight are omitted, FFmpeg DirectShow capture uses the camera's advertised/default format. Pass them explicitly only when the capture device requires a fixed size.

Use LGPL-clean FFmpeg builds for redistributable packages.

Optional local RTSP fixture without a phone:

  .\scripts\Test-PhoneCamReceiverFixture.ps1 `
    -Receiver .\bin\phonecam-receiver.exe `
    -MediaMtx C:\deps\mediamtx\mediamtx.exe `
    -Ffmpeg __RUNTIME_FFMPEG_PATH__

Optional Wi-Fi discovery firewall setup, from an elevated PowerShell on a private LAN:

  .\scripts\Install-PhoneCamFirewallRules.ps1 -Receiver .\bin\phonecam-receiver.exe

Normal receiver startup:

  .\bin\phonecam-receiver.exe

No-argument startup waits for a PhoneCam Android discovery beacon on UDP 47821.
'@

$packageReadme = $packageReadmeTemplate.Replace("__RUNTIME_FFMPEG_NOTE__", $runtimeFfmpegNote).Replace("__RUNTIME_FFMPEG_PATH__", $runtimeFfmpegPath)

Set-Content -Path (Join-Path $outputPath "README-WINDOWS.txt") -Value $packageReadme -Encoding UTF8

$manifest = @(
  "PhoneCam Windows package",
  "Generated: $(Get-Date -Format o)",
  "Receiver: $receiverPath",
  "Softcam DLL: $softcamDll",
  "Softcam installer: $softcamInstaller",
  "Softcam branding report: docs\SOFTCAM-BUILD.txt",
  "FFmpeg DLL source: $resolvedFfmpegBinDir",
  "FFmpeg executable: $ffmpegExeManifest",
  "FFmpeg/vcpkg runtime DLLs:"
) + ($ffmpegDlls | Sort-Object | ForEach-Object { "  - $_" })

Set-Content -Path (Join-Path $outputPath "PACKAGE-CONTENTS.txt") -Value $manifest -Encoding UTF8

if (-not $NoZip) {
  $zipPath = "$outputPath.zip"
  if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
  }
  Compress-Archive -Path (Join-Path $outputPath "*") -DestinationPath $zipPath -Force
  Write-Host "Package zip: $zipPath"
}

Write-Host "Package directory: $outputPath"
