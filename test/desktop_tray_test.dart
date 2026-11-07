import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/desktop_service.dart';
import 'package:just_translator/services/instance_service.dart';

import 'autostart_service_test.dart' show FakeAutostart;
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const tray = MethodChannel('tray_manager');
  const screen = MethodChannel('dev.leanflutter.plugins/screen_retriever');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final display = {
    'id': 'test',
    'size': {'width': 1920.0, 'height': 1080.0},
    'visiblePosition': {'dx': 0.0, 'dy': 0.0},
  };
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(window, (call) async {
      calls.add(call);
      if (call.method.startsWith('is')) return false;
      if (call.method == 'getBounds') {
        return {'x': 0.0, 'y': 0.0, 'width': 1180.0, 'height': 780.0};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(tray, (_) async => true);
    messenger.setMockMethodCallHandler(screen, (call) async {
      if (call.method == 'getAllDisplays') {
        return {
          'displays': [display],
        };
      }
      if (call.method == 'getCursorScreenPoint') return {'dx': 0.0, 'dy': 0.0};
      return display;
    });
  });
  tearDown(() {
    for (final channel in [window, tray, screen]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'losing the tray restores the window and prevents hiding it on close',
    () async {
      var available = true;
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final desktop = DesktopService(
        app,
        InstanceService(),
        autostart: FakeAutostart(),
        trayAvailable: () async => available,
      );
      try {
        await desktop.initialize(bindShortcut: false, showMain: false);
        expect(desktop.trayReady, true);
        calls.clear();
        available = false;
        await desktop.refreshTray();
        expect(desktop.trayReady, false);
        expect(calls.map((c) => c.method), contains('show'));
        expect(app.notice, contains('托盘暂不可用'));
        calls.clear();
        desktop.onWindowClose();
        await desktop.refreshTray();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(calls.map((c) => c.method), contains('show'));
        expect(calls.map((c) => c.method), isNot(contains('hide')));
        expect(calls.map((c) => c.method), isNot(contains('destroy')));
        available = true;
        await desktop.refreshTray();
        calls.clear();
        desktop.onWindowClose();
        await desktop.refreshTray();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(calls.map((c) => c.method), contains('hide'));
      } finally {
        desktop.dispose();
        app.dispose();
      }
    },
  );

  test(
    'native success without desktop registration does not hide startup',
    () async {
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final desktop = DesktopService(
        app,
        InstanceService(),
        autostart: FakeAutostart(),
        trayAvailable: () async => false,
      );
      try {
        await desktop.initialize(bindShortcut: false, showMain: false);
        expect(desktop.trayReady, false);
        expect(calls.map((c) => c.method), contains('show'));
        expect(app.notice, contains('托盘暂不可用'));
      } finally {
        desktop.dispose();
        app.dispose();
      }
    },
  );

  test(
    'failed native tray creation keeps background startup reachable',
    () async {
      messenger.setMockMethodCallHandler(tray, (_) async {
        throw PlatformException(code: 'tray-unavailable');
      });
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final desktop = DesktopService(
        app,
        InstanceService(),
        autostart: FakeAutostart(),
        trayAvailable: () async => false,
      );
      try {
        await desktop.initialize(bindShortcut: false, showMain: false);
        expect(desktop.trayReady, false);
        expect(calls.map((c) => c.method), contains('show'));
        expect(
          calls.where((c) => c.method == 'setPreventClose').last.arguments,
          {'isPreventClose': true},
        );
      } finally {
        desktop.dispose();
        app.dispose();
      }
    },
  );
  test('recreates a failed native tray on the periodic retry', () async {
    var creations = 0;
    var registered = false;
    messenger.setMockMethodCallHandler(tray, (call) async {
      if (call.method == 'setIcon') {
        creations++;
        if (creations == 1) {
          throw PlatformException(code: 'bus-not-ready');
        }
      }
      if (call.method == 'setContextMenu') registered = true;
      return true;
    });
    final app = AppController(settings: AppSettings(), store: MemoryStore());
    final desktop = DesktopService(
      app,
      InstanceService(),
      autostart: FakeAutostart(),
      trayAvailable: () async => registered,
    );
    try {
      await desktop.initialize(bindShortcut: false, showMain: false);
      expect(desktop.trayReady, false);
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(creations, 2);
      expect(desktop.trayReady, true);
      expect(app.notice, isNull);
    } finally {
      desktop.dispose();
      app.dispose();
    }
  });

  test('unregistered tray is destroyed and concurrent retries are merged', () async {
    final nativeCalls = <String>[];
    var registered = false;
    messenger.setMockMethodCallHandler(tray, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'setContextMenu' && nativeCalls.contains('destroy')) {
        registered = true;
      }
      return true;
    });
    final app = AppController(settings: AppSettings(), store: MemoryStore());
    final desktop = DesktopService(
      app,
      InstanceService(),
      autostart: FakeAutostart(),
      trayAvailable: () async => registered,
    );
    try {
      await desktop.initialize(bindShortcut: false, showMain: false);
      expect(desktop.trayReady, false);
      await Future.wait([desktop.refreshTray(), desktop.refreshTray()]);
      expect(desktop.trayReady, true);
      expect(nativeCalls.where((m) => m == 'destroy').length, 1);
      expect(nativeCalls.where((m) => m == 'setIcon').length, 2);
      expect(app.notice, isNull);
      nativeCalls.clear();
      await desktop.refreshTray();
      expect(nativeCalls, isEmpty);
      desktop.dispose();
      await desktop.refreshTray();
      expect(nativeCalls, isEmpty);
    } finally {
      app.dispose();
    }
  });

}
