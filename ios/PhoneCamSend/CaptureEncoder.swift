import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

public protocol CaptureEncoderDelegate: AnyObject {
    func captureEncoderDidOutputAccessUnit(_ encoder: CaptureEncoder, data: Data, ptsUs: Int64, isKeyFrame: Bool)
    func captureEncoderDidError(_ encoder: CaptureEncoder, message: String)
}

public class CaptureEncoder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public weak var delegate: CaptureEncoderDelegate?
    
    private var captureSession: AVCaptureSession?
    private var compressionSession: VTCompressionSession?
    private let queue = DispatchQueue(label: "com.phonecam.stream4k.capture")
    private let queueKey = DispatchSpecificKey<Bool>()
    
    private var width: Int = 1920
    private var height: Int = 1080
    private var fps: Int = 60
    private var bitrateBps: Int = 12_000_000
    
    private var isStreaming = false
    private let lock = NSLock()
    
    public init(delegate: CaptureEncoderDelegate? = nil) {
        self.delegate = delegate
        super.init()
        queue.setSpecific(key: queueKey, value: true)
    }
    
    deinit {
        // stop() synchronously drains callbacks before the unretained VT refcon dies.
        captureSession?.stopRunning()
        teardownEncoder()
    }

    private func onCaptureQueue(_ action: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true { action() }
        else { queue.sync(execute: action) }
    }

    public static func availableLadders() -> [Ladder] {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return [] }
        return ControlClient.candidateLadders.filter { mode in
            camera.formats.contains { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width == mode.width && dimensions.height == mode.height &&
                    format.videoSupportedFrameRateRanges.contains {
                        $0.minFrameRate <= Double(mode.fps) && $0.maxFrameRate >= Double(mode.fps)
                    }
            }
        }
    }

    public func configure(width: Int, height: Int, fps: Int, bitrateBps: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateBps = bitrateBps
    }
    
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStreaming else { return }
        isStreaming = true
        
        queue.async { [self] in
            lock.lock(); let active = isStreaming; lock.unlock()
            guard active else { return }
            self.setupCapture()
            #if !targetEnvironment(simulator)
            guard self.captureSession != nil else { return }
            #endif
            self.setupEncoder()
            #if !targetEnvironment(simulator)
            self.captureSession?.startRunning()
            #endif
        }
    }
    
    public func stop() {
        lock.lock()
        isStreaming = false
        lock.unlock()
        onCaptureQueue {
            #if !targetEnvironment(simulator)
            self.captureSession?.stopRunning()
            #endif
            self.captureSession = nil
            self.teardownEncoder()
        }
    }

    public func setBitrate(_ bitrateBps: Int) {
        queue.async { [weak self] in
            guard let self = self, let session = self.compressionSession else { return }
            self.bitrateBps = max(1_000_000, min(bitrateBps, 80_000_000))
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                                 value: self.bitrateBps as CFNumber)
        }
    }

    public func requestKeyFrame() {
        lock.lock()
        forceKeyFrameFlag = true
        lock.unlock()
    }
    
    private var forceKeyFrameFlag = false
    
    private func setupCapture() {
        #if targetEnvironment(simulator)
        print("CaptureEncoder: Running in simulator, AVCaptureSession will not be started.")
        #else
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            delegate?.captureEncoderDidError(self, message: "No back camera available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            var bestFormat: AVCaptureDevice.Format? = nil
            var bestFrameRateRange: AVFrameRateRange? = nil
            
            for format in camera.formats {
                let desc = format.formatDescription
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                if dims.width == self.width && dims.height == self.height {
                    for range in format.videoSupportedFrameRateRanges {
                        if range.minFrameRate <= Double(self.fps) && range.maxFrameRate >= Double(self.fps) {
                            bestFormat = format
                            bestFrameRateRange = range
                            break
                        }
                    }
                }
                if bestFormat != nil { break }
            }
            
            guard let format = bestFormat, bestFrameRateRange != nil else {
                delegate?.captureEncoderDidError(self, message: "Requested camera size/FPS is unavailable")
                return
            }
            do {
                try camera.lockForConfiguration()
                camera.activeFormat = format
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(self.fps))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(self.fps))
                camera.unlockForConfiguration()
            }
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            self.captureSession = session
        } catch {
            delegate?.captureEncoderDidError(self, message: "Camera setup failed: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func setupEncoder() {
        teardownEncoder()
        
        #if targetEnvironment(simulator)
        print("CaptureEncoder: Running in simulator, VTCompressionSession will not be created.")
        #else
        let width = self.width
        let height = self.height
        
        var compressionSessionOut: VTCompressionSession?
        
        let encoderCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else {
                return
            }
            
            let encoder = Unmanaged<CaptureEncoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
            encoder.handleEncodedFrame(sampleBuffer)
        }
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        var specification: CFDictionary? = nil
        if #available(iOS 17.4, *) {
            specification = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary
        }
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderCallback,
            refcon: selfPointer,
            compressionSessionOut: &compressionSessionOut
        )
        
        guard status == noErr, let session = compressionSessionOut else {
            delegate?.captureEncoderDidError(self, message: "VTCompressionSessionCreate failed: \(status)")
            return
        }
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        
        var bitrate = Int32(self.bitrateBps)
        let bitrateNum = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &bitrate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateNum)
        
        var maxKeyframeInterval = Int32(self.fps * 2)
        let keyframeNum = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &maxKeyframeInterval)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyframeNum)
        
        #if os(iOS)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        #endif
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        self.compressionSession = session
        #endif
    }
    
    private func teardownEncoder() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            self.compressionSession = nil
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        lock.lock()
        let session = isStreaming ? compressionSession : nil
        let forceKeyFrame = forceKeyFrameFlag
        if forceKeyFrame {
            forceKeyFrameFlag = false
        }
        lock.unlock()
        
        guard let activeSession = session else { return }
        
        let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var frameOptions: CFDictionary? = nil
        if forceKeyFrame {
            let key = kVTEncodeFrameOptionKey_ForceKeyFrame
            frameOptions = [key: kCFBooleanTrue] as CFDictionary
        }
        
        VTCompressionSessionEncodeFrame(
            activeSession,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimestamp,
            duration: .invalid,
            frameProperties: frameOptions,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
    
    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer) {
        var isKeyFrame = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let attachment = attachments.first {
            let key = kCMSampleAttachmentKey_NotSync
            if let notSync = attachment[key] as? Bool {
                isKeyFrame = !notSync
            } else {
                isKeyFrame = true
            }
        }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsUs = Int64(pts.seconds * 1_000_000.0)
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let rawData = dataPointer else { return }
        
        guard length <= 8 * 1024 * 1024 else { return }
        var annexB = Data(capacity: length + 256)
        var offset = 0
        while offset + 4 <= length {
            var nalLength: UInt32 = 0
            let ptr = rawData.advanced(by: offset)
            memcpy(&nalLength, ptr, 4)
            nalLength = CFSwapInt32BigToHost(nalLength)
            offset += 4
            
            if nalLength > 0 && Int(nalLength) <= length - offset {
                let startCode = Data([0x00, 0x00, 0x00, 0x01])
                annexB.append(startCode)
                let nalData = Data(bytes: ptr.advanced(by: 4), count: Int(nalLength))
                annexB.append(nalData)
                offset += Int(nalLength)
            } else {
                break
            }
        }
        
        if isKeyFrame, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var parameterSets = Data()
            var parameterSetCount = 0
            
            let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &parameterSetCount,
                nalUnitHeaderLengthOut: nil
            )
            
            if status == noErr {
                for i in 0..<parameterSetCount {
                    var parameterSetPointer: UnsafePointer<UInt8>?
                    var parameterSetSize = 0
                    let psStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                        formatDesc,
                        parameterSetIndex: i,
                        parameterSetPointerOut: &parameterSetPointer,
                        parameterSetSizeOut: &parameterSetSize,
                        parameterSetCountOut: nil,
                        nalUnitHeaderLengthOut: nil
                    )
                    if psStatus == noErr, let ptr = parameterSetPointer {
                        parameterSets.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                        parameterSets.append(ptr, count: parameterSetSize)
                    }
                }
            }
            
            if !parameterSets.isEmpty {
                annexB = parameterSets + annexB
            }
        }
        
        delegate?.captureEncoderDidOutputAccessUnit(self, data: annexB, ptsUs: ptsUs, isKeyFrame: isKeyFrame)
    }
}
