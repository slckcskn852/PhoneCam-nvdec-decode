#include "receiver_connection.h"
#include <algorithm>
#include <array>
#include <cctype>
#include <cstring>
#include <iostream>
#include <stdexcept>
#if defined(_WIN32)
#include <iphlpapi.h>
#include <windns.h>
#else
#include <ifaddrs.h>
#include <net/if.h>
#endif
#if defined(__APPLE__)
#include <dns_sd.h>
#endif

namespace phonecam {
namespace {
void closeConnectionSocket(socket_t fd) {
#if defined(_WIN32)
    closesocket(fd);
#else
    close(fd);
#endif
}
bool canRead(socket_t fd, std::chrono::milliseconds delay) {
    fd_set set; FD_ZERO(&set); FD_SET(fd, &set);
    timeval tv{};
    tv.tv_sec = static_cast<decltype(tv.tv_sec)>(delay.count() / 1000);
    tv.tv_usec = static_cast<decltype(tv.tv_usec)>(delay.count() % 1000 * 1000);
    return select(static_cast<int>(fd + 1), &set, nullptr, nullptr, &tv) > 0;
}
constexpr char alphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
uint8_t checksum(uint32_t ip) {
    uint8_t result = 0x5a;
    for (int shift = 24; shift >= 0; shift -= 8) {
        result ^= static_cast<uint8_t>(ip >> shift);
        for (int bit = 0; bit < 8; ++bit) result = (result & 0x80) ? (result << 1) ^ 0x07 : result << 1;
    }
    return result;
}
}
std::string computerName() {
    char name[256]{};
#if defined(_WIN32)
    DWORD size = sizeof(name);
    if (!GetComputerNameA(name, &size)) return "PhoneCam PC";
#else
    if (gethostname(name, sizeof(name)-1) != 0) return "PhoneCam PC";
#endif
    std::string result(name);
    if (auto dot = result.find('.'); dot != std::string::npos) result.resize(dot);
    return result.empty() ? "PhoneCam PC" : result;
}
std::vector<std::string> localIPv4Addresses() {
    std::vector<std::string> addresses;
    auto add = [&](const sockaddr* address) {
        if (!address || address->sa_family != AF_INET) return;
        const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(address);
        const auto host = ntohl(ipv4->sin_addr.s_addr);
        if (host == 0 || (host >> 24) == 127 || (host >> 24) >= 224 || (host >> 16) == 0xa9fe) return;
        char ip[INET_ADDRSTRLEN]{};
        if (inet_ntop(AF_INET, &ipv4->sin_addr, ip, sizeof(ip))) addresses.emplace_back(ip);
    };
#if defined(_WIN32)
    ULONG size = 16 * 1024;
    std::vector<unsigned char> buffer(size);
    auto rc = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                  nullptr, reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
    if (rc == ERROR_BUFFER_OVERFLOW) {
        buffer.resize(size);
        rc = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                  nullptr, reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
    }
    if (rc == NO_ERROR) for (auto* adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); adapter; adapter = adapter->Next)
        if (adapter->OperStatus == IfOperStatusUp && adapter->IfType != IF_TYPE_SOFTWARE_LOOPBACK)
            for (auto* item = adapter->FirstUnicastAddress; item; item = item->Next) add(item->Address.lpSockaddr);
#else
    ifaddrs* entries = nullptr;
    if (getifaddrs(&entries) == 0) {
        for (auto* item = entries; item; item = item->ifa_next)
            if ((item->ifa_flags & IFF_UP) && !(item->ifa_flags & IFF_LOOPBACK)) add(item->ifa_addr);
        freeifaddrs(entries);
    }
#endif
    std::sort(addresses.begin(), addresses.end());
    addresses.erase(std::unique(addresses.begin(), addresses.end()), addresses.end());
    return addresses;
}
std::string makeConnectionCode(const std::string& ipv4) {
    in_addr address{};
    if (inet_pton(AF_INET, ipv4.c_str(), &address) != 1) return {};
    const auto ip = ntohl(address.s_addr);
    uint64_t value = (static_cast<uint64_t>(ip) << 8) | checksum(ip);
    std::string code(8, '0');
    for (int index = 7; index >= 0; --index) { code[index] = alphabet[value & 31]; value >>= 5; }
    return "PC-" + code.substr(0, 4) + "-" + code.substr(4);
}
std::string decodeConnectionCode(const std::string& input) {
    std::string code;
    for (unsigned char c : input) if (c != '-' && !std::isspace(c)) code += static_cast<char>(std::toupper(c));
    if (code.rfind("PC", 0) != 0 || code.size() != 10) return {};
    uint64_t value = 0;
    for (size_t i = 2; i < code.size(); ++i) {
        const auto* digit = std::strchr(alphabet, code[i]);
        if (!digit) return {};
        value = (value << 5) | (digit - alphabet);
    }
    const auto ip = static_cast<uint32_t>(value >> 8);
    if (checksum(ip) != static_cast<uint8_t>(value)) return {};
    in_addr address{}; address.s_addr = htonl(ip);
    char text[INET_ADDRSTRLEN]{};
    return inet_ntop(AF_INET, &address, text, sizeof(text)) ? text : "";
}
ReceiverListener::ReceiverListener(int port) {
#if defined(_WIN32)
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) throw std::runtime_error("Network initialization failed");
    runtime_ = true;
