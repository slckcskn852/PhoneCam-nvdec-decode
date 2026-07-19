# Progress Tracker

## Current Status
Last visited: 2026-07-19T21:46:00+03:00
- [x] Perform codebase audit and spec verification
- [x] Complete Android 4K60 sender core and ABR logic
- [x] Create Desktop Receiver shared core (C++ custom client, jitter buffer, parser)
- [x] Implement macOS VideoToolbox preview and CoreMediaIO Extension target
- [x] Integrate Windows D3D11VA/NVDEC decode and Softcam virtual camera
- [x] Create iOS Swift capture/encode sender application and Xcode project
- [x] Verify conformance vectors in Android, iOS, and C++ CTest test suites
- [x] Wire control UI and document verification results
- [x] Terminate background tasks

## Retrospective
- **What worked**: Running workers in parallel for Android, Desktop, and iOS platforms allowed fast and isolated progress. Consolidating the C++ receiver core into `desktop/core/` and referencing it on both macOS and Windows via a root CMake file simplified the build layout.
- **Lessons learned**: Handling CoreFoundation dictionary callbacks correctly requires strict adherence to CF standard callback definitions (e.g. `kCFTypeDictionaryKeyCallBacks`). Additionally, when using depacketizers that wait for RTP marker bits to emit access units, ensuring that tests flush the depacketizer (e.g. `flushAll()`) is critical to avoid silent buffer hangs.
