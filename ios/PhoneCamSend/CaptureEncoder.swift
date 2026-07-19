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
    
    private var width: Int = 1920
    private var height: Int = 1080
    private var fps: Int = 60
    private var bitrateBps: Int = 12_000_000
    
    private var isStreaming = false
    private let lock = NSLock()
    
    public init(delegate: CaptureEncoderDelegate? = nil) {
        self.delegate = delegate
        super.init()
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
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupCapture()
            self.setupEncoder()
            #if !targetEnvironment(simulator)
            self.captureSession?.startRunning()
            #endif
        }
    }
    
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isStreaming else { return }
        isStreaming = false
        
        queue.async { [weak self] in
            guard let self = self else { return }
            #if !targetEnvironment(simulator)
            self.captureSession?.stopRunning()
            #endif
            self.captureSession = nil
            self.teardownEncoder()
        }
    }
    
    public func setBitrate(_ bitrateBps: Int) {
        lock.lock()
        self.bitrateBps = bitrateBps
        let session = compressionSession
        lock.unlock()
        
        guard let session = session else { return }
        var bitrate = Int32(bitrateBps)
        let bitrateNum = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &bitrate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateNum)
        
        var byteLimit = Int64(Double(bitrateBps) * 1.5 / 8.0)
        var duration: Double = 1.0
        let limitArrayValues: [CFNumber?] = [
            CFNumberCreate(kCFAllocatorDefault, .sInt64Type, &byteLimit),
            CFNumberCreate(kCFAllocatorDefault, .doubleType, &duration)
        ]
        let limitArray = limitArrayValues as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limitArray)
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
                        if Int(range.maxFrameRate) >= self.fps {
                            bestFormat = format
                            bestFrameRateRange = range
                            break
                        }
                    }
                }
                if bestFormat != nil { break }
            }
            
            if let format = bestFormat, let range = bestFrameRateRange {
                try camera.lockForConfiguration()
                camera.activeFormat = format
                camera.activeVideoMinFrameDuration = range.minFrameDuration
                camera.activeVideoMaxFrameDuration = range.minFrameDuration
                camera.unlockForConfiguration()
            }
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
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
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
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
            VTCompressionSessionInvalidate(session)
            self.compressionSession = nil
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        lock.lock()
        let session = compressionSession
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
        
        var annexB = Data()
        var offset = 0
        while offset < length {
            var nalLength: UInt32 = 0
            let ptr = rawData.advanced(by: offset)
            memcpy(&nalLength, ptr, 4)
            nalLength = CFSwapInt32BigToHost(nalLength)
            offset += 4
            
            if offset + Int(nalLength) <= length {
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
