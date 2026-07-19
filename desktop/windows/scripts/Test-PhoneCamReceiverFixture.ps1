param(
  [string]$Receiver = ".\build\windows-receiver\Release\phonecam-receiver.exe",
  [string]$MediaMtx = "mediamtx.exe",
  [string]$Ffmpeg = "ffmpeg.exe",
  [int]$RtspPort = 8555,
  [string]$RtspUrl = "",
  [string]$PairCode = "123456",
  [int]$Frames = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-CommandPath {
  param([string]$Command)

  if (Test-Path $Command) {
    return (Resolve-Path $Command).Path
  }

  $resolved = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $resolved) {
    throw "Command not found: $Command"
  }
  return $resolved.Source
}

function Stop-IfRunning {
  param([System.Diagnostics.Process]$Process)

  if ($Process -and -not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    $Process.WaitForExit(5000) | Out-Null
  }
}

$receiverPath = Resolve-CommandPath $Receiver
$mediaMtxPath = Resolve-CommandPath $MediaMtx
$ffmpegPath = Resolve-CommandPath $Ffmpeg
if (-not $RtspUrl) {
  $RtspUrl = "rtsp://127.0.0.1:$RtspPort/phonecam-test"
} else {
  try {
    $parsedRtspUrl = [Uri]$RtspUrl
    if ($parsedRtspUrl.Port -gt 0) {
      $RtspPort = $parsedRtspUrl.Port
    }
  } catch {
    throw "RtspUrl is not a valid URI: $RtspUrl"
  }
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("phonecam-fixture-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

$configPath = Join-Path $tempDir "mediamtx.yml"
$mediaMtxLog = Join-Path $tempDir "mediamtx.log"
$mediaMtxErr = Join-Path $tempDir "mediamtx.err.log"
$ffmpegLog = Join-Path $tempDir "ffmpeg.log"
$ffmpegErr = Join-Path $tempDir "ffmpeg.err.log"
$snapshotPath = Join-Path $tempDir "receiver-frame.ppm"

@"
logLevel: info
logDestinations: [stdout]
readTimeout: 10s
writeTimeout: 10s
rtsp: true
rtspTransports: [tcp]
rtspAddress: :$RtspPort
rtmp: false
hls: false
webrtc: false
srt: false
paths:
  all:
"@ | Set-Content -Path $configPath -Encoding UTF8

$mediaProcess = $null
$ffmpegProcess = $null

try {
  $mediaProcess = Start-Process -FilePath $mediaMtxPath -ArgumentList @($configPath) `
    -RedirectStandardOutput $mediaMtxLog -RedirectStandardError $mediaMtxErr -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 1
  if ($mediaProcess.HasExited) {
    Get-Content -Path $mediaMtxLog, $mediaMtxErr -ErrorAction SilentlyContinue | Write-Error
    throw "MediaMTX exited early. Logs: $mediaMtxLog, $mediaMtxErr"
  }

  $ffmpegArgs = @(
    "-hide_banner", "-loglevel", "info", "-re",
    "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30",
    "-f", "lavfi", "-i", "anullsrc=channel_layout=mono:sample_rate=48000",
    "-pix_fmt", "yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency",
    "-g", "30", "-b:v", "4M", "-c:a", "aac", "-b:a", "96k", "-rtsp_transport", "tcp", "-f", "rtsp", $RtspUrl
  )
  $ffmpegProcess = Start-Process -FilePath $ffmpegPath -ArgumentList $ffmpegArgs `
    -RedirectStandardOutput $ffmpegLog -RedirectStandardError $ffmpegErr -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 2
  if ($ffmpegProcess.HasExited) {
    Get-Content -Path $ffmpegLog, $ffmpegErr -ErrorAction SilentlyContinue | Write-Error
    throw "FFmpeg exited early. Logs: $ffmpegLog, $ffmpegErr"
  }

  $receiverArgs = @("--auto-discover-self-test", $RtspUrl, "--frames", $Frames, "--snapshot", $snapshotPath, "--no-preview", "--no-softcam")
  if ($PairCode) {
    $receiverArgs += @("--pair-code", $PairCode)
  }

  & $receiverPath @receiverArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Receiver fixture failed with exit code $LASTEXITCODE"
  }
  if (-not (Test-Path $snapshotPath -PathType Leaf)) {
    throw "Receiver fixture did not write a decoded frame snapshot: $snapshotPath"
  }
  $snapshotFile = Get-Item -Path $snapshotPath
  if ($snapshotFile.Length -le 0) {
    throw "Receiver fixture wrote an empty decoded frame snapshot: $snapshotPath"
  }

  Write-Host "Fixture passed."
  Write-Host "MediaMTX log: $mediaMtxLog"
  Write-Host "MediaMTX error log: $mediaMtxErr"
  Write-Host "FFmpeg log: $ffmpegLog"
  Write-Host "FFmpeg error log: $ffmpegErr"
  Write-Host "Receiver snapshot: $snapshotPath"
}
finally {
  Stop-IfRunning $ffmpegProcess
  Stop-IfRunning $mediaProcess
}
