# PhoneCam Softcam Branding

The Windows virtual camera name is owned by the registered DirectShow filter. The receiver cannot rename the camera at runtime through the Softcam sender API.

For the MVP, build a PhoneCam-branded Softcam fork from upstream `tshino/softcam`:

- Source: https://github.com/tshino/softcam
- License: MIT
- Filter name: `PhoneCam Virtual Camera`
- CLSID used by this repo's preparation script: `{1BF2F2F1-5C41-4C0B-B53B-B606627B60F3}`

## Build A Branded Softcam

Run on Windows with Visual Studio 2022 installed:

```powershell
powershell -ExecutionPolicy Bypass -File desktop\windows\scripts\Prepare-PhoneCamSoftcam.ps1 `
  -Destination C:\deps\phonecam-softcam
```

The script clones upstream Softcam if needed, patches the visible DirectShow filter name and CLSID, then builds `softcam.sln` and `examples\softcam_installer\softcam_installer.sln` with MSBuild. It also writes `PHONECAM-SOFTCAM-BUILD.txt` into the prepared checkout with the resolved upstream commit, expected `PhoneCam Virtual Camera` filter name, PhoneCam CLSID, built DLL path, and installer path.

To register immediately, run the same command from a trusted admin-capable shell with `-Register`:

```powershell
powershell -ExecutionPolicy Bypass -File desktop\windows\scripts\Prepare-PhoneCamSoftcam.ps1 `
  -Destination C:\deps\phonecam-softcam `
  -Register
```

Registration requires Administrator approval. Unregister with Softcam's installer helper or `DllUnregisterServer` path before replacing the DLL.

## Receiver Link

After the branded Softcam build exists, point the receiver at the patched checkout:

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -DFFMPEG_ROOT=C:\deps\ffmpeg `
  -DSOFTCAM_ROOT=C:\deps\phonecam-softcam `
  -DPHONECAM_WITH_SOFTCAM=ON

cmake --build build/windows-receiver --config Release
```

Run the generated-frame path first:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --self-test --frames 240 --fps 60
```

Then open OBS, Zoom, Teams, Discord, or a browser camera test and select `PhoneCam Virtual Camera`.

## Files Patched From Upstream

- `src/softcam/softcam.cpp`
  - Replaces Softcam's default CLSID with the PhoneCam CLSID.
  - Replaces `DirectShow Softcam` with `PhoneCam Virtual Camera`.
- `src/softcamcore/DShowSoftcam.cpp`
  - Replaces filter and stream display names so DirectShow apps show the PhoneCam name.

Do not reuse upstream's original CLSID in a branded fork. A unique CLSID prevents conflicts with a user's separately installed upstream Softcam.
