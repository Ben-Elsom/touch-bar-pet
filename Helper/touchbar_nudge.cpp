// touchbar_nudge: keeps the Touch Bar showing while Amphetamine or Touch Bar Pet holds the display.
//
// The Touch Bar goes blank about 75 seconds after real input, and only a real input
// device wakes it. So while Amphetamine (or Touch Bar Pet, while Claude is open) is holding the display awake and nothing has
// happened for 30 seconds, this moves the pointer one pixel and back through
// Karabiner's virtual mouse.
//
// The switch in the Touch Bar Pet window turns this off by creating a marker file in
// the signed-in user's Application Support folder. This only checks that the file
// exists and never opens it.
//
// It runs as root because Karabiner's virtual devices only accept root clients. It
// takes no input from anywhere and can do nothing except this one nudge.
//
//   touchbar_nudge          run (launchd keeps it going)
//   touchbar_nudge --check  print what it would do, without nudging

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <atomic>
#include <chrono>
#include <csignal>
#include <cstring>
#include <iostream>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <pwd.h>
#include <sys/stat.h>
#include <thread>

namespace {
namespace hid_report = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report;

constexpr double kNudgeAfterIdleSeconds = 30;
std::atomic<bool> should_exit(false);

std::string to_string(CFStringRef s) {
  if (!s) return "";
  char buffer[256] = {};
  return CFStringGetCString(s, buffer, sizeof(buffer), kCFStringEncodingUTF8) ? buffer : "";
}

/// True while Amphetamine or Touch Bar Pet is stopping the display from sleeping.
bool amphetamine_holds_display() {
  CFDictionaryRef by_process = nullptr;
  if (IOPMCopyAssertionsByProcess(&by_process) != kIOReturnSuccess || !by_process) return false;

  bool found = false;
  CFIndex count = CFDictionaryGetCount(by_process);
  std::vector<const void*> values(count);
  CFDictionaryGetKeysAndValues(by_process, nullptr, values.data());
  for (CFIndex p = 0; p < count && !found; ++p) {
    auto assertions = static_cast<CFArrayRef>(values[p]);
    for (CFIndex a = 0; a < CFArrayGetCount(assertions) && !found; ++a) {
      auto assertion = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(assertions, a));
      auto type = to_string(static_cast<CFStringRef>(CFDictionaryGetValue(assertion, kIOPMAssertionTypeKey)));
      auto name = to_string(static_cast<CFStringRef>(CFDictionaryGetValue(assertion, kIOPMAssertionNameKey)));
      // Amphetamine, or Touch Bar Pet itself while Claude is open.
      found = type == "PreventUserIdleDisplaySleep" &&
              (name.rfind("Amphetamine", 0) == 0 || name.rfind("Touch Bar Pet", 0) == 0);
    }
  }
  CFRelease(by_process);
  return found;
}

/// False once the signed-in user has switched this off in the Touch Bar Pet window.
bool switched_on() {
  uid_t uid = 0;
  CFStringRef user = SCDynamicStoreCopyConsoleUser(nullptr, &uid, nullptr);
  if (!user) return true;
  CFRelease(user);
  const passwd* account = getpwuid(uid);
  if (!account || !account->pw_dir) return true;
  std::string marker = std::string(account->pw_dir) + "/Library/Application Support/Touch_Bar_Pet/always_on_off";
  struct stat info;
  return lstat(marker.c_str(), &info) != 0;
}

/// Seconds since the last input from any device, or -1 if macOS won't say.
double seconds_idle() {
  io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
  if (!service) return -1;
  double seconds = -1;
  auto property = static_cast<CFNumberRef>(
      IORegistryEntryCreateCFProperty(service, CFSTR("HIDIdleTime"), kCFAllocatorDefault, 0));
  if (property) {
    int64_t nanoseconds = 0;
    if (CFNumberGetValue(property, kCFNumberSInt64Type, &nanoseconds)) seconds = nanoseconds / 1e9;
    CFRelease(property);
  }
  IOObjectRelease(service);
  return seconds;
}
} // namespace

int main(int argc, char** argv) {
  if (argc > 1 && std::strcmp(argv[1], "--check") == 0) {
    double idle = seconds_idle();
    bool held = amphetamine_holds_display();
    bool on = switched_on();
    std::cout << "Switched on in the window: " << (on ? "yes" : "no")
              << "\nAmphetamine or the pet holding display: " << (held ? "yes" : "no") << "\nidle seconds: " << idle
              << "\nwould nudge: " << (on && held && idle >= kNudgeAfterIdleSeconds ? "yes" : "no") << std::endl;
    return 0;
  }

  std::signal(SIGTERM, [](int) { should_exit = true; });
  std::signal(SIGINT, [](int) { should_exit = true; });

  pqrs::dispatcher::extra::initialize_shared_dispatcher();
  auto client = std::make_unique<pqrs::karabiner::driverkit::virtual_hid_device_service::client>();
  std::atomic<bool> ready(false);

  // The client reconnects by itself if Karabiner's service restarts.
  client->connected.connect([&client] { client->async_virtual_hid_pointing_initialize(); });
  client->closed.connect([&ready] { ready = false; });
  client->virtual_hid_pointing_ready.connect([&ready](auto&& r) { ready = r; });
  client->async_start();

  while (!should_exit) {
    if (ready && switched_on() && amphetamine_holds_display() && seconds_idle() >= kNudgeAfterIdleSeconds) {
      hid_report::pointing_input right;
      right.x = 1;
      client->async_post_report(right);
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      hid_report::pointing_input left;
      left.x = static_cast<uint8_t>(-1);
      client->async_post_report(left);
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      client->async_post_report(hid_report::pointing_input{});
    }
    std::this_thread::sleep_for(std::chrono::seconds(5));
  }

  client = nullptr;
  pqrs::dispatcher::extra::terminate_shared_dispatcher();
  return 0;
}
