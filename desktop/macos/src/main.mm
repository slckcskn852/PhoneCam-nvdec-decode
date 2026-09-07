#import <Cocoa/Cocoa.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#include <cstring>
#include "phonecam_client.h"
#include "control_parser.h"
#include "discovery.h"
#include <vector>
#include <iostream>
#include <memory>
#include <string>
#include <atomic>
#include <thread>
#include <chrono>
#include <iomanip>
#include <signal.h>

// Options structure matching CLI arguments
struct Options {
    std::string host = "127.0.0.1";
    int width = 3840;
    int height = 2160;
    int fps = 60;
    bool tcp = false;
    bool headless = false;
    double duration = -1.0;
    double statsInterval = 1.0;
    bool autoDiscover = false;
    std::string pairCode = "";
};

static Options gOptions;

void parseRtspUrl(const std::string& url, std::string& host, bool& tcp) {
    if (url.rfind("tcp://", 0) == 0) {
        tcp = true;
    }
    size_t pos = url.find("://");
    std::string auth = (pos == std::string::npos) ? url : url.substr(pos + 3);
    size_t slash = auth.find('/');
    std::string hostport = (slash == std::string::npos) ? auth : auth.substr(0, slash);
    size_t colon = hostport.find(':');
    host = (colon == std::string::npos) ? hostport : hostport.substr(0, colon);
}

// Simple VideoToolbox Decoder
class VideoToolboxDecoder {
public:
    VideoToolboxDecoder(std::function<void(CVPixelBufferRef, uint32_t)> callback)
        : callback_(callback), session_(nullptr), formatDesc_(nullptr) {}

    ~VideoToolboxDecoder() {
        reset();
    }

    void reset() {
        if (session_) {
            VTDecompressionSessionWaitForAsynchronousFrames(session_);
            VTDecompressionSessionInvalidate(session_);
            CFRelease(session_);
            session_ = nullptr;
        }
        if (formatDesc_) {
            CFRelease(formatDesc_);
            formatDesc_ = nullptr;
        }
        vps_.clear();
        sps_.clear();
        pps_.clear();
    }

