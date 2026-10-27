import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app.dart';
import 'package:just_translator/app_controller.dart';
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
    final app = AppController(settings: AppSettings(), store: MemoryStore());
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
    expect(find.text('深色模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
