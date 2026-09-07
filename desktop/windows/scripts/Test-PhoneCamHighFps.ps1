param(
  [Parameter(Mandatory)][string]$Receiver,
  [Parameter(Mandatory)][ValidatePattern('^(udp|tcp)://')][string]$Source,
  [ValidateSet('4k60','1080p120','1080p240')][string]$Mode = '4k60',
  [ValidateRange(60,7200)][int]$Seconds = 1800,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [switch]$NoSoftcam,
  [switch]$SoftwareDecode
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Receiver = (Resolve-Path $Receiver).Path
if (Test-Path $OutputDirectory) { throw 'Use a new evidence directory' }
New-Item -ItemType Directory $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$width = 1920; $height = 1080; $fps = 240
if ($Mode -eq '4k60') { $width = 3840; $height = 2160; $fps = 60 }
if ($Mode -eq '1080p120') { $fps = 120 }
$arguments = @('--rtsp', $Source, '--width', $width, '--height', $height, '--fps', $fps, '--frames', ($Seconds * $fps), '--no-preview')
if ($NoSoftcam) { $arguments += '--no-softcam' }
if ($SoftwareDecode) { $arguments += '--software-decode' }
$stdout = Join-Path $OutputDirectory 'receiver.stdout.log'
$stderr = Join-Path $OutputDirectory 'receiver.stderr.log'
$samples = [System.Collections.Generic.List[object]]::new()
$timer = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process $Receiver -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$timedOut = $false
try {
  while (-not $process.HasExited) {
    Start-Sleep -Seconds 1
    $process.Refresh()
    if ($process.HasExited) { break }
    $samples.Add([PSCustomObject]@{
      elapsedSeconds = $timer.Elapsed.TotalSeconds
      privateBytes = $process.PrivateMemorySize64
      workingSet = $process.WorkingSet64
      handles = $process.HandleCount
      cpuSeconds = $process.TotalProcessorTime.TotalSeconds
    })
    if ($timer.Elapsed.TotalSeconds -gt ($Seconds / 0.9 + 30)) {
      $timedOut = $true
      $process.Kill()
      break
    }
  }
  $process.WaitForExit()
} finally {
  if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
  $samples | Export-Csv (Join-Path $OutputDirectory 'process-samples.csv') -NoTypeInformation
}
$log = Get-Content $stdout -Raw
$summary = [regex]::Match($log, 'Receiver summary: (\d+) frames, avg ([\d.]+) fps, decode errors (\d+)')
$measuredFps = 0.0; $decodeErrors = -1; $frames = 0
if ($summary.Success) {
  $frames = [long]$summary.Groups[1].Value
  $measuredFps = [double]::Parse($summary.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
  $decodeErrors = [long]$summary.Groups[3].Value
}
$warm = @($samples | Where-Object elapsedSeconds -GE 30)
$memoryGrowth = $null; $handleGrowth = $null
if ($warm.Count -ge 10) {
  $memoryGrowth = $warm[-1].privateBytes - $warm[0].privateBytes
  $handleGrowth = $warm[-1].handles - $warm[0].handles
}
$sourceMatches = $log.Contains("Negotiated source: ${width}x${height} @ $fps fps") -and $log.Contains('Frames with different source resolution: 0')
$softcamActive = $log.Contains('Softcam virtual camera active.')
$passed = ($NoSoftcam -or $softcamActive) -and -not $timedOut -and $process.ExitCode -eq 0 -and $sourceMatches -and $frames -ge ($Seconds * $fps) -and $measuredFps -ge (0.9 * $fps) -and $decodeErrors -eq 0 -and $null -ne $memoryGrowth -and $memoryGrowth -le 64MB -and $handleGrowth -le 32
[PSCustomObject]@{
  mode = $Mode; source = $Source; requestedSeconds = $Seconds; frames = $frames
  measuredFps = $measuredFps; decodeErrors = $decodeErrors; sourceMatches = $sourceMatches
  timedOut = $timedOut; receiverExitCode = $process.ExitCode
  privateByteGrowthAfterWarmup = $memoryGrowth; handleGrowthAfterWarmup = $handleGrowth
  softcamEnabled = $softcamActive; softwareDecodeRequested = [bool]$SoftwareDecode
  receiverSha256 = (Get-FileHash $Receiver -Algorithm SHA256).Hash
  windowsVersion = [Environment]::OSVersion.VersionString
  passed = $passed
  limitation = 'Receiver-side evidence only. Capture the same camera in DirectShow/OBS separately; process growth thresholds are regression gates, not proof of zero leaks.'
} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'high-fps-evidence.json')
if (-not $passed) { throw "High-FPS gate failed; inspect $OutputDirectory" }
Write-Host "Receiver high-FPS gate passed: $Mode. Consumer capture and device thermal/orientation checks still required."