    void decodeFrame(const uint8_t* data, size_t len, uint32_t rtpTimestamp) {
        // Parse Annex B into NAL units
        size_t offset = 0;
        std::vector<std::pair<size_t, size_t>> nals; // (start_offset, length)
        
        while (offset + 4 <= len) {
            if (data[offset] == 0 && data[offset+1] == 0 && data[offset+2] == 0 && data[offset+3] == 1) {
                size_t start = offset + 4;
                size_t next = start;
                bool foundNext = false;
                while (next + 4 <= len) {
                    if (data[next] == 0 && data[next+1] == 0 && data[next+2] == 0 && data[next+3] == 1) {
                        foundNext = true;
                        break;
                    }
                    next++;
                }
                if (!foundNext) {
                    next = len;
                }
                if (next > start) {
                    size_t nal_len = next - start;
                    while (nal_len > 0 && data[start + nal_len - 1] == 0) {
                        nal_len--;
                    }
                    if (nal_len > 0) {
                        nals.push_back({start, nal_len});
                    }
                }
                offset = next;
            } else {
                offset++;
            }
        }

        // Build sample buffer
        std::vector<uint8_t> sampleBufferData;
        bool hasParameterSets = false;

        for (const auto& nal : nals) {
            const uint8_t* nalData = data + nal.first;
            size_t nalLen = nal.second;
            uint8_t type = (nalData[0] >> 1) & 0x3F;

            if (type == 32) { // VPS
                std::vector<uint8_t> incoming(nalData, nalData + nalLen);
                hasParameterSets |= incoming != vps_;
                vps_ = std::move(incoming);
            } else if (type == 33) { // SPS
                std::vector<uint8_t> incoming(nalData, nalData + nalLen);
                hasParameterSets |= incoming != sps_;
                sps_ = std::move(incoming);
            } else if (type == 34) { // PPS
                std::vector<uint8_t> incoming(nalData, nalData + nalLen);
                hasParameterSets |= incoming != pps_;
                pps_ = std::move(incoming);
            } else {
                size_t currentOffset = sampleBufferData.size();
                sampleBufferData.resize(currentOffset + 4 + nalLen);
                sampleBufferData[currentOffset + 0] = (nalLen >> 24) & 0xFF;
                sampleBufferData[currentOffset + 1] = (nalLen >> 16) & 0xFF;
                sampleBufferData[currentOffset + 2] = (nalLen >> 8) & 0xFF;
                sampleBufferData[currentOffset + 3] = nalLen & 0xFF;
                std::memcpy(&sampleBufferData[currentOffset + 4], nalData, nalLen);
            }
        }

        if ((hasParameterSets || !session_) && !vps_.empty() && !sps_.empty() && !pps_.empty()) {
            recreateSession();
        }

        if (sampleBufferData.empty()) {
            return;
        }

        if (!session_) {
            static int warnCount = 0;
            if (warnCount++ % 100 == 0) {
                std::cerr << "[Decoder] Warning: No active decompression session (VPS=" << vps_.size()
                          << ", SPS=" << sps_.size() << ", PPS=" << pps_.size() << ")\n" << std::flush;
            }
            return;
        }

        CMBlockBufferRef blockBuffer = nullptr;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(
            kCFAllocatorDefault,
            nullptr,
            sampleBufferData.size(),
            kCFAllocatorDefault,
            nullptr,
            0,
            sampleBufferData.size(),
            0,
            &blockBuffer
        );
        if (status != noErr) return;

        status = CMBlockBufferReplaceDataBytes(
            sampleBufferData.data(),
            blockBuffer,
            0,
            sampleBufferData.size()
        );
        if (status != noErr) {
            CFRelease(blockBuffer);
            return;
        }

        CMSampleBufferRef sampleBuffer = nullptr;
        size_t sampleSize = sampleBufferData.size();
        status = CMSampleBufferCreateReady(
            kCFAllocatorDefault,
            blockBuffer,
            formatDesc_,
            1,
            0,
            nullptr,
            1,
            &sampleSize,
            &sampleBuffer
        );
        CFRelease(blockBuffer);
        if (status != noErr) return;

        // Synchronous submission bounds decoded surfaces when the consumer stalls.
        VTDecodeFrameFlags flags = 0;
        VTDecodeInfoFlags infoFlagsOut;
        VTDecompressionSessionDecodeFrame(
            session_,
            sampleBuffer,
            flags,
            (void*)(uintptr_t)rtpTimestamp, // Pass timestamp as sourceFrameRefCon
            &infoFlagsOut
        );
        CFRelease(sampleBuffer);
    }

private:
    void recreateSession() {
        if (formatDesc_) {
            CFRelease(formatDesc_);
            formatDesc_ = nullptr;
        }
        if (session_) {
            VTDecompressionSessionWaitForAsynchronousFrames(session_);
            VTDecompressionSessionInvalidate(session_);
            CFRelease(session_);
            session_ = nullptr;
        }

        const uint8_t* parameterSetPointers[3] = { vps_.data(), sps_.data(), pps_.data() };
        const size_t parameterSetSizes[3] = { vps_.size(), sps_.size(), pps_.size() };
        
        OSStatus status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            kCFAllocatorDefault,
            3,
            parameterSetPointers,
            parameterSetSizes,
            4, // 4-byte length prefix
            nullptr,
            &formatDesc_
        );

        if (status != noErr) {
            std::cerr << "CMVideoFormatDescriptionCreateFromHEVCParameterSets failed: " << status << "\n";
            return;
        }

        VTDecompressionOutputCallbackRecord callbackRecord;
        callbackRecord.decompressionOutputCallback = decompressionCallback;
        callbackRecord.decompressionOutputRefCon = this;

