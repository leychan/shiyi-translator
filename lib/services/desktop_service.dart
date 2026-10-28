import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_controller.dart';
import '../app_identity.dart';
import 'autostart_service.dart';
import 'instance_service.dart';
import 'selection_service.dart';
import 'shortcut_service.dart';
import 'popup_service.dart';

class DesktopService extends ChangeNotifier with WindowListener, TrayListener {
  DesktopService(
    this.controller,
    this.instance, {
    PopupService? popup,
    SelectionService? selection,
    AutostartService? autostart,
  }) : selection = selection ?? SelectionService(),
       autostart = autostart ?? AutostartService() {
    this.popup = popup ?? PopupService(controller);
    instance.onRpc = this.popup.handle;
    this.popup.openSettings = () async {
      controller.goTo(1);
      await show();
    };
  }
  final AppController controller;
  final InstanceService instance;
  late final PopupService popup;
  final shortcuts = ShortcutService();
  final SelectionService selection;
  final AutostartService autostart;
  bool autostartEnabled = false;
  bool autostartBusy = false;
  String? autostartError;
  bool trayReady = false;
  bool registering = false;
  bool pinned = false;
  bool _capturing = false;
  bool _quitting = false;
  bool _disposed = false;
  String shortcutStatus = '正在连接桌面快捷键…';

  Future<void> initialize({
    bool bindShortcut = true,
    bool showMain = true,
  }) async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1180, 780),
        minimumSize: Size(600, 540),
        center: true,
        title: appTitle,
      ),
      () async {
        if (showMain) {
          await windowManager.show();
          await windowManager.focus();
        } else {
          await windowManager.hide();
        }
      },
    );
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
      );
      // Linux AppIndicator exposes its menu without the tooltip method.
      if (!Platform.isLinux) {
        await trayManager.setToolTip(appTitle);
      }
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '打开$appName'),
            MenuItem(key: 'selection', label: '翻译选中文字'),
            MenuItem(key: 'clipboard', label: '翻译剪贴板'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: '退出$appName'),
          ],
        ),
      );
      trayReady = true;
      await windowManager.setPreventClose(true);
    } catch (_) {
      controller.message('托盘暂不可用，关闭窗口将退出应用。');
    }
    await refreshAutostart();
    instance.onAction = handleAction;
    await instance.drainPending();
    notifyListeners();
    if (bindShortcut) {
      unawaited(registerShortcut());
    }
  }

  Future<void> refreshAutostart() async {
    if (autostartBusy || _disposed || _quitting) return;
    autostartBusy = true;
    _autostartChanged();
    try {
      autostartEnabled = await autostart.isEnabled();
      autostartError = null;
    } catch (_) {
      autostartError = '无法读取系统启动设置，可尝试重新切换开关';
    } finally {
      autostartBusy = false;
      _autostartChanged();
    }
  }

  Future<void> setAutostartEnabled(bool enabled) async {
    if (autostartBusy || _disposed || _quitting) return;
    autostartBusy = true;
    autostartError = null;
    _autostartChanged();
    try {
      await autostart.setEnabled(enabled);
      final registered = await autostart.isEnabled();
      if (registered != enabled) {
        throw StateError('Autostart registration did not match');
      }
      autostartEnabled = registered;
    } catch (_) {
      autostartError = '设置失败，请检查系统权限后重试';
      if (!_disposed && !_quitting) {
        controller.message('无法修改开机自启动设置，请检查系统权限后重试。');
      }
    } finally {
      autostartBusy = false;
      _autostartChanged();
    }
  }

  void _autostartChanged() {
    if (!_disposed && !_quitting) notifyListeners();
  }

  Future<void> registerShortcut() async {
    if (registering) return;
    registering = true;
    shortcutStatus = '等待系统绑定快捷键…';
    notifyListeners();
    try {
      await shortcuts.register(() => capture());
      shortcutStatus = shortcuts.label;
    } catch (error) {
      await shortcuts.dispose();
      debugPrint('Global shortcut registration failed: $error');
      shortcutStatus = '未绑定 · 可在设置中重试';
    } finally {
      registering = false;
      notifyListeners();
    }
  }

  Future<void> handleAction(String action) async {
    if (action == 'autostart') {
      return;
    } else if (action == 'selection') {
      await capture();
    } else if (action == 'clipboard') {
      await capture(clipboard: true);
    } else {
      await show();
    }
  }

  Future<void> capture({bool clipboard = false}) async {
    if (_capturing) return;
    _capturing = true;
    final anchor = await popup.placement.capture();
    try {
      // Read before activating our window, preserving the source application's selection.
      final captured = clipboard
          ? await selection.readClipboard()
          : await selection.readSelection();
      await popup.present(
        text: captured.text,
        label: captured.label,
        anchor: anchor,
      );
    } on SelectionException catch (error) {
      await popup.present(text: '', translate: false, anchor: anchor);
      popup.controller.message(error.message);
    } catch (_) {
      controller.message('取词失败，请尝试复制文字后使用剪贴板翻译。');
    } finally {
      _capturing = false;
    }
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> openPopup() async {
    final anchor = await popup.placement.capture();
    await popup.present(
      text: controller.input,
      label: controller.captureLabel,
      anchor: anchor,
    );
  }

  Future<void> togglePinned() async {
    pinned = !pinned;
    await windowManager.setAlwaysOnTop(pinned);
    notifyListeners();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    controller.cancel();
    await popup.dispose();
    await controller.persist();
    await shortcuts.dispose();
    if (trayReady) await trayManager.destroy();
    await instance.close();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowFocus() {
    unawaited(refreshAutostart());
  }

  @override
  void onWindowClose() async {
    if (trayReady && controller.settings.closeToTray) {
      await windowManager.hide();
    } else {
      await quit();
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'exit') {
      unawaited(quit());
    } else {
      unawaited(handleAction(menuItem.key ?? 'show'));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    unawaited(shortcuts.dispose());
    unawaited(popup.dispose());
    super.dispose();
  }
}