#endif
    socket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sockaddr_in address{}; address.sin_family = AF_INET; address.sin_port = htons(port);
#if defined(_WIN32)
    int exclusive = 1;
    setsockopt(socket_, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<char*>(&exclusive), sizeof(exclusive));
#else
    int reuse = 1; setsockopt(socket_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
#endif
    if (socket_ == INVALID_SOCKET_VAL || bind(socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || listen(socket_, 4) != 0) {
        if (socket_ != INVALID_SOCKET_VAL) closeConnectionSocket(socket_);
#if defined(_WIN32)
        if (runtime_) WSACleanup();
#endif
        throw std::runtime_error("Cannot open PhoneCam receiver port. Close another running receiver and retry.");
    }
#if defined(_WIN32)
    int length = sizeof(address);
#else
    socklen_t length = sizeof(address);
#endif
    getsockname(socket_, reinterpret_cast<sockaddr*>(&address), &length);
    port_ = ntohs(address.sin_port);
}
ReceiverListener::~ReceiverListener() {
    if (socket_ != INVALID_SOCKET_VAL) closeConnectionSocket(socket_);
#if defined(_WIN32)
    if (runtime_) WSACleanup();
#endif
}
socket_t ReceiverListener::acceptPhone(std::string& peer, std::chrono::milliseconds timeout) {
    if (!canRead(socket_, timeout)) return INVALID_SOCKET_VAL;
    sockaddr_in address{};
#if defined(_WIN32)
    int length = sizeof(address);
#else
    socklen_t length = sizeof(address);
#endif
    auto client = accept(socket_, reinterpret_cast<sockaddr*>(&address), &length);
    if (client == INVALID_SOCKET_VAL) return client;
    // The phone identifies this protocol before we send camera commands.
    std::array<char, sizeof("PHONECAM/2\n") - 1> hello{};
    size_t offset = 0;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
    while (offset < hello.size() && std::chrono::steady_clock::now() < deadline) {
        if (!canRead(client, std::chrono::milliseconds(50))) continue;
        const int count = recv(client, hello.data() + offset, static_cast<int>(hello.size() - offset), 0);
        if (count <= 0) break;
        offset += count;
    }
    if (offset != hello.size() || std::memcmp(hello.data(), kReverseHello, hello.size()) != 0) {
        closeConnectionSocket(client); return INVALID_SOCKET_VAL;
    }
    char text[INET_ADDRSTRLEN]{};
    inet_ntop(AF_INET, &address.sin_addr, text, sizeof(text));
    peer = text;
    return client;
}

#if defined(_WIN32)
// Each pending native callback owns a reference, including teardown during registration.
struct ReceiverAdvertisement::State {
    std::atomic<int> refs{1};
    std::mutex mutex;
    DNS_SERVICE_REGISTER_REQUEST request{};
    bool pending = true, registered = false, stopping = false;
    void retain() { ++refs; }
    void release() { if (--refs == 0) delete this; }
    ~State() { if (request.pServiceInstance) DnsServiceFreeInstance(request.pServiceInstance); }
    static void WINAPI removed(DWORD, void* context, PDNS_SERVICE_INSTANCE result) {
        auto* self = static_cast<State*>(context);
        if (result && result != self->request.pServiceInstance) DnsServiceFreeInstance(result);
        self->release();
    }
    void removeLocked() {
        registered = false;
        request.pRegisterCompletionCallback = removed;
        retain();
        if (DnsServiceDeRegister(&request, nullptr) != DNS_REQUEST_PENDING) release();
    }
    static void WINAPI completed(DWORD status, void* context, PDNS_SERVICE_INSTANCE result) {
        auto* self = static_cast<State*>(context);
        {
            std::lock_guard<std::mutex> lock(self->mutex);
            self->pending = false;
            self->registered = status == ERROR_SUCCESS;
            if (result && result != self->request.pServiceInstance) {
                DnsServiceFreeInstance(self->request.pServiceInstance);
                self->request.pServiceInstance = result;
            }
            if (status != ERROR_SUCCESS) std::cerr << "Network discovery unavailable (" << status << "). Use the PC code.\n";
            if (self->stopping && self->registered) self->removeLocked();
        }
        self->release();
    }
};
ReceiverAdvertisement::ReceiverAdvertisement(const std::string& name, int port) {
    auto self = std::make_unique<State>();
    std::wstring wideName(name.begin(), name.end());
    auto host = wideName + L".local";
    auto service = wideName + L"._phonecam._tcp.local";
    self->request.Version = DNS_QUERY_REQUEST_VERSION1;
    self->request.pServiceInstance = DnsServiceConstructInstance(service.c_str(), host.c_str(), nullptr, nullptr,
                                                                static_cast<WORD>(port), 0, 0, 0, nullptr, nullptr);
    if (!self->request.pServiceInstance) return;
    self->request.pRegisterCompletionCallback = State::completed;
    self->request.pQueryContext = self.get();
    self->retain();
    auto rc = DnsServiceRegister(&self->request, nullptr);
    if (rc != DNS_REQUEST_PENDING) { self->pending = false; self->release(); }
    state_ = self.release();
}
ReceiverAdvertisement::~ReceiverAdvertisement() {
    if (!state_) return;
    {
        std::lock_guard<std::mutex> lock(state_->mutex);
        state_->stopping = true;
        if (!state_->pending && state_->registered) state_->removeLocked();
    }
    state_->release();
}
#elif defined(__APPLE__)
struct ReceiverAdvertisement::State { DNSServiceRef reference = nullptr; };
ReceiverAdvertisement::ReceiverAdvertisement(const std::string& name, int port) : state_(new State) {
    auto rc = DNSServiceRegister(&state_->reference, 0, 0, name.c_str(), kReceiverServiceType, nullptr, nullptr,
                                htons(static_cast<uint16_t>(port)), 0, nullptr, nullptr, nullptr);
    if (rc != kDNSServiceErr_NoError) std::cerr << "Network discovery unavailable. Use the PC code.\n";
}
ReceiverAdvertisement::~ReceiverAdvertisement() {
    if (state_->reference) DNSServiceRefDeallocate(state_->reference);
    delete state_;
}
#else
struct ReceiverAdvertisement::State {};
ReceiverAdvertisement::ReceiverAdvertisement(const std::string&, int) {}
ReceiverAdvertisement::~ReceiverAdvertisement() = default;
#endif
}
