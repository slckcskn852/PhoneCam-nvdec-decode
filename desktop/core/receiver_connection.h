#pragma once
#include "phonecam_client.h"
#include <memory>

namespace phonecam {
constexpr int kReceiverPort = 47823;
constexpr const char* kReceiverServiceType = "_phonecam._tcp";
constexpr const char* kReverseHello = "PHONECAM/2\n";
std::vector<std::string> localIPv4Addresses();
std::string computerName();
// Address convenience code with a typo checksum. It is not an authentication secret.
std::string makeConnectionCode(const std::string& ipv4);
std::string decodeConnectionCode(const std::string& code);

class ReceiverListener {
public:
    explicit ReceiverListener(int port = kReceiverPort);
    ~ReceiverListener();
    ReceiverListener(const ReceiverListener&) = delete;
    ReceiverListener& operator=(const ReceiverListener&) = delete;
    socket_t acceptPhone(std::string& peer, std::chrono::milliseconds timeout);
    int port() const { return port_; }
private:
    socket_t socket_ = INVALID_SOCKET_VAL;
    int port_ = 0;
    bool runtime_ = false;
};

class ReceiverAdvertisement {
public:
    ReceiverAdvertisement(const std::string& name, int port);
    ~ReceiverAdvertisement();
    ReceiverAdvertisement(const ReceiverAdvertisement&) = delete;
    ReceiverAdvertisement& operator=(const ReceiverAdvertisement&) = delete;
private:
    struct State;
    State* state_ = nullptr;
};
}