        CFMutableDictionaryRef destinationImageBufferAttributes = CFDictionaryCreateMutable(
            kCFAllocatorDefault,
            0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
        
        int formatType = kCVPixelFormatType_32BGRA;
        CFNumberRef pixelFormatNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &formatType);
        CFDictionarySetValue(
            destinationImageBufferAttributes,
            kCVPixelBufferPixelFormatTypeKey,
            pixelFormatNumber
        );
        CFRelease(pixelFormatNumber);

        status = VTDecompressionSessionCreate(
            kCFAllocatorDefault,
            formatDesc_,
            nullptr,
            destinationImageBufferAttributes,
            &callbackRecord,
            &session_
        );
        CFRelease(destinationImageBufferAttributes);

        if (status != noErr) {
            std::cerr << "VTDecompressionSessionCreate failed: " << status << "\n";
        }
    }

    static void decompressionCallback(
        void* decompressionRefCon,
        void* sourceFrameRefCon,
        OSStatus status,
        VTDecodeInfoFlags infoFlags,
        CVImageBufferRef imageBuffer,
        CMTime presentationTimeStamp,
        CMTime presentationDuration) {
        
        uint32_t rtpTimestamp = (uint32_t)(uintptr_t)sourceFrameRefCon;
        if (status == noErr && imageBuffer) {
            auto* decoder = static_cast<VideoToolboxDecoder*>(decompressionRefCon);
            decoder->callback_(imageBuffer, rtpTimestamp);
        }
    }

    std::function<void(CVPixelBufferRef, uint32_t)> callback_;
    VTDecompressionSessionRef session_;
    CMVideoFormatDescriptionRef formatDesc_;
    std::vector<uint8_t> vps_;
    std::vector<uint8_t> sps_;
    std::vector<uint8_t> pps_;
};

@interface PreviewView : NSView {
    std::atomic<bool> updatePending_;
    CIContext* imageContext_;
}
- (void)updateFrame:(CVPixelBufferRef)pixelBuffer;
@end

@implementation PreviewView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        updatePending_ = false;
        imageContext_ = [CIContext contextWithOptions:nil];
        self.wantsLayer = YES;
        self.layer.contentsGravity = kCAGravityResizeAspect;
    }
    return self;
}

