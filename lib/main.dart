import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_controller.dart';
import 'popup.dart';
import 'services/desktop_service.dart';
import 'services/instance_service.dart';
import 'services/selection_service.dart';
import 'services/storage_service.dart';
import 'services/pointer_placement_service.dart';
import 'services/popup_service.dart';
import 'popup_placement.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--popup')) {
    try {
      await runPopup();
    } catch (_) {
      stderr.writeln('Unable to open translation popup.');
      exit(1);
    }
    return;
  }
  final action = arguments.contains('--selection')
      ? 'selection'
      : arguments.contains('--clipboard')
      ? 'clipboard'
      : 'show';
  final instance = InstanceService();
  try {
    if (!await instance.startOrForward(action)) exit(0);
    final store = StorageService();
    final settings = await store.load();
    final controller = AppController(settings: settings, store: store);
    if (store.loadWarning != null) controller.message(store.loadWarning!);
    SelectionCapture? captured;
    final placement = PointerPlacementService();
    PopupAnchor? anchor;
    String? captureError;
    if (action != 'show') {
      anchor = await placement.capture();
      try {
        captured = action == 'selection'
            ? await SelectionService().readSelection()
            : await SelectionService().readClipboard();
      } on SelectionException catch (error) {
        captureError = error.message;
      }
    }
    await windowManager.ensureInitialized();
    final desktop = DesktopService(
      controller,
      instance,
      popup: PopupService(controller, placement: placement),
    );
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => unawaited(desktop.quit()));
    }
    runApp(TranslatorApp(controller: controller, desktop: desktop));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        desktop
            .initialize(showMain: action == 'show')
            .then((_) async {
              if (action != 'show') {
                await desktop.popup.present(
                  text: captured?.text ?? '',
                  label: captured?.label,
                  translate: captured != null,
                  anchor: anchor,
                );
                if (captureError != null) {
                  desktop.popup.controller.message(captureError);
                }
              }
            })
            .catchError((Object _) {
              controller.message('部分桌面功能初始化失败，仍可使用输入翻译。');
            }),
      );
    });
  } catch (error) {
    stderr.writeln('Just Translator startup failed: ${error.runtimeType}');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              '无法启动 Just Translator。\n请检查应用数据目录权限，或稍后重试。\n错误类型：${error.runtimeType}',
            ),
          ),
        ),
      ),
    );
  }
}
