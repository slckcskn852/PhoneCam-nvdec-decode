// Windows-only sender-side lifetime/handle regression; no COM registration needed.
#include <windows.h>
#include <psapi.h>
#include <softcam/softcam.h>
#include <atomic>
#include <thread>
#include <vector>
#include <iostream>
#include <stdexcept>

static void require(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
int main() {
  try {
    std::vector<unsigned char> frame(64 * 64 * 3, 128);
    // Warm runtime/TLS timer initialization before sampling.
    auto warm = scCreateCamera(64, 64, 240); require(warm != nullptr, "warmup create failed");
    scSendFrame(warm, frame.data()); scDeleteCamera(warm);
    DWORD initialHandles = 0; GetProcessHandleCount(GetCurrentProcess(), &initialHandles);
    PROCESS_MEMORY_COUNTERS_EX initial{}; initial.cb = sizeof(initial);
    GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&initial), sizeof(initial));
    for (int cycle = 0; cycle < 100; ++cycle) {
      auto camera = scCreateCamera(64, 64, 240); require(camera != nullptr, "create failed");
      std::atomic<bool> began{false};
      std::thread writer([&] {
        began = true;
        for (int i = 0; i < 4; ++i) scSendFrame(camera, frame.data());
      });
      while (!began) std::this_thread::yield();
      scDeleteCamera(camera);
      writer.join();
    }
    DWORD handles = 0; GetProcessHandleCount(GetCurrentProcess(), &handles);
    PROCESS_MEMORY_COUNTERS_EX memory{}; memory.cb = sizeof(memory);
    GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory));
    std::cout << "100 create/send/delete cycles: handles " << initialHandles << " -> " << handles
              << ", private bytes " << initial.PrivateUsage << " -> " << memory.PrivateUsage << '\n';
    require(handles <= initialHandles + 4, "handle count grew across camera lifetimes");
    require(memory.PrivateUsage <= initial.PrivateUsage + 16 * 1024 * 1024, "unbounded private memory growth");
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
