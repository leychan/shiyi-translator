import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/autostart_service.dart';
import 'package:just_translator/services/desktop_service.dart';
import 'package:just_translator/services/instance_service.dart';

import 'support.dart';

class FakeAutostart extends AutostartService {
  bool enabled = false;
  bool fail = false;
  int writes = 0;
  Completer<void>? pending;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async {
    writes++;
    await pending?.future;
    if (fail) throw StateError('denied');
    enabled = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AutostartService service;
  late File entry;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shiyi-autostart-test-');
    service = AutostartService(
      executable: '/opt/My Translator/shiyi',
      environment: {
        'HOME': root.path,
        'XDG_CONFIG_HOME': '${root.path}/config',
      },
      operatingSystem: 'linux',
    );
    entry = File(
      '${root.path}/config/autostart/${AutostartService.desktopId}.desktop',
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test('user startup entry is created, read and removed without touching other entries', () async {
    expect(await service.isEnabled(), false);
    await service.setEnabled(true);
    expect(await service.isEnabled(), true);
    final content = await entry.readAsString();
    expect(content, contains('Exec="/opt/My Translator/shiyi" --autostart'));
    expect(content, contains('Name[zh_CN]=拾译'));
    final other = File('${entry.parent.path}/other.desktop');
    await other.writeAsString('unrelated');
    await service.setEnabled(true);
    expect(await service.isEnabled(), true);
    await service.setEnabled(false);
    await service.setEnabled(false);
    expect(await service.isEnabled(), false);
    expect(await other.readAsString(), 'unrelated');
    expect(await File('${entry.path}.tmp').exists(), false);
  });

  test('status respects desktop environment disable flags', () async {
    await service.setEnabled(true);
    final enabled = await entry.readAsString();
    await entry.writeAsString(
      enabled.replaceFirst('Hidden=false', 'Hidden=true'),
    );
    expect(await service.isEnabled(), false);
    await entry.writeAsString(
      enabled.replaceFirst(
        'X-GNOME-Autostart-enabled=true',
        'X-GNOME-Autostart-enabled=false',
      ),
    );
    expect(await service.isEnabled(), false);
    await entry.writeAsString(enabled);
    expect(await service.isEnabled(), true);
  });

  test('relative XDG_CONFIG_HOME falls back to the user configuration directory', () async {
    final fallback = AutostartService(
      executable: '/opt/shiyi',
      environment: {'HOME': root.path, 'XDG_CONFIG_HOME': 'relative'},
      operatingSystem: 'linux',
    );
    await fallback.setEnabled(true);
    expect(
      await File(
        '${root.path}/.config/autostart/${AutostartService.desktopId}.desktop',
      ).exists(),
      true,
    );
    expect(await fallback.isEnabled(), true);
    await fallback.setEnabled(false);
  });

  test('invalid executable cannot inject desktop entry keys', () async {
    final invalid = AutostartService(
      executable: '/opt/shiyi\nHidden=true',
      environment: {'HOME': root.path},
      operatingSystem: 'linux',
    );
    await expectLater(invalid.setEnabled(true), throwsFormatException);
    expect(await Directory('${root.path}/.config').exists(), false);
  });

  test('desktop launcher passes a single background argument even with special path characters', () async {
    final executable = File(
      '${root.path}/Shiyi "quoted" \\ dollar\$ percent% 中文',
    );
    final output = File('${root.path}/arguments.txt');
    await executable.writeAsString(
      '#!/bin/sh\nprintf "%s" "\$1" > "${output.path}"\n',
    );
    expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    final special = AutostartService(
      executable: executable.path,
      environment: {
        'HOME': root.path,
        'XDG_CONFIG_HOME': '${root.path}/config',
      },
      operatingSystem: 'linux',
    );
    await special.setEnabled(true);
    final validation = await Process.run('desktop-file-validate', [entry.path]);
    expect(
      validation.exitCode,
      0,
      reason: validation.stdout.toString() + validation.stderr.toString(),
    );
    final launched = await Process.run('gio', ['launch', entry.path]);
    expect(launched.exitCode, 0, reason: launched.stderr.toString());
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!await output.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await output.readAsString(), '--autostart');
  }, skip: !Platform.isLinux);

  test(
    'native desktop implementations receive only the requested enable state',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var registered = false;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AutostartService.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'isAutostartEnabled') return registered;
        registered = (call.arguments as Map)['enabled'] as bool;
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(AutostartService.channel, null),
      );
      for (final platform in ['windows', 'macos']) {
        final native = AutostartService(operatingSystem: platform);
        expect(await native.isEnabled(), false);
        await native.setEnabled(true);
        expect(await native.isEnabled(), true);
        await native.setEnabled(false);
        expect(await native.isEnabled(), false);
      }
      expect(
        calls
            .where((call) => call.method == 'setAutostartEnabled')
            .map((call) => call.arguments),
        [
          {'enabled': true},
          {'enabled': false},
          {'enabled': true},
          {'enabled': false},
        ],
      );
    },
  );

  test(
    'failed registration keeps the switch unchanged and reports an error',
    () async {
      final backend = FakeAutostart();
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final desktop = DesktopService(
        app,
        InstanceService(),
        autostart: backend,
      );
      addTearDown(() {
        desktop.dispose();
        app.dispose();
      });
      await desktop.refreshAutostart();
      await desktop.setAutostartEnabled(true);
      expect(desktop.autostartEnabled, true);
      backend.fail = true;
      await desktop.setAutostartEnabled(false);
      expect(desktop.autostartEnabled, true);
      expect(desktop.autostartBusy, false);
      expect(app.notice, contains('无法修改开机自启动'));
    },
  );

  test(
    'pending registration blocks duplicate writes and tolerates disposal',
    () async {
      final backend = FakeAutostart()..pending = Completer<void>();
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final desktop = DesktopService(
        app,
        InstanceService(),
        autostart: backend,
      );
      final pending = desktop.setAutostartEnabled(true);
      expect(desktop.autostartBusy, true);
      await desktop.setAutostartEnabled(false);
      expect(backend.writes, 1);
      desktop.dispose();
      app.dispose();
      backend.pending!.complete();
      await pending;
    },
  );

  test(
    'autostart forwarding does not show a window or start selection capture',
    () async {
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final desktop = DesktopService(
        app,
        InstanceService(),
        autostart: FakeAutostart(),
      );
      addTearDown(() {
        desktop.dispose();
        app.dispose();
      });
      await desktop.handleAction('autostart');
      expect(app.input, isEmpty);
      expect(app.results, isEmpty);
    },
  );
}
