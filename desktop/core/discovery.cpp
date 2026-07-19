#include "discovery.h"
#include <iostream>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <map>
#include <thread>
#include <stdexcept>
#include <cstring>
#include <sstream>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
using SocketHandle = SOCKET;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
using SocketHandle = int;
constexpr SocketHandle kInvalidSocket = -1;
#endif

namespace phonecam {

constexpr int kDiscoveryPort = 47821;
constexpr int kDiscoveryTimeoutMs = 500;
constexpr const char* kDiscoveryMagic = "PHONECAM";

#if defined(_WIN32)
class SocketRuntime {
public:
  SocketRuntime() {
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
      throw std::runtime_error("WSAStartup failed.");
    }
  }
  ~SocketRuntime() {
    WSACleanup();
  }
};

void closeSocket(SocketHandle socket) {
  closesocket(socket);
}
#else
class SocketRuntime {
public:
  SocketRuntime() = default;
};

void closeSocket(SocketHandle socket) {
  close(socket);
}
#endif

int parseIntOrZero(const std::string& value) {
  try {
    return std::stoi(value);
  } catch (...) {
    return 0;
  }
}

std::string normalizePairCode(const std::string& input) {
  std::string digits;
  for (const unsigned char ch : input) {
    if (std::isdigit(ch)) {
      digits.push_back(static_cast<char>(ch));
    }
    if (digits.size() == 6) {
      break;
    }
  }
  return digits;
}

std::vector<std::string> splitPipe(const std::string& input) {
  std::vector<std::string> parts;
  size_t start = 0;
  while (start <= input.size()) {
    const auto pos = input.find('|', start);
    if (pos == std::string::npos) {
      parts.push_back(input.substr(start));
      break;
    }
    parts.push_back(input.substr(start, pos - start));
    start = pos + 1;
  }
  return parts;
}

bool parseDiscoveryPayload(const std::string& payload, const std::string& senderIp, DiscoveryDevice& device) {
  const auto parts = splitPipe(payload);
  if (parts.size() < 8 || parts[0] != kDiscoveryMagic || parts[1] != "1") {
    return false;
  }
  device.url = parts[2];
  device.width = parseIntOrZero(parts[3]);
  device.height = parseIntOrZero(parts[4]);
  device.fps = parseIntOrZero(parts[5]);
  device.bitrate = parseIntOrZero(parts[6]);
  device.deviceName = parts[7].empty() ? "Android Phone" : parts[7];
  device.pairCode = parts.size() >= 9 ? normalizePairCode(parts[8]) : "";
  device.protocols = parts.size() >= 10 ? parts[9] : "rtsp";
  device.senderIp = senderIp;
  return device.url.rfind("rtsp://", 0) == 0;
}

void sendUdpPayload(const std::string& payload, const std::string& host, int port) {
  SocketRuntime runtime;
  SocketHandle socketFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socketFd == kInvalidSocket) {
    throw std::runtime_error("Failed to create UDP sender socket.");
  }

  sockaddr_in target{};
  target.sin_family = AF_INET;
  target.sin_port = htons(static_cast<uint16_t>(port));
  if (inet_pton(AF_INET, host.c_str(), &target.sin_addr) != 1) {
    closeSocket(socketFd);
    throw std::runtime_error("Invalid UDP target host: " + host);
  }

  const auto sent = sendto(socketFd, payload.data(), static_cast<int>(payload.size()), 0,
                           reinterpret_cast<sockaddr*>(&target), sizeof(target));
  closeSocket(socketFd);
  if (sent < 0 || static_cast<size_t>(sent) != payload.size()) {
    throw std::runtime_error("Failed to send UDP discovery self-test packet.");
  }
}

std::string sockaddrToIp(const sockaddr_in& addr) {
  char buffer[INET_ADDRSTRLEN]{};
  const char* result = inet_ntop(AF_INET, &addr.sin_addr, buffer, sizeof(buffer));
  return result ? std::string(result) : "unknown";
}

std::vector<DiscoveryDevice> runDiscovery(int seconds, const std::string& pairCode) {
  SocketRuntime runtime;
  SocketHandle socketFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socketFd == kInvalidSocket) {
    throw std::runtime_error("Failed to create UDP discovery socket.");
  }

  int reuse = 1;
  setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse), sizeof(reuse));

#if defined(_WIN32)
  DWORD timeout = kDiscoveryTimeoutMs;
  setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
#else
  timeval timeout{};
  timeout.tv_sec = 0;
  timeout.tv_usec = kDiscoveryTimeoutMs * 1000;
  setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
