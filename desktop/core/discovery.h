#pragma once
#include <string>
#include <vector>

namespace phonecam {

struct DiscoveryDevice {
  std::string url;
  std::string senderIp;
  std::string deviceName;
  int width = 0;
  int height = 0;
  int fps = 0;
  int bitrate = 0;
  std::string pairCode;
  std::string protocols; // e.g. "rtsp,stream4k"
};

std::string normalizePairCode(const std::string& input);

bool parseDiscoveryPayload(const std::string& payload, const std::string& senderIp, DiscoveryDevice& device);

void sendUdpPayload(const std::string& payload, const std::string& host, int port);

std::vector<DiscoveryDevice> runDiscovery(int seconds, const std::string& pairCode = "");

// Self-test functions
int runDiscoverySelfTest(const std::string& pairCode);
int runPairCodeMismatchSelfTest();
int runAutoDiscoverySelectionSelfTest();

} // namespace phonecam
