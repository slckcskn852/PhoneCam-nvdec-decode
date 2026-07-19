#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <cassert>
#include <cstdlib>
#include <thread>
#include <map>
#include "discovery.h"
#include "control_parser.h"
#include "rtp_hevc.h"
#include "playout_buffer.h"

// Helper to convert hex string to bytes
std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (size_t i = 0; i < hex.length(); i += 2) {
        if (i + 1 < hex.length()) {
            std::string byteString = hex.substr(i, 2);
            uint8_t byte = static_cast<uint8_t>(strtol(byteString.c_str(), nullptr, 16));
            bytes.push_back(byte);
        }
    }
    return bytes;
}

std::string readFile(const std::string& filepath) {
    std::ifstream file(filepath);
    if (!file.is_open()) {
        throw std::runtime_error("Could not open file: " + filepath);
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string s = buffer.str();
    // Trim whitespace
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' ')) {
        s.pop_back();
    }
    return s;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: conformance-tests <vectors_directory>\n";
        return 1;
    }
    std::string dir = argv[1];
    if (dir.back() != '/' && dir.back() != '\\') {
        dir += "/";
    }

    std::cout << "Running conformance tests using vectors from: " << dir << "\n";

    try {
        // Test 1: Connect Message
        {
            std::string jsonStr = readFile(dir + "handshake_connect.hex");
            phonecam::ControlMessage msg = phonecam::parseControlMessage(jsonStr);
            assert(msg.version == "1.0");
            assert(msg.type == "connect");
            assert(msg.width == 3840);
            assert(msg.height == 2160);
            assert(msg.fps == 60);
            assert(msg.transport == "udp");
            assert(msg.streamPort == 5004);
            std::cout << "[PASS] Parse handshake_connect\n";
        }

        // Test 2: Connect Ack Message
        {
            std::string jsonStr = readFile(dir + "handshake_connect_ack.hex");
            phonecam::ControlMessage msg = phonecam::parseControlMessage(jsonStr);
            assert(msg.version == "1.0");
            assert(msg.type == "connect_ack");
            assert(msg.status == "success");
            assert(msg.width == 3840);
            assert(msg.height == 2160);
            assert(msg.fps == 60);
            assert(msg.bitrate == 35000000);
            std::cout << "[PASS] Parse handshake_connect_ack\n";
        }

        // Test 3: NACK Message
        {
            std::string jsonStr = readFile(dir + "nack_request.hex");
            phonecam::ControlMessage msg = phonecam::parseControlMessage(jsonStr);
            assert(msg.version == "1.0");
            assert(msg.type == "nack");
            assert(msg.seqs.size() == 2);
            assert(msg.seqs[0] == 8001);
            assert(msg.seqs[1] == 8002);
            std::cout << "[PASS] Parse nack_request\n";
        }

        // Test 4: Generation helpers
        {
            std::string conn = phonecam::makeConnectMessage(1920, 1080, 30, "tcp", 0);
            phonecam::ControlMessage msg = phonecam::parseControlMessage(conn);
            assert(msg.type == "connect");
            assert(msg.width == 1920);
            assert(msg.height == 1080);
            assert(msg.fps == 30);
            assert(msg.transport == "tcp");
            assert(msg.streamPort == 0);

            std::string start = phonecam::makeStartMessage();
            assert(phonecam::parseControlMessage(start).type == "start");

            std::string stop = phonecam::makeStopMessage();
            assert(phonecam::parseControlMessage(stop).type == "stop");

            std::string ping = phonecam::makePingMessage();
            assert(phonecam::parseControlMessage(ping).type == "ping");

            std::string nack = phonecam::makeNackMessage({100, 200});
            auto nackMsg = phonecam::parseControlMessage(nack);
            assert(nackMsg.type == "nack");
            assert(nackMsg.seqs.size() == 2 && nackMsg.seqs[0] == 100 && nackMsg.seqs[1] == 200);

            std::string pli = phonecam::makePliMessage();
            assert(phonecam::parseControlMessage(pli).type == "pli");

            std::string feedback = phonecam::makeFeedbackMessage(0.05, 4.5);
            auto fbMsg = phonecam::parseControlMessage(feedback);
            assert(fbMsg.type == "feedback");
            assert(fbMsg.lossFraction == 0.05);
            assert(fbMsg.jitterMs == 4.5);

            std::cout << "[PASS] Message generation and round-trip\n";
        }

        // Test 5: Depacketizer - Single NAL
        {
            std::string hexStr = readFile(dir + "rtp_single_nal.hex");
            std::vector<uint8_t> pkt = hexToBytes(hexStr);
            
            phonecam::RtpHevcDepacketizer depack;
            std::vector<uint8_t> result;
            depack.setAccessUnitCallback([&result](const uint8_t* data, size_t len, uint32_t, bool) {
                result.assign(data, data + len);
            });

            depack.feedPacket(pkt.data(), pkt.size());
            depack.flushAll();
            // Expected Annex B prefix + NAL payload
            std::vector<uint8_t> expected = {0x00, 0x00, 0x00, 0x01, 0x40, 0x01, 0x00, 0x11, 0x22, 0x33};
            assert(result == expected);
            std::cout << "[PASS] Depacketize single NAL\n";
        }

        // Test 6: Depacketizer - Fragmented NAL (FU)
        {
            std::string startHex = readFile(dir + "rtp_fu_start.hex");
            std::string endHex = readFile(dir + "rtp_fu_end.hex");
            
            std::vector<uint8_t> pktStart = hexToBytes(startHex);
            std::vector<uint8_t> pktEnd = hexToBytes(endHex);

            phonecam::RtpHevcDepacketizer depack;
            std::vector<uint8_t> result;
            depack.setAccessUnitCallback([&result](const uint8_t* data, size_t len, uint32_t, bool) {
                result.assign(data, data + len);
            });

            depack.feedPacket(pktStart.data(), pktStart.size());
            assert(result.empty()); // Not complete yet

            depack.feedPacket(pktEnd.data(), pktEnd.size());
            std::vector<uint8_t> expected = {0x00, 0x00, 0x00, 0x01, 0x26, 0x01, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff};
            assert(result == expected);
            std::cout << "[PASS] Depacketize fragmented FU NAL\n";
        }

        // Test 7: Discovery Self-Tests
        {
            int rc = phonecam::runDiscoverySelfTest("123456");
            assert(rc == 0);
            rc = phonecam::runPairCodeMismatchSelfTest();
            assert(rc == 0);
            rc = phonecam::runAutoDiscoverySelectionSelfTest();
            assert(rc == 0);
            std::cout << "[PASS] Discovery self-tests\n";
        }

        // Test 8: Sequence wrap and NACK recovery under loss
        {
            phonecam::RtpHevcDepacketizer depack;
            std::vector<uint16_t> nackedSeqs;
            depack.setNackCallback([&nackedSeqs](const std::vector<uint16_t>& seqs) {
                nackedSeqs.insert(nackedSeqs.end(), seqs.begin(), seqs.end());
            });
            
            auto makeDummyRtp = [](uint16_t seq, uint32_t ts) {
                std::vector<uint8_t> pkt(12 + 2);
                pkt[0] = 0x80;
                pkt[1] = 0x60;
                pkt[2] = (seq >> 8) & 0xFF;
                pkt[3] = seq & 0xFF;
                pkt[4] = (ts >> 24) & 0xFF;
                pkt[5] = (ts >> 16) & 0xFF;
                pkt[6] = (ts >> 8) & 0xFF;
                pkt[7] = ts & 0xFF;
                pkt[8] = 0; pkt[9] = 0; pkt[10] = 0; pkt[11] = 1;
                pkt[12] = 1 << 1;
                pkt[13] = 1;
                return pkt;
            };

            uint16_t seq = 0;
            uint32_t ts = 1000;
            const uint32_t totalPackets = 140000;
            uint64_t expectedReceived = 0;
            
            std::map<uint16_t, std::vector<uint8_t>> lostPackets;
            
            for (uint32_t i = 0; i < totalPackets; ++i) {
                auto pkt = makeDummyRtp(seq, ts);
                
                if (i % 1000 == 500) {
                    lostPackets[seq] = pkt;
                } else {
                    depack.feedPacket(pkt.data(), pkt.size());
                    expectedReceived++;
                }
                
                if (!nackedSeqs.empty()) {
                    for (auto nackSeq : nackedSeqs) {
                        auto it = lostPackets.find(nackSeq);
                        if (it != lostPackets.end()) {
                            depack.feedPacket(it->second.data(), it->second.size());
                            expectedReceived++;
                            lostPackets.erase(it);
                        }
                    }
                    nackedSeqs.clear();
                }

                seq++;
                if (i % 54 == 0) {
                    ts += 90000 / 60;
                }
            }
            
            depack.flushAll();
            
            auto stats = depack.statsSnapshotAndReset();
            assert(stats.packetsReceived == expectedReceived);
            assert(lostPackets.empty());
            assert(stats.nackRecoveries == 140);
            
            std::cout << "[PASS] Sequence wrap and NACK recovery under loss (140,000 packets)\n";
        }

        // Test 9: NACK retry limit and give-up logic
        {
            phonecam::RtpHevcDepacketizer depack;
            std::vector<uint16_t> nackedSeqs;
            depack.setNackCallback([&nackedSeqs](const std::vector<uint16_t>& seqs) {
                nackedSeqs.insert(nackedSeqs.end(), seqs.begin(), seqs.end());
            });
            
            auto makeDummyRtp = [](uint16_t seq, uint32_t ts) {
                std::vector<uint8_t> pkt(12 + 2);
                pkt[0] = 0x80; pkt[1] = 0x60;
                pkt[2] = (seq >> 8) & 0xFF; pkt[3] = seq & 0xFF;
                pkt[4] = (ts >> 24) & 0xFF; pkt[5] = (ts >> 16) & 0xFF; pkt[6] = (ts >> 8) & 0xFF; pkt[7] = ts & 0xFF;
                pkt[8] = 0; pkt[9] = 0; pkt[10] = 0; pkt[11] = 1;
                pkt[12] = 1 << 1; pkt[13] = 1;
                return pkt;
            };

            auto pkt0 = makeDummyRtp(0, 1000);
            depack.feedPacket(pkt0.data(), pkt0.size());
            
            for (uint16_t seq = 2; seq <= 50; ++seq) {
                auto pkt = makeDummyRtp(seq, 1000);
                depack.feedPacket(pkt.data(), pkt.size());
                std::this_thread::sleep_for(std::chrono::milliseconds(16));
            }
            
            auto stats = depack.statsSnapshotAndReset();
            assert(stats.packetsLost >= 1);
            std::cout << "[PASS] NACK retry limit and give-up logic\n";
        }

        std::cout << "All conformance tests passed successfully!\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Test failed with exception: " << e.what() << "\n";
        return 1;
    }
}
