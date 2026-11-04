import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/popup.dart';

import 'support.dart';

void main() {
  test(
    'new settings follow the system and legacy settings keep their theme',
    () {
      expect(AppSettings().themeMode, ThemeMode.system);
      expect(AppSettings.fromJson({}).themeMode, ThemeMode.system);
      for (final dark in [false, true]) {
        final mode = dark ? ThemeMode.dark : ThemeMode.light;
        expect(AppSettings(darkMode: dark).themeMode, mode);
        expect(AppSettings.fromJson({'darkMode': dark}).themeMode, mode);
      }
    },
  );

  test(
    'all theme modes survive JSON persistence and override legacy values',
    () {
      for (final mode in ThemeMode.values) {
        final settings = AppSettings(themeMode: mode);
        final json =
            jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;
        expect(json['themeMode'], mode.name);
        expect(AppSettings.fromJson(json).themeMode, mode);
        expect(
          AppSettings.fromJson({'themeMode': mode.name, 'darkMode': true})
              .themeMode,
          mode,
        );
      }
      expect(
        AppSettings.fromJson({'themeMode': 'unknown'}).themeMode,
        ThemeMode.system,
      );
    },
  );

  for (final popup in [false, true]) {
    testWidgets(
      '${popup ? 'popup' : 'main window'} follows system brightness live',
      (tester) async {
        tester.view.physicalSize = popup
            ? const Size(480, 700)
            : const Size(1180, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final platform = tester.binding.platformDispatcher;
        platform.platformBrightnessTestValue = Brightness.light;
        addTearDown(platform.clearPlatformBrightnessTestValue);
        final app = AppController(
          settings: AppSettings(),
          store: MemoryStore(),
        );
        addTearDown(app.dispose);
        await tester.pumpWidget(
          popup ? PopupApp(controller: app) : TranslatorApp(controller: app),
        );
        await tester.pumpAndSettle();
        Brightness brightness() =>
            Theme.of(tester.element(find.byType(Scaffold))).brightness;
        expect(brightness(), Brightness.light);

        platform.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.dark);
        platform.platformBrightnessTestValue = Brightness.light;
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.light);

        app.settings.themeMode = ThemeMode.dark;
        app.settingsChanged();
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.dark);
        platform.platformBrightnessTestValue = Brightness.dark;
        app.settings.themeMode = ThemeMode.light;
        app.settingsChanged();
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.light);

        app.settings.themeMode = ThemeMode.system;
        app.settingsChanged();
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.dark);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('theme selector saves all three modes at minimum window size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStore();
    final app = AppController(settings: AppSettings(), store: store);
    addTearDown(app.dispose);
    app.goTo(3);
    await tester.pumpWidget(TranslatorApp(controller: app));
    await tester.pumpAndSettle();
    for (final (label, mode) in [
      ('深色', ThemeMode.dark),
      ('浅色', ThemeMode.light),
      ('跟随系统', ThemeMode.system),
    ]) {
      await tester.tap(find.byKey(const Key('theme-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(app.settings.themeMode, mode);
      expect(store.settings.toJson()['themeMode'], mode.name);
      expect(tester.takeException(), isNull);
    }
    expect(store.saves, 3);
  });
}
