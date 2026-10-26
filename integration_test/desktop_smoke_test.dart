import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_translator/app.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/popup.dart';
import 'package:just_translator/popup_placement.dart';
import 'package:just_translator/services/pointer_placement_service.dart';
import 'package:just_translator/services/desktop_service.dart';
import 'package:just_translator/services/instance_service.dart';
import 'package:just_translator/services/popup_service.dart';
import 'package:just_translator/services/selection_service.dart';
import 'package:just_translator/services/translation_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import '../test/support.dart';

class FixtureSelection extends SelectionService {
  @override
  Future<SelectionCapture> readSelection() async =>
      const SelectionCapture('Hello Pot.', '划词取词');
}

class FixtureTranslator extends TranslationService {
  @override
  Future<String> translate(
    TranslationRequest input,
    CancellationToken token, {
    void Function(String)? onPartial,
  }) async => '你好，Pot。';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'KDE positions the native popup near the anchor and flips at screen edges',
    (tester) async {
      if (!Platform.isLinux ||
          Platform.environment['XDG_SESSION_TYPE'] != 'wayland' ||
          !(Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
              .toLowerCase()
              .contains('kde')) {
        return;
      }
      final bridge = KWinPlacementBridge();
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      final window = PopupWindow();
      try {
        await windowManager.ensureInitialized();
        final captured = await bridge.capture();
        expect(captured.workArea.width, greaterThan(0));
        await tester.pumpWidget(PopupApp(controller: app, window: window));
        await tester.pumpAndSettle();
        await window.initialize();
        await window.togglePin();
        Future<void> verify(Offset cursor) async {
          final anchor = PopupAnchor(
            cursor: cursor,
            workArea: captured.workArea,
          );
          await window.show(
            anchor: anchor,
            preparePosition: () async {
              await bridge.prepare(pid, anchor);
              return true;
            },
          );
          await tester.pumpAndSettle();
          Rect? geometry;
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (DateTime.now().isBefore(deadline)) {
            geometry = await bridge.popupGeometry(pid);
            if (geometry != null) {
              final expected = popupBoundsNear(anchor, geometry.size);
              if ((geometry.topLeft - expected.topLeft).distance < 2) break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(geometry, isNotNull);
          final expected = popupBoundsNear(anchor, geometry!.size);
          expect((geometry.topLeft - expected.topLeft).distance, lessThan(2));
          expect(geometry.left, greaterThanOrEqualTo(captured.workArea.left));
          expect(geometry.bottom, lessThanOrEqualTo(captured.workArea.bottom));
        }

        await verify(captured.workArea.topLeft + const Offset(80, 80));
        await window.hide();
        await verify(captured.workArea.bottomRight - const Offset(20, 20));
      } finally {
        await window.hide();
        window.dispose();
        await bridge.dispose();
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setPreventClose(false);
        await tester.pumpWidget(const SizedBox.shrink());
        app.dispose();
      }
    },
  );

  testWidgets(
    'desktop window, service configuration, history, compact and dark layouts',
    (tester) async {
      await windowManager.ensureInitialized();
      final boundaryKey = GlobalKey();
      final store = MemoryStore();
      final app = AppController(
        settings: AppSettings(),
        store: store,
        translator: FixtureTranslator(),
      );
      final sessionDirectory = await Directory.systemTemp.createTemp(
        'just-translator-desktop-',
      );
      final instance = InstanceService(directory: sessionDirectory);
      await instance.startOrForward('show');
      final desktop = DesktopService(app, instance);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: TranslatorApp(controller: app, desktop: desktop),
        ),
      );
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(size: Size(1180, 780)),
        () async {
          await windowManager.show();
        },
      );
      await tester.pumpAndSettle();
      await desktop.initialize(bindShortcut: false);
      expect(desktop.trayReady, true);

      Future<void> screenshot(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/screenshots');
        await directory.create(recursive: true);
        await File('${directory.path}/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      }

      await screenshot('01-translate');
      await tester.tap(find.text('添加翻译服务'));
      await tester.pumpAndSettle();
      await screenshot('02-add-service');
      await tester.enterText(
        find.widgetWithText(TextFormField, '显示名称'),
        '本地翻译服务',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '模型名称'),
        'test-model',
      );
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('测试成功'), findsOneWidget);
      expect(find.text('你好，Pot。'), findsOneWidget);
      expect(app.settings.providers, isEmpty);
      expect(store.saves, 0);
      await screenshot('11-service-test');
      await tester.tap(find.text('保存服务'));
      await tester.pumpAndSettle();
      expect(app.settings.providers.single.name, '本地翻译服务');
      app.goTo(1);
      await screenshot('03-services');
      app.settings.history = [
        HistoryEntry(
          id: 'test',
          text: 'Good design makes the complex feel simple.',
          source: 'en',
          target: 'zh',
          createdAt: DateTime(2026, 10, 26, 14, 30),
          translations: {'测试服务 · test': '好的设计，让复杂变得简单。'},
        ),
      ];
      app.restoreHistory(app.settings.history.single);
      await screenshot('04-translation-result');
      app.goTo(2);
      await screenshot('05-history');
      app.goTo(3);
      await screenshot('06-settings');
      app.settings.darkMode = true;
      app.goTo(0);
      await screenshot('07-dark');
      await windowManager.setSize(const Size(640, 720));
      await tester.pumpAndSettle();
      await screenshot('08-compact');
      app.settings.darkMode = false;
      app.results = [
        TranslationResult(
            provider: const ProviderConfig(
              id: 'baidu',
              name: '百度翻译',
              kind: ProviderKind.baidu,
              endpoint: 'https://fanyi-api.baidu.com',
            ),
          )
          ..text = '好的设计，让复杂变得简单。'
          ..status = ResultStatus.complete,
        TranslationResult(provider: provider())
          ..text = '好的设计使复杂的事物变得简单。'
          ..status = ResultStatus.complete,
      ];
      final popupWindow = PopupWindow();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PopupApp(
            controller: app,
            window: popupWindow,
            openSettings: () async {},
          ),
        ),
      );
      await popupWindow.initialize();
      await popupWindow.show();
      await popupWindow.togglePin();
      await screenshot('09-independent-popup');
      if (Platform.isLinux) {
        final native = await const MethodChannel(
          'dev.justtranslator/window-diagnostics',
        ).invokeMapMethod<String, dynamic>('inspectSurface');
        expect(native!['visualDepth'], 32);
        expect(
          native['cornerAlpha'],
          [0, 0, 0, 0],
          reason:
              'GTK and Flutter must both preserve transparent rounded corners.',
        );
        expect(
          native['centerAlpha'],
          255,
          reason: 'The popup content must remain opaque.',
        );
      }
      await tester.tap(find.byKey(const ValueKey('popup-result-baidu')));
      await tester.pumpAndSettle();
      expect(find.text('好的设计，让复杂变得简单。'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('popup-result-baidu')));
      await tester.pumpAndSettle();
      app.settings.darkMode = true;
      app.settingsChanged();
      await screenshot('10-popup-dark');
      if (Platform.isLinux) {
        final native = await const MethodChannel(
          'dev.justtranslator/window-diagnostics',
        ).invokeMapMethod<String, dynamic>('inspectSurface');
        expect(native!['cornerAlpha'], [0, 0, 0, 0]);
        expect(native['centerAlpha'], 255);
      }
      await popupWindow.hide();
      expect(await windowManager.isVisible(), false);
      popupWindow.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      desktop.dispose();
      await instance.close();
      await sessionDirectory.delete(recursive: true);
      app.dispose();
    },
  );

  testWidgets(
    'release executable forwards to existing instance without opening another window',
    (tester) async {
      if (!Platform.isLinux) return;
      final release = File('build/linux/x64/release/bundle/just_translator')
          .absolute;
      expect(
        await release.exists(),
        true,
        reason:
            'Build the release app before running desktop integration tests.',
      );
      final root = await Directory.systemTemp.createTemp(
        'just-translator-forward-',
      );
      final directory = Directory(
        '${root.path}/dev.justtranslator.just_translator',
      );
      final instance = InstanceService(directory: directory);
      final actions = <String>[];
      try {
        await instance.startOrForward('show');
        instance.onAction = (action) async {
          actions.add(action);
        };
        final result = await Process.run(
          release.path,
          ['--selection'],
          environment: {'XDG_DATA_HOME': root.path},
        ).timeout(const Duration(seconds: 15));
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(actions, ['selection']);
      } finally {
        await instance.close();
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'hotkey capture opens a separate popup and leaves the management window hidden',
    (tester) async {
      if (!Platform.isLinux) return;
      final release = File('build/linux/x64/release/bundle/just_translator')
          .absolute;
      final root = await Directory.systemTemp.createTemp(
        'just-translator-popup-desktop-',
      );
      final instance = InstanceService(
        directory: Directory('${root.path}/dev.justtranslator.just_translator'),
      );
      final main = AppController(
        settings: AppSettings(providers: [provider()]),
        store: MemoryStore(),
      );
      final popup = PopupService(
        main,
        executable: release.path,
        environment: {'XDG_DATA_HOME': root.path},
        translator: FixtureTranslator(),
      );
      final desktop = DesktopService(
        main,
        instance,
        popup: popup,
        selection: FixtureSelection(),
      );
      try {
        await instance.startOrForward('show');
        await desktop.initialize(bindShortcut: false, showMain: false);
        main.input = 'Keep this draft';
        main.page = 2;
        await desktop.capture();
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        while (!popup.connected && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(popup.connected, true);
        expect(popup.isRunning, true);
        expect(await windowManager.isVisible(), false);
        expect(main.input, 'Keep this draft');
        expect(main.page, 2);
        expect(popup.controller.results.single.text, '你好，Pot。');
        if (Platform.environment['XDG_SESSION_TYPE'] == 'wayland' &&
            (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
                .toLowerCase()
                .contains('kde')) {
          final anchor = PopupAnchor.fromJson(
            popup.snapshot()['anchor'] as Map<String, dynamic>,
          );
          final inspector = KWinPlacementBridge();
          try {
            Rect? geometry;
            final deadline = DateTime.now().add(const Duration(seconds: 3));
            while (DateTime.now().isBefore(deadline)) {
              geometry = await inspector.popupGeometry(popup.processId!);
              if (geometry != null &&
                  (geometry.topLeft -
                              popupBoundsNear(anchor, geometry.size).topLeft)
                          .distance <
                      2) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(geometry, isNotNull);
            expect(
              (geometry!.topLeft -
                      popupBoundsNear(anchor, geometry.size).topLeft)
                  .distance,
              lessThan(2),
            );
          } finally {
            await inspector.dispose();
          }
        }
        await desktop.capture();
        expect(await windowManager.isVisible(), false);
        expect(popup.controller.input, 'Hello Pot.');
      } finally {
        desktop.dispose();
        await popup.dispose();
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await instance.close();
        main.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