- (void)updateFrame:(CVPixelBufferRef)pixelBuffer {
    if (updatePending_.exchange(true)) return;
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
        CIImage* image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        CGImageRef rendered = [imageContext_ createCGImage:image fromRect:image.extent];
        self.layer.contents = (__bridge id)rendered;
        if (rendered) CGImageRelease(rendered);
        CVPixelBufferRelease(pixelBuffer);
        updatePending_ = false;
    });
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
@public
    NSWindow* window_;
    PreviewView* previewView_;
    std::unique_ptr<phonecam::PhoneCamClient> client_;
    std::unique_ptr<VideoToolboxDecoder> decoder_;
    std::thread statsThread_;
    std::atomic<bool> statsRunning_;
    int exitCode_;
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSRect rect = NSMakeRect(0, 0, 1280, 720);
    window_ = [[NSWindow alloc] initWithContentRect:rect
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [window_ setTitle:@"PhoneCam macOS Receiver"];
    [window_ setDelegate:self];
    
    previewView_ = [[PreviewView alloc] initWithFrame:rect];
    [window_ setContentView:previewView_];
    [window_ makeKeyAndOrderFront:nil];
    [window_ center];
    
    [NSApp activateIgnoringOtherApps:YES];
    
    exitCode_ = 0;
    
    decoder_ = std::make_unique<VideoToolboxDecoder>([self](CVPixelBufferRef pb, uint32_t timestamp) {
        if (self->client_) {
            self->client_->reportDecodedFrame(timestamp);
        }
        [previewView_ updateFrame:pb];
    });
    
    std::cout << "Starting client connecting to host: " << gOptions.host << "\n";
    phonecam::TransportMode mode = gOptions.tcp ? phonecam::TransportMode::TCP : phonecam::TransportMode::UDP;
    
    client_ = std::make_unique<phonecam::PhoneCamClient>(mode, gOptions.host);
    client_->setFrameCallback([self](const uint8_t* data, size_t len, uint32_t timestamp, bool) {
        self->decoder_->decodeFrame(data, len, timestamp);
    });
    
    if (!client_->start(gOptions.width, gOptions.height, gOptions.fps)) {
        std::cerr << "Failed to start PhoneCamClient\n";
        [NSApp terminate:nil];
        return;
    }
    
    statsRunning_ = true;
    statsThread_ = std::thread([self]() {
        auto startTime = std::chrono::steady_clock::now();
        auto lastStatsTime = startTime;
        
        uint64_t totalFramesDecoded = 0;
        uint64_t totalFramesReceived = 0;
        double totalFrameAgeMsSum = 0.0;
        uint64_t totalFrameAgeCount = 0;
        uint64_t lastNackRecoveries = 0;
        double lastLossPercent = 0.0;
        
        while (self->statsRunning_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            if (!self->statsRunning_) break;
            
            auto now = std::chrono::steady_clock::now();
            double elapsed = std::chrono::duration<double>(now - startTime).count();
            
            if (gOptions.duration > 0.0 && elapsed >= gOptions.duration) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->window_ close];
                });
                break;
            }
            
            double elapsedStats = std::chrono::duration<double>(now - lastStatsTime).count();
            if (elapsedStats >= gOptions.statsInterval) {
                auto stats = self->client_->getStats();
                
                std::cout << "[Stats] Net FPS: " << std::fixed << std::setprecision(1) << stats.networkFps
                          << " | Loss: " << std::setprecision(2) << stats.lossPercent << "%"
                          << " | NACK: " << stats.nackRecoveries
                          << " | Decode FPS: " << std::setprecision(1) << stats.decodeFps
                          << " | Frame Age: " << std::setprecision(1) << stats.avgFrameAgeMs << " ms\n" << std::flush;
                
                totalFramesDecoded += (uint64_t)(stats.decodeFps * elapsedStats);
                totalFramesReceived += (uint64_t)(stats.networkFps * elapsedStats);
                if (stats.avgFrameAgeMs > 0.0) {
                    totalFrameAgeMsSum += stats.avgFrameAgeMs;
                    totalFrameAgeCount++;
                }
                lastNackRecoveries = stats.nackRecoveries;
                lastLossPercent = stats.lossPercent;
                
                lastStatsTime = now;
            }
        }
        
        auto endTime = std::chrono::steady_clock::now();
        double totalDuration = std::chrono::duration<double>(endTime - startTime).count();
        
        auto stats = self->client_->getStats();
        double elapsedStats = std::chrono::duration<double>(endTime - lastStatsTime).count();
        if (elapsedStats > 0.0) {
            totalFramesDecoded += (uint64_t)(stats.decodeFps * elapsedStats);
            totalFramesReceived += (uint64_t)(stats.networkFps * elapsedStats);
            if (stats.avgFrameAgeMs > 0.0) {
                totalFrameAgeMsSum += stats.avgFrameAgeMs;
                totalFrameAgeCount++;
            }
            lastNackRecoveries = stats.nackRecoveries;
            lastLossPercent = stats.lossPercent;
        }
        
        bool success = true;
        double finalAvgDecodeFps = totalDuration > 0.0 ? (double)totalFramesDecoded / totalDuration : 0.0;
        double finalAvgNetworkFps = totalDuration > 0.0 ? (double)totalFramesReceived / totalDuration : 0.0;
        double finalAvgFrameAge = totalFrameAgeCount > 0 ? totalFrameAgeMsSum / totalFrameAgeCount : 0.0;
        
        if (finalAvgDecodeFps < 0.9 * gOptions.fps) success = false;
        if (lastLossPercent >= 1.0) success = false;
        
        std::cout << "\n{\"duration_sec\": " << std::fixed << std::setprecision(1) << totalDuration
                  << ", \"total_packets\": " << stats.networkPackets
                  << ", \"loss_percent\": " << std::setprecision(2) << lastLossPercent
                  << ", \"nack_recoveries\": " << lastNackRecoveries
                  << ", \"avg_network_fps\": " << std::setprecision(1) << finalAvgNetworkFps
                  << ", \"avg_decode_fps\": " << std::setprecision(1) << finalAvgDecodeFps
                  << ", \"avg_frame_age_ms\": " << std::setprecision(1) << finalAvgFrameAge
                  << ", \"success\": " << (success ? "true" : "false") << "}\n" << std::flush;
        
        self->exitCode_ = success ? 0 : 1;
    });
}

