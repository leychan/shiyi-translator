import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/desktop_service.dart';
import 'package:just_translator/services/instance_service.dart';
import 'package:just_translator/services/linux_tray_status.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../test/autostart_service_test.dart' show FakeAutostart;
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux tray registers again after native destruction', (tester) async {
    if (!Platform.isLinux) return;
    await windowManager.ensureInitialized();
    await tester.pumpWidget(const SizedBox.shrink());
    final app = AppController(settings: AppSettings(), store: MemoryStore());
    final desktop = DesktopService(
      app,
      InstanceService(),
      autostart: FakeAutostart(),
    );
    final status = LinuxTrayStatus();
    try {
      await desktop.initialize(bindShortcut: false, showMain: false);
      // 首次连接失败时使用与后台定时器相同的恢复入口。
      for (var attempt = 0; attempt < 3 && !desktop.trayReady; attempt++) {
        await desktop.refreshTray();
      }
      expect(await status.isAvailable(), true);
      await trayManager.destroy();
      expect(await status.isAvailable(), false);
      await desktop.refreshTray();
      expect(desktop.trayReady, true);
      expect(await status.isAvailable(), true);
      expect(app.notice, isNull);
    } finally {
      desktop.dispose();
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      app.dispose();
    }
  });
}
