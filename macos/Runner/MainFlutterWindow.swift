import Cocoa
import FlutterMacOS
import ApplicationServices
import Carbon

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private let autostartLabel = "dev.justtranslator.justTranslator.autostart"

  private var autostartURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents")
      .appendingPathComponent("\(autostartLabel).plist")
  }

  private func autostartEnabled() throws -> Bool {
    let url = autostartURL
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    let data = try Data(contentsOf: url)
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let executable = Bundle.main.executableURL?.path else { return false }
    return plist["Label"] as? String == autostartLabel &&
      plist["ProgramArguments"] as? [String] == [executable, "--autostart"] &&
      plist["Disabled"] as? Bool != true
  }

  private func setAutostart(_ enabled: Bool) throws {
    let url = autostartURL
    if !enabled {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      return
    }
    guard let executable = Bundle.main.executableURL?.path else {
      throw NSError(domain: "ShiyiAutostart", code: 1)
    }
    let plist: [String: Any] = [
      "Label": autostartLabel,
      "ProgramArguments": [executable, "--autostart"],
      "RunAtLoad": true,
      "KeepAlive": false,
      "ProcessType": "Interactive",
      "LimitLoadToSessionType": "Aqua",
    ]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url, options: .atomic)
  }

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
      } else if call.method == "isAutostartEnabled" {
        do { result(try self.autostartEnabled()) }
        catch { result(FlutterError(code: "autostart", message: "Unable to read startup registration", details: nil)) }
      } else if call.method == "setAutostartEnabled" {
        guard let arguments = call.arguments as? [String: Any], let enabled = arguments["enabled"] as? Bool else {
          result(FlutterError(code: "arguments", message: "Expected enabled boolean", details: nil)); return
        }
        do { try self.setAutostart(enabled); result(nil) }
        catch { result(FlutterError(code: "autostart", message: "Unable to update startup registration", details: nil)) }
      } else { result(FlutterMethodNotImplemented) }
    }

    super.awakeFromNib()
    if CommandLine.arguments.contains(where: { ["--selection", "--clipboard", "--popup", "--autostart"].contains($0) }) {
      self.orderOut(nil)
    }
  }

  deinit {
    if let key = hotKey { UnregisterEventHotKey(key) }
    if let handler = eventHandler { RemoveEventHandler(handler) }
  }
}
