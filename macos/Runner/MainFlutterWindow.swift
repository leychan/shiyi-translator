import Cocoa
import FlutterMacOS
import ApplicationServices
import Carbon

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    desktopChannel = FlutterMethodChannel(name: "dev.justtranslator/desktop",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    desktopChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "readSelection" {
        guard AXIsProcessTrusted() else {
          let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
          _ = AXIsProcessTrustedWithOptions(options)
          result(FlutterError(code: "accessibility", message: "Accessibility permission required", details: nil))
          return
        }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused = focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
          result(""); return
        }
        let element = focused as! AXUIElement
        var text: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &text)
        result(text as? String ?? "")
      } else if call.method == "registerShortcut" {
        if let key = self.hotKey { UnregisterEventHotKey(key) }
        if self.eventHandler == nil {
          var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
          InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data = data else { return OSStatus(eventNotHandledErr) }
            let window = Unmanaged<MainFlutterWindow>.fromOpaque(data).takeUnretainedValue()
            window.desktopChannel?.invokeMethod("translateSelection", arguments: nil)
            return noErr
          }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &self.eventHandler)
        }
        let identifier = EventHotKeyID(signature: 0x4A54524E, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier,
          GetApplicationEventTarget(), 0, &self.hotKey)
        result(status == noErr)
      } else { result(FlutterMethodNotImplemented) }
    }

    super.awakeFromNib()
    if CommandLine.arguments.contains(where: { ["--selection", "--clipboard", "--popup"].contains($0) }) {
      self.orderOut(nil)
    }
  }

  deinit {
    if let key = hotKey { UnregisterEventHotKey(key) }
    if let handler = eventHandler { RemoveEventHandler(handler) }
  }
}
