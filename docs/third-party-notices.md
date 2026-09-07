# Third-Party Notices

PhoneCamRedux is MIT. Keep third-party licenses visible when packaging binaries.

## RootEncoder

- Project: https://github.com/pedroSG94/RootEncoder
- License: Apache-2.0
- Use: Android camera encoding and RTSP/RTP transport support.

## RTSP-Server

- Project: https://github.com/pedroSG94/RTSP-Server
- License: Apache-2.0
- Use: Android RTSP server mode so the Windows receiver can open a standard RTSP URL.

## Softcam

- Project: https://github.com/tshino/softcam
- License: MIT
- Use: Windows DirectShow virtual webcam backend.

## FFmpeg

- Project: https://ffmpeg.org/
- License: build-dependent LGPL/GPL.
- Use: RTSP demuxing, H.264/HEVC decoding, pixel conversion.

Use dynamic LGPL FFmpeg builds for MIT-friendly distribution. Do not bundle GPL/nonfree builds without changing the distribution/license posture. The Windows vcpkg manifest disables FFmpeg default features and enables only the receiver libraries currently needed: `avcodec`, `avformat`, and `swscale`.

## OBS Studio

- Project: https://github.com/obsproject/obs-studio
- License: GPLv2
- Use: interoperability target only.

Do not copy OBS code into this MIT app. Users can select PhoneCam/Softcam as a camera source in OBS.

## Legacy Prototype Dependencies

The old Python receiver under `desktop/receiver` and the checked-in `UnityCapture-master` tree are retained as reference material only. They are not the production MVP path and are not part of the Windows MVP package.

### Unity Capture

- Project: https://github.com/schellingb/UnityCapture
- License: `UnityCaptureFilter` is MIT; `UnityCapturePlugin` is zlib, as stated in the checked-in `UnityCapture-master/README.md`.
- Use: legacy DirectShow prototype reference only.

Do not package UnityCapture in the PhoneCamRedux MVP deliverable. The production Windows virtual-camera backend is the PhoneCam-branded Softcam path.

### pyvirtualcam

- Project: https://github.com/letmaik/pyvirtualcam
- License: GPLv2, as listed on PyPI.
- Use: legacy Python receiver dependency only.

Do not package pyvirtualcam or the Python prototype into the MIT Windows MVP deliverable. Keep GPL components out of production distribution unless the distribution/license posture is intentionally changed.

## Proprietary distribution

The MIT application and Softcam licenses and Apache-2.0 Android dependencies permit proprietary derivatives when their applicable notices and obligations are retained. Preserve the existing copyright notices; a proprietary product license does not erase upstream rights.

For the Windows FFmpeg path, use dynamically linked LGPL builds without `--enable-gpl` or `--enable-nonfree`. Supply the exact corresponding FFmpeg source (including modifications), configuration/build instructions, dependency license texts, and a way for users to replace/relink the LGPL libraries. The product EULA must preserve LGPL-required reverse-engineering/relinking rights. The new release packager checks linked-library configuration, supplied license/source inputs and signatures; it cannot establish that an arbitrary source archive matches the binary. Review all transitive DLL licenses separately. See [FFmpeg's legal checklist](https://www.ffmpeg.org/legal.html).

HEVC patent obligations are separate from copyright licenses and vary with product/distribution circumstances; obtain product-specific advice before commercial shipment. Apple/Android platform codecs avoid bundling FFmpeg into mobile builds, but are not a blanket patent clearance. Local Homebrew FFmpeg builds used for testing may be GPL and must not be copied into the proprietary package.

Use `desktop/windows/scripts/Package-PhoneCamWindows.ps1` for this release path. Older MVP packaging scripts and CI binaries are development artifacts and do not certify licensing, signing or store readiness.
