#include "flutter_window.h"

#include <optional>
#include <UIAutomation.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>

namespace {
constexpr int kTranslateHotKey = 0x4A54;

std::string ReadSelectedText() {
  using Microsoft::WRL::ComPtr;
  ComPtr<IUIAutomation> automation;
  if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(automation.GetAddressOf())))) return "";
  ComPtr<IUIAutomationElement> element;
  if (FAILED(automation->GetFocusedElement(element.GetAddressOf()))) return "";
  ComPtr<IUnknown> unknown;
  if (FAILED(element->GetCurrentPattern(UIA_TextPatternId, unknown.GetAddressOf()))) return "";
  ComPtr<IUIAutomationTextPattern> pattern;
  if (FAILED(unknown.As(&pattern))) return "";
  ComPtr<IUIAutomationTextRangeArray> ranges;
  if (FAILED(pattern->GetSelection(ranges.GetAddressOf()))) return "";
  int count = 0;
  ranges->get_Length(&count);
  std::string selected;
  for (int i = 0; i < count; ++i) {
    ComPtr<IUIAutomationTextRange> range;
    if (FAILED(ranges->GetElement(i, range.GetAddressOf()))) continue;
    BSTR text = nullptr;
    if (SUCCEEDED(range->GetText(15000, &text)) && text) {
      const int length = static_cast<int>(SysStringLen(text));
      const int bytes = WideCharToMultiByte(CP_UTF8, 0, text, length, nullptr, 0, nullptr, nullptr);
      std::string utf8(bytes, '\0');
      WideCharToMultiByte(CP_UTF8, 0, text, length, utf8.data(), bytes, nullptr, nullptr);
      if (!selected.empty()) selected += "\n";
      selected += utf8;
      SysFreeString(text);
    }
  }
  return selected;
}
}  // namespace

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  desktop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "dev.justtranslator/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "readSelection") {
      result->Success(flutter::EncodableValue(ReadSelectedText()));
    } else if (call.method_name() == "registerShortcut") {
      UnregisterHotKey(GetHandle(), kTranslateHotKey);
      result->Success(flutter::EncodableValue(RegisterHotKey(GetHandle(), kTranslateHotKey,
          MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_SPACE) != 0));
    } else { result->NotImplemented(); }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Presentation is controlled by window_manager after Dart chooses the
  // management window or the frameless translation popup.

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  UnregisterHotKey(GetHandle(), kTranslateHotKey);
  desktop_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_HOTKEY:
      if (wparam == kTranslateHotKey && desktop_channel_) {
        desktop_channel_->InvokeMethod("translateSelection", nullptr);
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
