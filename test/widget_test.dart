import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/app_identity.dart';
import 'package:just_translator/models.dart';

import 'support.dart';

void main() {
  testWidgets(
    'dragging a handle saves provider order and orders the main results',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 1040);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final providers = [
        provider(id: 'one'),
        provider(id: 'two'),
        provider(id: 'three'),
      ];
      final store = MemoryStore();
      final app = AppController(
        settings: AppSettings(providers: providers),
        store: store,
      );
      addTearDown(app.dispose);
      app.goTo(1);
      app.results = [
        for (final p in providers.reversed)
          TranslationResult(provider: p)
            ..text = '译文 ${p.id}'
            ..status = ResultStatus.complete,
      ];
      await tester.pumpWidget(TranslatorApp(controller: app));
      await tester.pumpAndSettle();
      final first = tester.getCenter(
        find.byKey(const Key('provider-drag-one')),
      );
      final last = tester.getCenter(
        find.byKey(const Key('provider-drag-three')),
      );
      final gesture = await tester.startGesture(last);
      await tester.pump();
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(first + const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(app.settings.providers.map((p) => p.id), ['three', 'one', 'two']);
      expect(store.saves, 1);
      app.goTo(0);
      await tester.pumpAndSettle();
      final thirdY = tester
          .getTopLeft(find.byKey(const Key('translation-result-three')))
          .dy;
      final firstY = tester
          .getTopLeft(find.byKey(const Key('translation-result-one')))
          .dy;
      final secondY = tester
          .getTopLeft(find.byKey(const Key('translation-result-two')))
          .dy;
      expect(thirdY, lessThan(firstY));
      expect(firstY, lessThan(secondY));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('onboarding, service form validation, and navigation', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(1180, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(
      settings: AppSettings(interfaceLanguage: InterfaceLanguage.zh),
      store: MemoryStore(),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(TranslatorApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('让不同的语言，彼此靠近'), findsOneWidget);
    await tester.tap(find.text('添加翻译服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存服务'));
    await tester.pumpAndSettle();
    expect(find.text('请为这个服务取一个名字'), findsOneWidget);
    expect(find.text('请填写模型名称'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有翻译记录'), findsOneWidget);
    await tester.tap(find.text('偏好设置'));
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'About and settings follow the system and honor saved overrides',
    (tester) async {
      tester.view.physicalSize = const Size(600, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = tester.binding.platformDispatcher;
      platform.localesTestValue = const [Locale('zh', 'CN')];
      addTearDown(platform.clearLocalesTestValue);
      final store = MemoryStore();
      final app = AppController(
        settings: AppSettings.fromJson({}),
        store: store,
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(TranslatorApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(find.text('版本 $appVersion'), findsOneWidget);
      expect(find.text(appRepository), findsOneWidget);

      platform.localesTestValue = const [Locale('fr', 'FR')];
      await tester.pumpAndSettle();
      expect(find.text('Version $appVersion'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final languageMenu = find.byKey(const Key('interface-language'));
      final themeDropdown = tester.widget<DropdownButton<ThemeMode>>(
        find.byKey(const Key('theme-mode')),
      );
      expect(
        tester.widget<DropdownButton<InterfaceLanguage>>(languageMenu).style,
        themeDropdown.style,
      );
      await tester.tap(languageMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文').last);
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsOneWidget);
      expect(
        AppSettings.fromJson(store.settings.toJson()).interfaceLanguage,
        InterfaceLanguage.zh,
      );

      await tester.tap(languageMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      platform.localesTestValue = const [Locale('zh', 'CN')];
      await tester.pumpAndSettle();
      expect(find.text('Interface language'), findsOneWidget);
      expect(store.settings.toJson()['interfaceLanguage'], 'en');

      await tester.tap(languageMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow system').last);
      await tester.pumpAndSettle();
      expect(find.text('界面语言'), findsOneWidget);
      expect(store.settings.toJson()['interfaceLanguage'], 'system');

      tester.view.physicalSize = const Size(1024, 540);
      await tester.pumpAndSettle();
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();
      expect(find.text('版本 $appVersion'), findsOneWidget);
      platform.localesTestValue = const [Locale('en', 'US')];
      await tester.pumpAndSettle();
      expect(find.text('Version $appVersion'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'minimum window size has no layout overflow in light and dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(600, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(settings: AppSettings(), store: MemoryStore());
      addTearDown(app.dispose);
      await tester.pumpWidget(TranslatorApp(controller: app));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      app.settings.darkMode = true;
      app.settingsChanged();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      app.goTo(1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