- (void)windowWillClose:(NSNotification *)notification {
    statsRunning_ = false;
    if (client_) {
        client_->stop();
    }
    if (statsThread_.joinable()) {
        statsThread_.join();
    }
    decoder_.reset();
    std::exit(exitCode_);
}

@end

std::atomic<bool> gKeepRunning{true};
void sigintHandler(int) {
    gKeepRunning = false;
}

int runHeadless() {
    signal(SIGINT, sigintHandler);
    
    std::cout << "Starting headless client connecting to host: " << gOptions.host << "\n";
    phonecam::TransportMode mode = gOptions.tcp ? phonecam::TransportMode::TCP : phonecam::TransportMode::UDP;
    
    auto client = std::make_unique<phonecam::PhoneCamClient>(mode, gOptions.host);
    auto decoder = std::make_unique<VideoToolboxDecoder>([&client](CVPixelBufferRef pb, uint32_t timestamp) {
        client->reportDecodedFrame(timestamp);
    });
    
    client->setFrameCallback([&decoder](const uint8_t* data, size_t len, uint32_t timestamp, bool) {
        decoder->decodeFrame(data, len, timestamp);
    });
    
    if (!client->start(gOptions.width, gOptions.height, gOptions.fps)) {
        std::cerr << "Failed to start client\n";
        return 1;
    }
    
    auto startTime = std::chrono::steady_clock::now();
    auto lastStatsTime = startTime;
    
    uint64_t totalFramesDecoded = 0;
    uint64_t totalFramesReceived = 0;
    double totalFrameAgeMsSum = 0.0;
    uint64_t totalFrameAgeCount = 0;
    uint64_t lastNackRecoveries = 0;
    double lastLossPercent = 0.0;
    
    while (gKeepRunning) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        
        auto now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(now - startTime).count();
        
        if (gOptions.duration > 0.0 && elapsed >= gOptions.duration) {
            break;
        }
        
        double elapsedStats = std::chrono::duration<double>(now - lastStatsTime).count();
        if (elapsedStats >= gOptions.statsInterval) {
            auto stats = client->getStats();
            
            std::cout << "[Stats] Net FPS: " << std::fixed << std::setprecision(1) << stats.networkFps
                      << " | Loss: " << std::setprecision(2) << stats.lossPercent << "%"
                      << " | NACK: " << stats.nackRecoveries
                      << " | Decode FPS: " << std::setprecision(1) << stats.decodeFps
                      << " | Frame Age: " << std::setprecision(1) << stats.avgFrameAgeMs << " ms\n" << std::flush;
            
            totalFramesDecoded += (uint64_t)(stats.decodeFps * elapsedStats);
            totalFramesReceived += (uint64_t)(stats.networkFps * elapsedStats);
            if (stats.avgFrameAgeMs > 0.0) {
                totalFrameAgeMsSum += stats.avgFrameAgeMs;
                totalFrameAgeCount++;
            }
            lastNackRecoveries = stats.nackRecoveries;
            lastLossPercent = stats.lossPercent;
            
            lastStatsTime = now;
        }
    }
    
    auto endTime = std::chrono::steady_clock::now();
    double totalDuration = std::chrono::duration<double>(endTime - startTime).count();
    
    auto stats = client->getStats();
    double elapsedStats = std::chrono::duration<double>(endTime - lastStatsTime).count();
    if (elapsedStats > 0.0) {
        totalFramesDecoded += (uint64_t)(stats.decodeFps * elapsedStats);
        totalFramesReceived += (uint64_t)(stats.networkFps * elapsedStats);
        if (stats.avgFrameAgeMs > 0.0) {
            totalFrameAgeMsSum += stats.avgFrameAgeMs;
            totalFrameAgeCount++;
        }
        lastNackRecoveries = stats.nackRecoveries;
        lastLossPercent = stats.lossPercent;
    }
    
    client->stop();
    
    bool success = true;
    double finalAvgDecodeFps = totalDuration > 0.0 ? (double)totalFramesDecoded / totalDuration : 0.0;
    double finalAvgNetworkFps = totalDuration > 0.0 ? (double)totalFramesReceived / totalDuration : 0.0;
    double finalAvgFrameAge = totalFrameAgeCount > 0 ? totalFrameAgeMsSum / totalFrameAgeCount : 0.0;
    
    if (finalAvgDecodeFps < 0.9 * gOptions.fps) success = false;
    if (lastLossPercent >= 1.0) success = false;
    
    std::cout << "\n{\"duration_sec\": " << std::fixed << std::setprecision(1) << totalDuration
              << ", \"total_packets\": " << stats.networkPackets
              << ", \"loss_percent\": " << std::setprecision(2) << lastLossPercent
              << ", \"nack_recoveries\": " << lastNackRecoveries
              << ", \"avg_network_fps\": " << std::setprecision(1) << finalAvgNetworkFps
              << ", \"avg_decode_fps\": " << std::setprecision(1) << finalAvgDecodeFps
              << ", \"avg_frame_age_ms\": " << std::setprecision(1) << finalAvgFrameAge
              << ", \"success\": " << (success ? "true" : "false") << "}\n" << std::flush;
              
    return success ? 0 : 1;
}

