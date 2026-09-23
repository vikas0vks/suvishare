#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <winhttp.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Named mutex shared with the Inno Setup installer (AppMutex), so the
// installer can detect a running copy, and used here to enforce a single
// instance: launching the app again focuses the existing window instead of
// opening a second one.
constexpr const wchar_t kInstanceMutexName[] = L"SuviShareSingleInstance";
constexpr const wchar_t kWindowTitle[] = L"Suvi Share";

// The running instance listens on this loopback port (lib/platform/
// single_instance.dart) and shows its own window on GET /focus.
constexpr INTERNET_PORT kInstanceLockPort = 53339;

// Asks the running instance to bring its window to the front.
//
// Deliberately done over loopback HTTP instead of ShowWindow /
// SetForegroundWindow from this process: poking a Flutter window from a
// foreign process has crashed the engine in the running instance
// (access violation in flutter_windows.dll), while showing the window from
// inside the app (windowManager.show(), same path the tray uses) is safe.
void FocusExistingInstance() {
  HINTERNET session = ::WinHttpOpen(L"SuviShare/2",
                                    WINHTTP_ACCESS_TYPE_NO_PROXY,
                                    WINHTTP_NO_PROXY_NAME,
                                    WINHTTP_NO_PROXY_BYPASS, 0);
  if (session == nullptr) {
    return;
  }
  ::WinHttpSetTimeouts(session, 1000, 1000, 1000, 2000);
  HINTERNET connect =
      ::WinHttpConnect(session, L"127.0.0.1", kInstanceLockPort, 0);
  if (connect != nullptr) {
    HINTERNET request = ::WinHttpOpenRequest(
        connect, L"GET", L"/focus", nullptr, WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if (request != nullptr) {
      if (::WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                               WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
        ::WinHttpReceiveResponse(request, nullptr);
      }
      ::WinHttpCloseHandle(request);
    }
    ::WinHttpCloseHandle(connect);
  }
  ::WinHttpCloseHandle(session);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance: if the mutex already exists another copy is running —
  // ask it to show itself and exit before Flutter even starts.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kInstanceMutexName);
  if (instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    FocusExistingInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // The title must stay in sync with kWindowTitle and with the Dart side
  // (window_manager).
  if (!window.Create(kWindowTitle, origin, size)) {
    // A silent exit here looks like "the app hung / never opened". Say what
    // actually happened: engine startup failed, almost always because the
    // data/ folder next to the executable is missing or damaged.
    ::MessageBoxW(
        nullptr,
        L"Suvi Share could not start because its application data is missing "
        L"or damaged (the 'data' folder next to suvi_share.exe).\n\n"
        L"Please reinstall Suvi Share.",
        kWindowTitle, MB_ICONERROR | MB_OK);
    if (instance_mutex != nullptr) {
      ::CloseHandle(instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (instance_mutex != nullptr) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