#endif

  sockaddr_in listenAddr{};
  listenAddr.sin_family = AF_INET;
  listenAddr.sin_addr.s_addr = htonl(INADDR_ANY);
  listenAddr.sin_port = htons(kDiscoveryPort);
  if (bind(socketFd, reinterpret_cast<sockaddr*>(&listenAddr), sizeof(listenAddr)) < 0) {
    closeSocket(socketFd);
    throw std::runtime_error("Failed to bind UDP discovery port " + std::to_string(kDiscoveryPort) + ".");
  }

  std::cout << "Listening for PhoneCam discovery beacons on UDP " << kDiscoveryPort
            << " for " << seconds << " seconds";
  if (!pairCode.empty()) {
    std::cout << " with pair code " << pairCode;
  }
  std::cout << "..." << std::endl;

  std::map<std::string, DiscoveryDevice> devicesByUrl;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  while (std::chrono::steady_clock::now() < deadline) {
    char buffer[1024]{};
    sockaddr_in sender{};
#if defined(_WIN32)
    int senderLen = sizeof(sender);
    const int count = recvfrom(socketFd, buffer, static_cast<int>(sizeof(buffer) - 1), 0,
                               reinterpret_cast<sockaddr*>(&sender), &senderLen);
#else
    socklen_t senderLen = sizeof(sender);
    const int count = static_cast<int>(recvfrom(socketFd, buffer, sizeof(buffer) - 1, 0,
                                                reinterpret_cast<sockaddr*>(&sender), &senderLen));
#endif
    if (count <= 0) {
      continue;
    }
    buffer[count] = '\0';

    DiscoveryDevice device;
    if (!parseDiscoveryPayload(std::string(buffer, static_cast<size_t>(count)), sockaddrToIp(sender), device)) {
      continue;
    }
    if (!pairCode.empty() && device.pairCode != pairCode) {
      continue;
    }

    const bool isNew = devicesByUrl.find(device.url) == devicesByUrl.end();
    devicesByUrl[device.url] = device;
    if (isNew) {
      std::cout << "Discovered " << device.deviceName << " at " << device.url
                << " (" << device.width << "x" << device.height << " @ " << device.fps
                << " fps, " << device.bitrate / 1'000'000.0 << " Mbps, sender "
                << device.senderIp;
      if (!device.pairCode.empty()) {
        std::cout << ", pair " << device.pairCode;
      }
      std::cout << ")\n";
    }
  }

  closeSocket(socketFd);

  std::vector<DiscoveryDevice> devices;
  for (const auto& entry : devicesByUrl) {
    devices.push_back(entry.second);
  }
  std::sort(devices.begin(), devices.end(), [](const auto& a, const auto& b) {
    return a.deviceName < b.deviceName;
  });
  std::cout << "Discovery complete: " << devices.size() << " PhoneCam device(s) found." << std::endl;
  return devices;
}

int runDiscoverySelfTest(const std::string& pairCode) {
  const std::string advertisedPairCode = pairCode.empty() ? "123456" : pairCode;
  const std::string payload = "PHONECAM|1|rtsp://127.0.0.1:8554/|1280|720|60|2800000|Synthetic Android|" + advertisedPairCode;
  std::exception_ptr senderError;
  std::thread sender([payload, &senderError] {
    try {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
      sendUdpPayload(payload, "127.0.0.1", kDiscoveryPort);
    } catch (...) {
      senderError = std::current_exception();
    }
  });

  std::vector<DiscoveryDevice> devices;
  try {
    devices = runDiscovery(2, pairCode);
  } catch (...) {
    if (sender.joinable()) {
      sender.join();
    }
    throw;
  }
  sender.join();
  if (senderError) {
    try {
      std::rethrow_exception(senderError);
    } catch (const std::exception& error) {
      std::cerr << "Discovery self-test sender failed: " << error.what() << "\n";
    }
    return 2;
  }
  if (devices.empty()) {
    std::cerr << "Discovery self-test failed: no synthetic beacon received.\n";
    return 2;
  }
  std::cout << "Discovery self-test passed.\n";
  return 0;
}

int runPairCodeMismatchSelfTest() {
  const std::string payload = "PHONECAM|1|rtsp://127.0.0.1:8554/|1280|720|60|2800000|Synthetic Android|123456";
  std::exception_ptr senderError;
  std::thread sender([payload, &senderError] {
    try {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
      sendUdpPayload(payload, "127.0.0.1", kDiscoveryPort);
    } catch (...) {
      senderError = std::current_exception();
    }
  });

  std::vector<DiscoveryDevice> devices;
  try {
    devices = runDiscovery(2, "654321");
  } catch (...) {
    if (sender.joinable()) {
      sender.join();
    }
    throw;
  }
  sender.join();
  if (senderError) {
    try {
      std::rethrow_exception(senderError);
    } catch (const std::exception& error) {
      std::cerr << "Pair-code mismatch self-test sender failed: " << error.what() << "\n";
    }
    return 2;
  }
  if (!devices.empty()) {
    std::cerr << "Pair-code mismatch self-test failed: mismatched beacon was accepted.\n";
    return 2;
  }
  std::cout << "Pair-code mismatch self-test passed.\n";
  return 0;
}

int runAutoDiscoverySelectionSelfTest() {
  const std::string payload = "PHONECAM|1|rtsp://127.0.0.1:8554/|1280|720|60|2800000|Synthetic Android|123456";
  std::exception_ptr senderError;
  std::thread sender([payload, &senderError] {
    try {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
      sendUdpPayload(payload, "127.0.0.1", kDiscoveryPort);
    } catch (...) {
      senderError = std::current_exception();
    }
  });

  std::vector<DiscoveryDevice> devices;
  try {
    devices = runDiscovery(2, "123456");
  } catch (...) {
    if (sender.joinable()) {
      sender.join();
    }
    throw;
  }
  sender.join();
  if (senderError) {
    try {
      std::rethrow_exception(senderError);
    } catch (const std::exception& error) {
      std::cerr << "Auto-discovery selection self-test sender failed: " << error.what() << "\n";
    }
    return 2;
  }
  if (devices.empty()) {
    std::cerr << "Auto-discovery selection self-test failed: no synthetic beacon received.\n";
    return 2;
  }

  const auto& device = devices.front();
  if (device.url != "rtsp://127.0.0.1:8554/") {
    std::cerr << "Auto-discovery selection self-test failed: wrong RTSP URL selected.\n";
    return 2;
  }
  if (device.fps != 60) {
    std::cerr << "Auto-discovery selection self-test failed: advertised FPS was not applied.\n";
    return 2;
  }

  std::cout << "Auto-discovery selection self-test passed.\n";
  return 0;
}

} // namespace phonecam
