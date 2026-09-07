#include "playout_buffer.h"
#include "rtp_hevc.h"
#include "phonecam_client.h"
#include "receiver_connection.h"
#include "latency_controller.h"
#include "control_parser.h"
#include <limits>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <vector>
#include <thread>
#include <atomic>

using namespace phonecam;
using namespace std::chrono_literals;
static void require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
static std::vector<uint8_t> packet(uint16_t seq, uint32_t ts, bool marker, std::vector<uint8_t> payload) {
    std::vector<uint8_t> data{0x80, static_cast<uint8_t>(96 | (marker ? 128 : 0)),
        static_cast<uint8_t>(seq >> 8), static_cast<uint8_t>(seq),
        static_cast<uint8_t>(ts >> 24), static_cast<uint8_t>(ts >> 16), static_cast<uint8_t>(ts >> 8), static_cast<uint8_t>(ts),
        0x50, 0x43, 0x4b, 0x36};
    data.insert(data.end(), payload.begin(), payload.end()); return data;
}
static void coreTests() {
    for (const auto* ip : {"192.168.1.42", "10.0.0.5", "172.16.8.9"})
        require(decodeConnectionCode(makeConnectionCode(ip)) == ip, "PC code round trip failed");
    require(makeConnectionCode("192.168.1.42") == "PC-R2M0-2AGG", "shared PC code vector mismatch");
    require(decodeConnectionCode("PC-ZZZZ-ZZZZ").empty(), "PC code checksum bypassed");
    require(makeConnectionCode("not an IP").empty(), "invalid IPv4 encoded");
    LatencyController latency;
    require(latency.delay() == 10 && latency.update(0, 0) == 9, "latency did not decrease gradually");
    require(latency.update(40, .1) == 50, "jitter did not grow bounded delay immediately");
    require(latency.update(std::numeric_limits<double>::infinity(), 0) == 50, "invalid jitter changed delay");
    for (int i=0; i<100; ++i) latency.update(0, 0);
    require(latency.delay() == 5, "adaptive delay floor failed");
    latency.reset(); require(latency.delay() == 10, "delay reset failed");
    require(JsonParser::parse(std::string(20, '[') + std::string(20, ']')).isNull(), "deep JSON accepted");
    require(JsonParser::parse(std::string(65536, ' ')).isNull(), "oversized JSON accepted");
    auto hostile = parseControlMessage(R"({"type":"connect_ack","selected_ladder":{"width":1e100,"height":-1,"fps":1.5},"seqs":[-1,65536,2]})");
    require(hostile.width == 0 && hostile.height == 0 && hostile.seqs.size() == 1 && hostile.seqs[0] == 2, "unsafe control numbers accepted");
    PlayoutBuffer aged(0, 20, 100, 5);
    aged.push({1}, 1, true);
    std::this_thread::sleep_for(30ms);
    require(!aged.push({2}, 2, true), "stale compressed frame was retained");
    PlayoutFrame recent;
    require(aged.pop(recent, 0ms) && recent.rtpTimestamp == 2, "stale frame replayed");
    PlayoutBuffer intentional(200, 20, 100, 5);
    intentional.push({1}, 1, true);
    std::this_thread::sleep_for(30ms);
    require(intentional.push({2}, 2, true), "fixed manual jitter delay was treated as stale backlog");
    intentional.setTargetDelay(0);
    require(intentional.pop(recent, 0ms) && recent.rtpTimestamp == 1, "manual-delay frame was discarded");
    PlayoutBuffer bounded(0, 4, 100);
    for (uint32_t i = 0; i < 100000; ++i) {
        bounded.push(std::vector<uint8_t>(30), i, true);
        require(bounded.queuedFrames() <= 3 && bounded.queuedBytes() <= 100, "playout grew beyond byte budget");
    }
    require(!bounded.push(std::vector<uint8_t>(101), 100001, true), "oversized AU accepted");
    PlayoutFrame frame;
    require(bounded.pop(frame, 0ms) && frame.rtpTimestamp == 99997, "old frames were not evicted");
    bounded.clear(); require(bounded.queuedBytes() == 0, "clear retained byte accounting");
    bounded.push({1}, 0xfffffff0, true); bounded.push({2}, 16, true);
    require(bounded.pop(frame, 0ms) && frame.rtpTimestamp == 0xfffffff0, "timestamp wrap reordered old frame");
    require(bounded.pop(frame, 0ms) && frame.rtpTimestamp == 16, "timestamp wrap lost new frame");
    PlayoutBuffer delayed(1000);
    delayed.push({1}, 0, true); delayed.setTargetDelay(0);
    require(delayed.pop(frame, 0ms), "delay update did not release queued frame");

    RtpHevcDepacketizer depack(16, 4);
    bool complete = true; size_t maxSize = 0; int callbacks = 0;
    depack.setAccessUnitCallback([&](const uint8_t*, size_t len, uint32_t, bool good) { complete = good; maxSize = std::max(maxSize, len); ++callbacks; });
    auto feed = [&](std::vector<uint8_t> data) { depack.feedPacket(data.data(), data.size()); };
    // A truncated FU followed by the next timestamp must never be labelled complete.
    feed(packet(0, 100, false, {0x62, 1, 0x93, 1, 2}));
    feed(packet(1, 200, true, {0x26, 1, 3, 4}));
    require(callbacks >= 2, "lost AU was not surfaced for recovery");
    // Unbounded same-timestamp single NAL input used to grow forever.
    depack.reset(); callbacks = 0;
    std::vector<uint8_t> nal(60000, 1); nal[0] = 0x26;
    for (uint16_t i = 0; i < 300; ++i) feed(packet(i, 300, i == 299, nal));
    require(callbacks == 1 && !complete, "oversized access unit was marked complete");
    require(maxSize <= RtpHevcDepacketizer::kMaxAccessUnitBytes, "access unit exceeded memory cap");
    depack.reset(); callbacks = 0;
    std::vector<uint8_t> fragment(60000, 1); fragment[0] = 0x62; fragment[2] = 0x93;
    feed(packet(0, 400, false, fragment)); fragment[2] = 0x13;
    for (uint16_t i = 1; i < 300; ++i) feed(packet(i, 400, i == 299, fragment));
    require(callbacks == 1 && !complete, "oversized fragmented NAL was marked complete");
    depack.reset();
    size_t nacks = 0;
    depack.setNackCallback([&](const auto& seqs) { nacks += seqs.size(); });
    feed(packet(0, 0, true, {0x26, 1})); feed(packet(30000, 1, true, {0x26, 1}));
    require(nacks <= 4, "large sequence jump caused unbounded NACK work");
    depack.feedPacket(nullptr, 100);
    feed({0x80});
    std::cout << "PASS: bounded queues, wrap, damaged AUs, oversized FU/NAL, bounded NACKs\n";
}
static void closeSocket(socket_t socket) {
#if defined(_WIN32)
    closesocket(socket);
#else
    close(socket);
#endif
}
static void networkTests() {
#if defined(_WIN32)
    WSADATA data; require(WSAStartup(MAKEWORD(2, 2), &data) == 0, "WSAStartup failed");
#endif
    // EOF and malicious record lengths must still join all threads on stop/destruction.
    for (int cycle = 0; cycle < 30; ++cycle) {
        socket_t server = socket(AF_INET, SOCK_STREAM, 0);
        require(server != INVALID_SOCKET_VAL, "server socket failed");
        sockaddr_in address{}; address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        require(bind(server, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0, "loopback bind failed");
#if defined(_WIN32)
        int length = sizeof(address);
#else
        socklen_t length = sizeof(address);
#endif
        getsockname(server, reinterpret_cast<sockaddr*>(&address), &length);
        listen(server, 1);
        std::thread peer([&] {
            auto socket = accept(server, nullptr, nullptr);
            if (socket == INVALID_SOCKET_VAL) return;
            if (cycle % 2) {
                const uint8_t record[]{1, 0, 0x7f, 0xff, 0xff, 0xff};
                send(socket, reinterpret_cast<const char*>(record), sizeof(record), 0);
            }
            closeSocket(socket);
        });
        PhoneCamClient client(TransportMode::TCP, "127.0.0.1", ntohs(address.sin_port));
        bool started = client.start(1920, 1080, 240);
        peer.join(); closeSocket(server);
        require(started, "client failed to start");
        std::this_thread::sleep_for(10ms);
        auto before = std::chrono::steady_clock::now();
        client.stop(); client.stop();
        require(std::chrono::steady_clock::now() - before < 1s, "disconnect cleanup blocked");
    }
    // Exercise the outbound-phone path, auto negotiation, media and repeated reconnects.
    ReceiverListener receiver(0);
    for (int cycle = 0; cycle < 10; ++cycle) {
        std::atomic<bool> handshake{false};
        std::thread phone([&] {
            auto fd = socket(AF_INET, SOCK_STREAM, 0);
            sockaddr_in target{}; target.sin_family = AF_INET; target.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            target.sin_port = htons(receiver.port());
            if (connect(fd, reinterpret_cast<sockaddr*>(&target), sizeof(target)) != 0) { closeSocket(fd); return; }
#if defined(_WIN32)
            DWORD timeout = 2000; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<char*>(&timeout), sizeof(timeout));
#else
            timeval timeout{2, 0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#endif
            auto write = [&](const std::vector<uint8_t>& bytes) {
                size_t offset = 0;
                while (offset < bytes.size()) {
                    int n = send(fd, reinterpret_cast<const char*>(bytes.data()+offset), static_cast<int>(bytes.size()-offset), 0);
                    if (n <= 0) return false;
                    offset += n;
                }
                return true;
            };
            auto read = [&](uint8_t* bytes, size_t count) {
                size_t offset=0;
                while (offset<count) {
                    int n=recv(fd, reinterpret_cast<char*>(bytes+offset), static_cast<int>(count-offset), 0);
                    if (n<=0) return false;
                    offset+=n;
                }
                return true;
            };
            auto readControl = [&]() -> ControlMessage {
                uint8_t header[6]{};
                if (!read(header, 6)) return {};
                uint32_t size = (uint32_t(header[2])<<24)|(uint32_t(header[3])<<16)|(uint32_t(header[4])<<8)|header[5];
                if (size > 65535) return {};
                std::string body(size, ' ');
                if (!read(reinterpret_cast<uint8_t*>(body.data()), size)) return {};
                return parseControlMessage(body);
            };
            auto sendRecord = [&](uint8_t channel, const std::vector<uint8_t>& payload) {
                uint32_t n = static_cast<uint32_t>(payload.size());
                std::vector<uint8_t> record{channel,0,uint8_t(n>>24),uint8_t(n>>16),uint8_t(n>>8),uint8_t(n)};
                record.insert(record.end(), payload.begin(), payload.end()); return write(record);
            };
            std::string hello = kReverseHello;
            write(std::vector<uint8_t>(hello.begin(),hello.end()));
            auto request = readControl();
            if (request.type == "connect" && request.width == 0 && request.height == 0 && request.fps == 0) {
                std::string ack = R"({"type":"connect_ack","status":"success","selected_ladder":{"width":1920,"height":1080,"fps":60}})";
                sendRecord(1, std::vector<uint8_t>(ack.begin(),ack.end()));
                auto start = readControl();
                handshake = start.type == "start";
                // A dependent frame before the first IDR must be withheld.
                sendRecord(2, packet(0, 0, true, {0x02, 1, 7}));
                sendRecord(2, packet(1, 1500, true, {0x26, 1, 7}));
                std::this_thread::sleep_for(30ms);
            }
            closeSocket(fd);
        });
        std::string peer;
        auto accepted = receiver.acceptPhone(peer, 2s);
        PhoneCamClient client(TransportMode::TCP, "127.0.0.1", receiver.port());
        std::atomic<int> frames{0};
        client.setFrameCallback([&](const uint8_t*, size_t, uint32_t ts, bool) { if (ts==1500) ++frames; else frames=-100; });
        bool started = accepted != INVALID_SOCKET_VAL && client.start(0,0,0,accepted);
        phone.join(); client.stop();
        require(started && handshake && peer=="127.0.0.1", "reverse connection/automatic handshake failed");
        require(frames == 1 && client.negotiatedFormat().fps == 60, "reverse media or initial IDR gate failed");
    }
    // Unrelated services must not receive camera-control commands.
    auto bad = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in target{}; target.sin_family=AF_INET; target.sin_addr.s_addr=htonl(INADDR_LOOPBACK); target.sin_port=htons(receiver.port());
    require(connect(bad, reinterpret_cast<sockaddr*>(&target), sizeof(target)) == 0, "bad peer setup failed");
    send(bad, "notphone!!!", 11, 0);
    std::string rejected;
    require(receiver.acceptPhone(rejected, 100ms) == INVALID_SOCKET_VAL, "wrong protocol preface accepted");
    closeSocket(bad);
    PhoneCamClient invalid(TransportMode::UDP, "bad-host");
    require(!invalid.start(), "invalid address accepted"); invalid.stop();
#if defined(_WIN32)
    WSACleanup();
#endif
    std::cout << "PASS: 30 TCP EOF/hostile-length cycles and idempotent cleanup\n";
}
int main(int argc, char**) {
    try { if (argc > 1) networkTests(); else coreTests(); return 0; }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
