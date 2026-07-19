## 2026-07-19T17:33:28Z
You are an iOS Swift developer worker. Your task is to create the iOS sender application project and files under `ios/`, and verify that it compiles and passes simulator unit tests.

## Files to write

### ios/PhoneCamSend.xcodeproj/project.pbxproj
[Included project.pbxproj template]

### ios/PhoneCamSend/PhoneCamSendApp.swift
[The SwiftUI app entry source provided in chunk 2]

### ios/PhoneCamSend/ContentView.swift
[The ContentView SwiftUI and Viewmodel source provided in chunk 3]

### ios/PhoneCamSend/CaptureEncoder.swift
[The AVFoundation capture and VideoToolbox encoder source provided in chunk 1]

### ios/PhoneCamSend/RtpSwiftPacketizer.swift
[The Swift H.265 packetizer source provided in chunk 1]

### ios/PhoneCamSend/ControlClient.swift
[The NWConnection Control client and ABR logic source provided in chunk 1]

### ios/PhoneCamSend/StreamController.swift
[The Swift streaming orchestrator source provided in chunk 2]

### ios/PhoneCamSend/UdpStreamSender.swift
[The NWConnection UDP media payload stream sender source provided in chunk 1]

### ios/PhoneCamSendTests/PhoneCamSendTests.swift
[The XCTest unit test source provided in chunk 3]

## Actions to perform
1. Create directories: `ios/PhoneCamSend.xcodeproj/`, `ios/PhoneCamSend/`, `ios/PhoneCamSendTests/`.
2. Write all the files above.
3. Run simulator tests to verify:
   `xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend -sdk iphonesimulator test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_IDENTITY=""`
4. Verify standard device target compilation compiles cleanly:
   `xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend -sdk iphoneos build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_IDENTITY=""`
