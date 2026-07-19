#include "control_parser.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <atomic>
#include <thread>
#include <chrono>
#include <map>
#include <mutex>
#include <random>
#include <cstring>
#include <cstdint>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

struct NalUnit {
    std::vector<uint8_t> data;
};

struct Frame {
    std::vector<NalUnit> nals;
};

// Simple raw HEVC parser
std::vector<Frame> parseHevcFile(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("Failed to open HEVC file: " + path);
    }
    std::vector<uint8_t> buffer((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    
    std::vector<NalUnit> nals;
    size_t i = 0;
    while (i < buffer.size()) {
        if (i + 4 <= buffer.size() && buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 0 && buffer[i+3] == 1) {
            size_t start = i + 4;
            i = start;
            while (i < buffer.size()) {
                if (i + 4 <= buffer.size() && buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 0 && buffer[i+3] == 1) {
                    break;
                }
                if (i + 3 <= buffer.size() && buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 1) {
                    break;
                }
                i++;
            }
            size_t len = i - start;
            while (len > 0 && buffer[start + len - 1] == 0) {
                len--;
            }
            if (len > 0) {
                nals.push_back({std::vector<uint8_t>(buffer.begin() + start, buffer.begin() + start + len)});
            }
        } else if (i + 3 <= buffer.size() && buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 1) {
            size_t start = i + 3;
            i = start;
            while (i < buffer.size()) {
                if (i + 4 <= buffer.size() && buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 0 && buffer[i+3] == 1) {
                    break;
                }
                if (i + 3 <= buffer.size() && buffer[i] == 0 && buffer[i+1] == 0 && buffer[i+2] == 1) {
                    break;
                }
                i++;
            }
            size_t len = i - start;
            while (len > 0 && buffer[start + len - 1] == 0) {
                len--;
            }
            if (len > 0) {
                nals.push_back({std::vector<uint8_t>(buffer.begin() + start, buffer.begin() + start + len)});
            }
        } else {
            i++;
        }
    }
    
    std::vector<Frame> frames;
    Frame currentFrame;
    bool hasSlice = false;
    
    for (const auto& nal : nals) {
        if (nal.data.empty()) continue;
        uint8_t type = (nal.data[0] >> 1) & 0x3F;
        bool isSlice = (type <= 9) || (type >= 16 && type <= 21);
        bool isNewFrameStart = (type == 35) || (type == 32) || (isSlice && hasSlice);
        
        if (isNewFrameStart && (!currentFrame.nals.empty())) {
            frames.push_back(currentFrame);
            currentFrame = Frame();
            hasSlice = false;
        }
        
        currentFrame.nals.push_back(nal);
        if (isSlice) {
            hasSlice = true;
        }
    }
    if (!currentFrame.nals.empty()) {
        frames.push_back(currentFrame);
    }
    
    return frames;
}

// Packetizer helpers
std::vector<uint8_t> makeSingleRtpPacket(uint16_t seq, uint32_t timestamp, bool marker, const std::vector<uint8_t>& nalData) {
    std::vector<uint8_t> packet(12 + nalData.size());
    packet[0] = 0x80;
    packet[1] = (marker ? 0x80 : 0x00) | 96;
    packet[2] = (seq >> 8) & 0xFF;
    packet[3] = seq & 0xFF;
    packet[4] = (timestamp >> 24) & 0xFF;
    packet[5] = (timestamp >> 16) & 0xFF;
    packet[6] = (timestamp >> 8) & 0xFF;
    packet[7] = timestamp & 0xFF;
    packet[8] = 0x12; packet[9] = 0x34; packet[10] = 0x56; packet[11] = 0x78;
    std::memcpy(packet.data() + 12, nalData.data(), nalData.size());
    return packet;
}

std::vector<std::vector<uint8_t>> makeFuRtpPackets(uint16_t& seq, uint32_t timestamp, bool frameLast, const std::vector<uint8_t>& nalData) {
    std::vector<std::vector<uint8_t>> packets;
    uint8_t nalHeaderH = nalData[0];
    uint8_t nalHeaderL = nalData[1];
    uint8_t nalType = (nalHeaderH >> 1) & 0x3F;
    
    size_t payloadOffset = 2;
    size_t totalPayloadLen = nalData.size() - 2;
    constexpr size_t kMaxChunkSize = 1380;
    
    size_t remaining = totalPayloadLen;
    while (remaining > 0) {
        size_t chunk = std::min(remaining, kMaxChunkSize);
        bool start = (payloadOffset == 2);
        bool end = (remaining <= kMaxChunkSize);
        bool marker = frameLast && end;
        
        std::vector<uint8_t> packet(12 + 3 + chunk);
        packet[0] = 0x80;
        packet[1] = (marker ? 0x80 : 0x00) | 96;
        packet[2] = (seq >> 8) & 0xFF;
        packet[3] = seq & 0xFF;
        packet[4] = (timestamp >> 24) & 0xFF;
        packet[5] = (timestamp >> 16) & 0xFF;
        packet[6] = (timestamp >> 8) & 0xFF;
        packet[7] = timestamp & 0xFF;
        packet[8] = 0x12; packet[9] = 0x34; packet[10] = 0x56; packet[11] = 0x78;
        
        packet[12] = (nalHeaderH & 0x81) | (49 << 1);
        packet[13] = nalHeaderL;
        packet[14] = (start ? 0x80 : 0x00) | (end ? 0x40 : 0x00) | nalType;
        
        std::memcpy(packet.data() + 15, nalData.data() + payloadOffset, chunk);
        packets.push_back(packet);
        
        seq++;
        payloadOffset += chunk;
        remaining -= chunk;
    }
    return packets;
}

// Global control state
std::atomic<bool> gControlRunning{true};
std::atomic<bool> gStreamingStarted{false};
std::string gTargetHost = "127.0.0.1";
int gTargetMediaPort = 5004;

std::mutex gHistoryMutex;
std::vector<std::vector<uint8_t>> gHistoryBuffer(65536);
int gMediaSocket = -1;

#include <errno.h>

void controlThreadFunc() {
    int controlSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (controlSock < 0) {
        std::cerr << "Failed to create control socket: " << strerror(errno) << "\n";
        return;
    }
    
    int reuse = 1;
    setsockopt(controlSock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    sockaddr_in localCtrl{};
    localCtrl.sin_family = AF_INET;
    localCtrl.sin_addr.s_addr = htonl(INADDR_ANY);
    localCtrl.sin_port = htons(47822);
    
    if (bind(controlSock, (sockaddr*)&localCtrl, sizeof(localCtrl)) < 0) {
        std::cerr << "Failed to bind control socket to port 47822: " << strerror(errno) << "\n";
        close(controlSock);
        return;
    }
    
    std::vector<char> buffer(65536);
    while (gControlRunning) {
        sockaddr_in clientAddr{};
        socklen_t addrLen = sizeof(clientAddr);
        int bytes = recvfrom(controlSock, buffer.data(), buffer.size() - 1, 0, (sockaddr*)&clientAddr, &addrLen);
        if (bytes <= 0) break;
        buffer[bytes] = '\0';
        
        std::string json(buffer.data(), bytes);
        phonecam::ControlMessage msg = phonecam::parseControlMessage(json);
        
        char clientIp[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &clientAddr.sin_addr, clientIp, sizeof(clientIp));
        
        if (msg.type == "connect") {
            gTargetHost = clientIp;
            gTargetMediaPort = msg.streamPort;
            std::cout << "Connect request from " << clientIp << ", target media port: " << gTargetMediaPort << "\n";
            
            std::string reply = "{\"version\":\"1.0\",\"type\":\"connect_ack\",\"status\":\"success\",\"selected_ladder\":{\"width\":3840,\"height\":2160,\"fps\":60,\"bitrate\":35000000}}";
            sendto(controlSock, reply.data(), reply.size(), 0, (sockaddr*)&clientAddr, addrLen);
        } else if (msg.type == "start") {
            std::cout << "Start streaming request received\n";
            gStreamingStarted = true;
            std::string reply = "{\"version\":\"1.0\",\"type\":\"start_ack\",\"status\":\"success\"}";
            sendto(controlSock, reply.data(), reply.size(), 0, (sockaddr*)&clientAddr, addrLen);
        } else if (msg.type == "stop") {
            std::cout << "Stop streaming request received\n";
            gStreamingStarted = false;
            std::string reply = "{\"version\":\"1.0\",\"type\":\"stop_ack\",\"status\":\"success\"}";
            sendto(controlSock, reply.data(), reply.size(), 0, (sockaddr*)&clientAddr, addrLen);
        } else if (msg.type == "ping") {
            std::string reply = "{\"version\":\"1.0\",\"type\":\"pong\",\"device_name\":\"Synthetic Android\",\"capabilities\":{\"ladder\":[{\"width\":3840,\"height\":2160,\"fps\":60,\"bitrate\":35000000}]},\"state\":\"streaming\"}";
            sendto(controlSock, reply.data(), reply.size(), 0, (sockaddr*)&clientAddr, addrLen);
        } else if (msg.type == "nack") {
            std::lock_guard<std::mutex> lock(gHistoryMutex);
            sockaddr_in mediaDest{};
            mediaDest.sin_family = AF_INET;
            mediaDest.sin_port = htons(gTargetMediaPort);
            inet_pton(AF_INET, gTargetHost.c_str(), &mediaDest.sin_addr);
            
            for (auto seq : msg.seqs) {
                if (seq < gHistoryBuffer.size() && !gHistoryBuffer[seq].empty() && gMediaSocket >= 0) {
                    sendto(gMediaSocket, gHistoryBuffer[seq].data(), gHistoryBuffer[seq].size(), 0, (sockaddr*)&mediaDest, sizeof(mediaDest));
                }
            }
        } else if (msg.type == "pli") {
            std::cout << "PLI received (Picture Loss Indication)\n";
        }
    }
    
    close(controlSock);
}

int main(int argc, char** argv) {
    std::string hevcPath = "";
    double lossPct = 0.0;
    
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--file" && i + 1 < argc) {
            hevcPath = argv[++i];
        } else if (arg == "--inject-loss" && i + 1 < argc) {
            lossPct = std::stod(argv[++i]);
        }
    }
    
    if (hevcPath.empty()) {
        std::cerr << "Usage: phonecam-soak-sender --file <path.hevc> [--inject-loss <pct>]\n" << std::flush;
        return 1;
    }
    
    gMediaSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (gMediaSocket < 0) {
        std::cerr << "Failed to create media socket\n" << std::flush;
        return 1;
    }
    
    std::thread controlThread(controlThreadFunc);
    
    std::cout << "Loading HEVC file: " << hevcPath << "\n" << std::flush;
    std::vector<Frame> frames;
    try {
        frames = parseHevcFile(hevcPath);
    } catch (const std::exception& e) {
        std::cerr << "Failed to parse: " << e.what() << "\n" << std::flush;
        gControlRunning = false;
        // wake control thread
        int dummySock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        sockaddr_in localCtrl{};
        localCtrl.sin_family = AF_INET;
        inet_pton(AF_INET, "127.0.0.1", &localCtrl.sin_addr);
        localCtrl.sin_port = htons(47822);
        sendto(dummySock, "exit", 4, 0, (sockaddr*)&localCtrl, sizeof(localCtrl));
        close(dummySock);
        if (controlThread.joinable()) controlThread.join();
        return 1;
    }
    
    std::cout << "Loaded " << frames.size() << " frames from file.\n" << std::flush;
    if (frames.empty()) {
        std::cerr << "No valid frames found in file.\n" << std::flush;
        gControlRunning = false;
        // wake control thread
        int dummySock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        sockaddr_in localCtrl{};
        localCtrl.sin_family = AF_INET;
        inet_pton(AF_INET, "127.0.0.1", &localCtrl.sin_addr);
        localCtrl.sin_port = htons(47822);
        sendto(dummySock, "exit", 4, 0, (sockaddr*)&localCtrl, sizeof(localCtrl));
        close(dummySock);
        if (controlThread.joinable()) controlThread.join();
        return 1;
    }
    
    std::default_random_engine generator(12345); // Seeded for deterministic loss behavior in conformance
    std::uniform_real_distribution<double> distribution(0.0, 100.0);
    
    std::cout << "Waiting for control connection on port 47822...\n" << std::flush;
    while (!gStreamingStarted) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    std::cout << "Starting streaming loop at 60 fps with " << lossPct << "% injected loss...\n";
    
    sockaddr_in mediaDest{};
    mediaDest.sin_family = AF_INET;
    mediaDest.sin_port = htons(gTargetMediaPort);
    inet_pton(AF_INET, gTargetHost.c_str(), &mediaDest.sin_addr);
    
    uint16_t seq = 0;
    uint32_t timestamp = 0;
    size_t frameIndex = 0;
    
    auto frameInterval = std::chrono::microseconds(16666); // ~60 fps
    auto nextFrameTime = std::chrono::steady_clock::now();
    
    while (gStreamingStarted) {
        const auto& frame = frames[frameIndex];
        
        // Packetize the frame
        std::vector<std::vector<uint8_t>> framePackets;
        for (size_t i = 0; i < frame.nals.size(); ++i) {
            const auto& nal = frame.nals[i];
            bool frameLast = (i == frame.nals.size() - 1);
            if (nal.data.size() <= 1400) {
                framePackets.push_back(makeSingleRtpPacket(seq, timestamp, frameLast, nal.data));
                seq++;
            } else {
                auto fus = makeFuRtpPackets(seq, timestamp, frameLast, nal.data);
                framePackets.insert(framePackets.end(), fus.begin(), fus.end());
            }
        }
        
        // Send packets
        for (const auto& packet : framePackets) {
            uint16_t packetSeq = (packet[2] << 8) | packet[3];
            {
                std::lock_guard<std::mutex> lock(gHistoryMutex);
                gHistoryBuffer[packetSeq] = packet;
            }
            
            // Random loss injection
            double roll = distribution(generator);
            if (lossPct > 0.0 && roll < lossPct) {
                // Drop packet
                continue;
            }
            
            sendto(gMediaSocket, packet.data(), packet.size(), 0, (sockaddr*)&mediaDest, sizeof(mediaDest));
        }
        
        // Advance counters
        timestamp += 1500; // 90000 / 60
        frameIndex = (frameIndex + 1) % frames.size();
        
        // Sleep to maintain rate
        nextFrameTime += frameInterval;
        std::this_thread::sleep_until(nextFrameTime);
    }
    
    std::cout << "Streaming finished.\n";
    
    gControlRunning = false;
    // Wake control recvfrom by closing the socket or letting it timeout
    // In our case we can close it from main or just join
    int dummySock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    sockaddr_in localCtrl{};
    localCtrl.sin_family = AF_INET;
    inet_pton(AF_INET, "127.0.0.1", &localCtrl.sin_addr);
    localCtrl.sin_port = htons(47822);
    sendto(dummySock, "exit", 4, 0, (sockaddr*)&localCtrl, sizeof(localCtrl));
    close(dummySock);
    
    if (controlThread.joinable()) {
        controlThread.join();
    }
    
    close(gMediaSocket);
    return 0;
}
