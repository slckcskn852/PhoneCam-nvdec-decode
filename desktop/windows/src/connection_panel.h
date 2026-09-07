#pragma once
#include "receiver_connection.h"
#if defined(_WIN32)
#include <windows.h>
#include <shellapi.h>
#endif

class ConnectionPanel {
public:
  ConnectionPanel(const std::string& name, const std::vector<std::string>& addresses, int port) {
    std::string instructions = "Open PhoneCam on your phone, tap Find computer, then choose " + name + ".\n\n";
    instructions += "Computer not listed? Enter one of these PC codes on your phone:\n";
    for (const auto& ip : addresses) {
      const auto code = phonecam::makeConnectionCode(ip);
      if (copyText_.empty()) copyText_ = port == phonecam::kReceiverPort ? code : ip + ":" + std::to_string(port);
      instructions += "  " + (port == phonecam::kReceiverPort ? code : ip + ":" + std::to_string(port)) + "    (" + ip + ")\n";
    }
    instructions += "\nKeep PhoneCam open on both devices. No USB cable or account is needed.";
    std::cout << "\nPhoneCam Receiver — " << name << "\n" << instructions << "\n" << std::flush;
#if defined(_WIN32)
    WNDCLASSW klass{}; klass.lpfnWndProc = procedure; klass.hInstance = GetModuleHandleW(nullptr);
    klass.lpszClassName = L"PhoneCamConnection"; klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    klass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    RegisterClassW(&klass);
    window_ = CreateWindowExW(0, klass.lpszClassName, L"PhoneCam — Connect your phone", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                             CW_USEDEFAULT, CW_USEDEFAULT, 660, 480, nullptr, nullptr, klass.hInstance, this);
    if (!window_) throw std::runtime_error("Cannot create connection window");
    auto text = wide(instructions);
    label_ = CreateWindowW(L"STATIC", text.c_str(), WS_CHILD | WS_VISIBLE | SS_LEFT, 24, 24, 600, 265, window_, nullptr, klass.hInstance, nullptr);
    status_ = CreateWindowW(L"STATIC", L"Waiting for your phone…", WS_CHILD | WS_VISIBLE, 24, 300, 600, 34, window_, nullptr, klass.hInstance, nullptr);
    CreateWindowW(L"BUTTON", L"Copy PC code", WS_CHILD | WS_VISIBLE | WS_TABSTOP, 24, 360, 160, 38, window_, reinterpret_cast<HMENU>(1), klass.hInstance, nullptr);
    CreateWindowW(L"BUTTON", L"Allow home network", WS_CHILD | WS_VISIBLE | WS_TABSTOP, 196, 360, 200, 38, window_, reinterpret_cast<HMENU>(2), klass.hInstance, nullptr);
    CreateWindowW(L"BUTTON", L"Connection help", WS_CHILD | WS_VISIBLE | WS_TABSTOP, 408, 360, 190, 38, window_, reinterpret_cast<HMENU>(3), klass.hInstance, nullptr);
    EnumChildWindows(window_, [](HWND child, LPARAM) -> BOOL {
      SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE); return TRUE;
    }, 0);
    ShowWindow(window_, SW_SHOW); UpdateWindow(window_);
#endif
  }
  ~ConnectionPanel() {
#if defined(_WIN32)
    if (window_) DestroyWindow(window_);
#endif
  }
  bool pump() {
#if defined(_WIN32)
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) closed_ = true;
      TranslateMessage(&message); DispatchMessageW(&message);
    }
#endif
    return !closed_;
  }
  void show(bool value) {
#if defined(_WIN32)
    ShowWindow(window_, value ? SW_SHOW : SW_HIDE);
#else
    (void)value;
#endif
  }
  void status(const std::string& message) {
    std::cout << message << '\n' << std::flush;
#if defined(_WIN32)
    SetWindowTextW(status_, wide(message).c_str());
#endif
  }
private:
  bool closed_ = false;
  std::string copyText_;
#if defined(_WIN32)
  HWND window_ = nullptr, label_ = nullptr, status_ = nullptr;
  static std::wstring wide(const std::string& input) {
    int count = MultiByteToWideChar(CP_UTF8, 0, input.data(), static_cast<int>(input.size()), nullptr, 0);
    std::wstring result(count, L' ');
    MultiByteToWideChar(CP_UTF8, 0, input.data(), static_cast<int>(input.size()), result.data(), count);
    return result;
  }
  void copy() {
    const auto value = wide(copyText_);
    if (!OpenClipboard(window_)) return;
    auto memory = GlobalAlloc(GMEM_MOVEABLE, (value.size()+1) * sizeof(wchar_t));
    if (memory) {
      auto* target = GlobalLock(memory);
      if (target) {
        std::memcpy(target, value.c_str(), (value.size()+1)*sizeof(wchar_t)); GlobalUnlock(memory);
        EmptyClipboard(); if (!SetClipboardData(CF_UNICODETEXT, memory)) GlobalFree(memory);
      } else GlobalFree(memory);
    }
    CloseClipboard();
  }
  void allowNetwork() {
    wchar_t executable[MAX_PATH]{};
    GetModuleFileNameW(nullptr, executable, MAX_PATH);
    std::wstring path(executable);
    const auto directory = path.substr(0, path.find_last_of(L"\\/"));
    const auto script = directory + L"\\Install-PhoneCamFirewallRules.ps1";
    if (GetFileAttributesW(script.c_str()) == INVALID_FILE_ATTRIBUTES) {
      MessageBoxW(window_, L"Allow PhoneCam on Private networks in the Windows Firewall prompt.\n\nFor a developer build, run desktop/windows/scripts/Install-PhoneCamFirewallRules.ps1 with the receiver path from an elevated PowerShell.\n\nThe packaged app includes this helper beside the executable.", L"Allow PhoneCam", MB_OK | MB_ICONINFORMATION);
      return;
    }
    const auto args = L"-NoProfile -ExecutionPolicy Bypass -File \"" + script + L"\" -Receiver \"" + path + L"\"";
    if (reinterpret_cast<INT_PTR>(ShellExecuteW(window_, L"runas", L"powershell.exe", args.c_str(), directory.c_str(), SW_SHOWNORMAL)) <= 32)
      status("Network setup was cancelled or could not start. You can retry.");
  }
  static LRESULT CALLBACK procedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<ConnectionPanel*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<ConnectionPanel*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self && message == WM_CLOSE) { self->closed_ = true; ShowWindow(window, SW_HIDE); return 0; }
    if (self && message == WM_COMMAND) {
      if (LOWORD(wparam) == 1) self->copy();
      if (LOWORD(wparam) == 2) self->allowNetwork();
      if (LOWORD(wparam) == 3) MessageBoxW(window,
        L"1. Open PhoneCam on both devices and tap Find computer on your phone.\n2. Allow camera/local-network access and Windows Private-network access.\n3. If the computer is missing, enter its PC code or IP address.\n\nDifferent Wi-Fi names, mesh nodes and access points work when devices share a LAN. For a second router, connect from its downstream side toward the upstream computer. Guest/client isolation or two isolated networks require a route or the same non-guest network.\n\nPC codes contain an address and typo check; they are not passwords. Use a trusted home network.",
        L"Connection help", MB_OK | MB_ICONINFORMATION);
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
#endif
};
