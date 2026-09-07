param(
  [Parameter(Mandatory)][string]$BinaryDirectory,
  [Parameter(Mandatory)][string]$SoftcamInstaller,
  [Parameter(Mandatory)][string]$SoftcamLicense,
  [Parameter(Mandatory)][string]$FfmpegSourceArchive,
  [Parameter(Mandatory)][string]$FfmpegBuildInstructions,
  [Parameter(Mandatory)][string]$ThirdPartyLicenseDirectory,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [switch]$DevelopmentPackage
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$receiver = Join-Path $BinaryDirectory "phonecam-receiver.exe"
foreach ($path in @($receiver, $SoftcamInstaller, $SoftcamLicense, $FfmpegSourceArchive, $FfmpegBuildInstructions, $ThirdPartyLicenseDirectory)) {
  if (-not (Test-Path $path)) { throw "Missing release input: $path" }
}
if (Test-Path $OutputDirectory) { throw "Use a new output directory; existing packages are never overwritten" }
$dlls = @(Get-ChildItem $BinaryDirectory -Filter *.dll -File)
foreach ($pattern in @('softcam.dll', 'avcodec*.dll', 'avformat*.dll', 'avutil*.dll', 'swscale*.dll')) {
  if (-not ($dlls | Where-Object Name -Like $pattern)) { throw "Missing runtime DLL: $pattern" }
}
$dependencyInfo = & $receiver --release-check 2>&1
if ($LASTEXITCODE -ne 0) { throw "FFmpeg release license check failed: $dependencyInfo" }
if (-not $DevelopmentPackage) {
  foreach ($file in @($receiver, $SoftcamInstaller, (Join-Path $BinaryDirectory 'softcam.dll'))) {
    if ((Get-AuthenticodeSignature $file).Status -ne 'Valid') { throw "Release artifact needs a valid Authenticode signature: $file" }
  }
}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$notices = Join-Path $OutputDirectory 'licenses'
New-Item -ItemType Directory -Path $notices | Out-Null
Copy-Item $receiver $OutputDirectory
Copy-Item (Join-Path $PSScriptRoot 'Install-PhoneCamFirewallRules.ps1') $OutputDirectory
$dlls | Copy-Item -Destination $OutputDirectory
Copy-Item $SoftcamInstaller (Join-Path $OutputDirectory 'softcam_installer.exe')
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $notices 'PhoneCam-MIT.txt')
Copy-Item $SoftcamLicense (Join-Path $notices 'Softcam-MIT.txt')
Copy-Item (Join-Path $root 'docs\third-party-notices.md') $notices
Copy-Item (Join-Path $ThirdPartyLicenseDirectory '*') $notices -Recurse
Copy-Item $FfmpegSourceArchive $notices
Copy-Item $FfmpegBuildInstructions $notices
$dependencyInfo | Set-Content (Join-Path $notices 'linked-ffmpeg-build.txt')
Copy-Item (Join-Path $root 'docs\release-readiness.md') $OutputDirectory
Copy-Item (Join-Path $root 'docs\easy-connection.md') $OutputDirectory
Copy-Item (Join-Path $root 'CHANGELOG.md') $OutputDirectory
Get-ChildItem $OutputDirectory -Recurse -File | ForEach-Object {
  [PSCustomObject]@{ file = $_.FullName.Substring((Resolve-Path $OutputDirectory).Path.Length + 1); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'sha256-manifest.json')
Write-Host "Package created at $OutputDirectory. Verify the FFmpeg source archive matches these DLLs and retain dependency relinking rights in the EULA."
