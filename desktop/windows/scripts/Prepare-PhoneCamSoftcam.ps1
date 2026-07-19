param(
  [string]$Destination = "C:\deps\phonecam-softcam",
  [string]$Repository = "https://github.com/tshino/softcam.git",
  [string]$Revision = "main",
  [string]$Configuration = "Release",
  [string]$Platform = "x64",
  [switch]$Register
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MSBuild {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found. Install Visual Studio 2022 with Desktop development with C++."
  }

  $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\Current\Bin\MSBuild.exe" | Select-Object -First 1
  if (-not $msbuild -or -not (Test-Path $msbuild)) {
    throw "MSBuild not found. Install Visual Studio 2022 with MSBuild."
  }
  return $msbuild
}

function Replace-OrFail {
  param(
    [string]$Path,
    [string]$Old,
    [string]$New
  )

  $content = Get-Content -Raw -Path $Path
  if ($content.Contains($New)) {
    return
  }
  if (-not $content.Contains($Old)) {
    throw "Expected text not found in $Path"
  }
  Set-Content -Path $Path -Value $content.Replace($Old, $New) -NoNewline
}

if (-not (Test-Path $Destination)) {
  git clone $Repository $Destination
}

Push-Location $Destination
try {
  git fetch --tags origin
  git checkout $Revision

  $softcamCpp = Join-Path $Destination "src\softcam\softcam.cpp"
  $dshowCpp = Join-Path $Destination "src\softcamcore\DShowSoftcam.cpp"

  Replace-OrFail $softcamCpp "// {AEF3B972-5FA5-4647-9571-358EB472BC9E}" "// {1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}"
  Replace-OrFail $softcamCpp @"
DEFINE_GUID(CLSID_DShowSoftcam,
0xaef3b972, 0x5fa5, 0x4647, 0x95, 0x71, 0x35, 0x8e, 0xb4, 0x72, 0xbc, 0x9e);
"@ @"
DEFINE_GUID(CLSID_DShowSoftcam,
0x1bf2f2f1, 0x5c41, 0x4c0b, 0xb5, 0x3b, 0xb6, 0x06, 0x62, 0x7b, 0x60, 0xf3);
"@
  Replace-OrFail $softcamCpp 'const wchar_t FILTER_NAME[] = L"DirectShow Softcam";' 'const wchar_t FILTER_NAME[] = L"PhoneCam Virtual Camera";'
  Replace-OrFail $dshowCpp 'CSource(NAME("DirectShow Softcam"), lpunk, clsid)' 'CSource(NAME("PhoneCam Virtual Camera"), lpunk, clsid)'
  Replace-OrFail $dshowCpp '(void)new SoftcamStream(phr, this, L"DirectShow Softcam Stream");' '(void)new SoftcamStream(phr, this, L"PhoneCam Virtual Camera Stream");'
  Replace-OrFail $dshowCpp 'CSourceStream(NAME("DirectShow Softcam Stream"), phr, pParent, pPinName)' 'CSourceStream(NAME("PhoneCam Virtual Camera Stream"), phr, pParent, pPinName)'

  $msbuild = Get-MSBuild
  & $msbuild "softcam.sln" /m "/p:Configuration=$Configuration" "/p:Platform=$Platform"
  if ($LASTEXITCODE -ne 0) {
    throw "Softcam build failed with exit code $LASTEXITCODE"
  }

  $installerSolution = Join-Path $Destination "examples\softcam_installer\softcam_installer.sln"
  if (-not (Test-Path $installerSolution)) {
    throw "softcam_installer.sln was not found."
  }
  & $msbuild $installerSolution /m "/p:Configuration=$Configuration" "/p:Platform=$Platform"
  if ($LASTEXITCODE -ne 0) {
    throw "Softcam installer build failed with exit code $LASTEXITCODE"
  }

  $softcamDll = Get-ChildItem -Path $Destination -Recurse -Filter "softcam.dll" |
    Where-Object { $_.FullName -match "\\dist\\bin\\$Platform\\" } |
    Select-Object -First 1
  if (-not $softcamDll) {
    throw "Built softcam.dll was not found under dist\bin\$Platform."
  }

  $installer = Get-ChildItem -Path (Join-Path $Destination "examples\softcam_installer") -Recurse -Filter "softcam_installer.exe" |
    Where-Object { $_.FullName -match "\\$Platform\\$Configuration\\" } |
    Select-Object -First 1

  if (-not $installer) {
    throw "Built softcam_installer.exe was not found under examples\softcam_installer\$Platform\$Configuration."
  }

  $commit = (& git rev-parse HEAD).Trim()
  $metadata = @(
    "PhoneCam Softcam build metadata",
    "Generated: $(Get-Date -Format o)",
    "Repository: $Repository",
    "Requested revision: $Revision",
    "Resolved commit: $commit",
    "Configuration: $Configuration",
    "Platform: $Platform",
    "Filter name: PhoneCam Virtual Camera",
    "CLSID: {1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}",
    "Softcam DLL: $($softcamDll.FullName)",
    "Softcam installer: $($installer.FullName)",
    "Patched source: src\softcam\softcam.cpp",
    "Patched source: src\softcamcore\DShowSoftcam.cpp"
  )
  $metadataPath = Join-Path $Destination "PHONECAM-SOFTCAM-BUILD.txt"
  Set-Content -Path $metadataPath -Value $metadata -Encoding UTF8

  Write-Host "PhoneCam-branded Softcam DLL: $($softcamDll.FullName)"
  Write-Host "PhoneCam Softcam metadata: $metadataPath"

  if ($Register) {
    Start-Process -FilePath $installer.FullName -ArgumentList @("register", $softcamDll.FullName) -Verb RunAs -Wait
  } else {
    Write-Host "Register from an elevated PowerShell after review:"
    Write-Host "`"$($installer.FullName)`" register `"$($softcamDll.FullName)`""
  }
}
finally {
  Pop-Location
}