int main(int argc, char** argv) {
    // Command line parsing
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--connect" && i + 1 < argc) {
            gOptions.host = argv[++i];
        } else if (arg == "--width" && i + 1 < argc) {
            gOptions.width = std::stoi(argv[++i]);
        } else if (arg == "--height" && i + 1 < argc) {
            gOptions.height = std::stoi(argv[++i]);
        } else if (arg == "--fps" && i + 1 < argc) {
            gOptions.fps = std::stoi(argv[++i]);
        } else if (arg == "--tcp") {
            gOptions.tcp = true;
        } else if (arg == "--headless") {
            gOptions.headless = true;
        } else if (arg == "--duration" && i + 1 < argc) {
            gOptions.duration = std::stod(argv[++i]);
        } else if (arg == "--stats-interval" && i + 1 < argc) {
            gOptions.statsInterval = std::stod(argv[++i]);
        } else if (arg == "--auto-discover") {
            gOptions.autoDiscover = true;
        } else if (arg == "--pair-code" && i + 1 < argc) {
            gOptions.pairCode = argv[++i];
        } else if (arg == "--rtsp" && i + 1 < argc) {
            std::string url = argv[++i];
            parseRtspUrl(url, gOptions.host, gOptions.tcp);
        }
    }
    
    if (gOptions.autoDiscover) {
        std::vector<phonecam::DiscoveryDevice> devices = phonecam::runDiscovery(5, gOptions.pairCode);
        if (devices.empty()) {
            std::cerr << "Auto-discovery failed: no devices found.\n";
            return 1;
        }
        const auto& dev = devices.front();
        gOptions.host = dev.senderIp;
        if (dev.protocols.find("stream4k") != std::string::npos) {
            gOptions.width = dev.width;
            gOptions.height = dev.height;
            gOptions.fps = dev.fps;
        } else {
            // Fallback parsing of RTSP URL to extract host and check TCP
            parseRtspUrl(dev.url, gOptions.host, gOptions.tcp);
        }
        std::cout << "Auto-discovery selected: " << dev.deviceName << " (" << gOptions.host << ") using " << dev.protocols << "\n";
    }

    if (gOptions.headless) {
        return runHeadless();
    } else {
        @autoreleasepool {
            NSApplication* app = [NSApplication sharedApplication];
            AppDelegate* delegate = [[AppDelegate alloc] init];
            [app setDelegate:delegate];
            return NSApplicationMain(argc, (const char**)argv);
        }
    }
}
