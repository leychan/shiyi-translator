import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/popup.dart';
import 'package:just_translator/widgets/provider_dialog.dart';

import 'support.dart';

class MeasuringPopupWindow extends PopupWindow {
  double? contentHeight;
  @override
  Future<void> fitContent(double height) async => contentHeight = height;
}

void main() {
  testWidgets(
    'popup follows provider order and preserves collapsed cards after reorder',
    (tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final providers = [provider(id: 'one'), provider(id: 'two')];
      final app = AppController(
        settings: AppSettings(providers: providers),
        store: MemoryStore(),
      );
      addTearDown(app.dispose);
      app.input = 'Hello';
      app.results = [
        for (final p in providers.reversed)
          TranslationResult(provider: p)
            ..text = '译文 ${p.id}'
            ..status = ResultStatus.complete,
      ];
      await tester.pumpWidget(PopupApp(controller: app));
      await tester.pumpAndSettle();
      final one = find.byKey(const Key('popup-result-one'));
      final two = find.byKey(const Key('popup-result-two'));
      expect(tester.getTopLeft(one).dy, lessThan(tester.getTopLeft(two).dy));
      await tester.tap(one);
      await tester.pumpAndSettle();
      await app.reorderProviders(1, 0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(two).dy, lessThan(tester.getTopLeft(one).dy));
      expect(find.text('译文 one'), findsNothing);
      expect(find.text('译文 two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'popup measures real content, grows for text and shrinks on collapse',
    (tester) async {
      tester.view.physicalSize = const Size(480, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(
        settings: AppSettings(providers: [provider()]),
        store: MemoryStore(),
      );
      final window = MeasuringPopupWindow();
      addTearDown(app.dispose);
      addTearDown(window.dispose);
      app.input = 'Hello';
      final result = TranslationResult(provider: provider())
        ..text = '你好'
        ..status = ResultStatus.complete;
      app.results = [result];
      await tester.pumpWidget(PopupApp(controller: app, window: window));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      final short = window.contentHeight!;
      expect(short, inExclusiveRange(250, 500));
      result.text = List.filled(80, '一段需要滚动显示的译文。').join('\n');
      app.settingsChanged();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(window.contentHeight!, greaterThan(2000));
      await tester.tap(find.byKey(const ValueKey('popup-result-test')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(window.contentHeight!, lessThan(short));
      await tester.tap(find.byKey(const ValueKey('popup-result-test')));
      await tester.pumpAndSettle();
      result.text = '你好';
      app.settingsChanged();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(window.contentHeight!, closeTo(short, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'popup presents independent translation UI with collapsible providers',
    (tester) async {
      tester.view.physicalSize = const Size(480, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(
        settings: AppSettings(providers: [provider()]),
        store: MemoryStore(),
      );
      app.input = 'Hello Pot.';
      final result =
          TranslationResult(
              provider: const ProviderConfig(
                id: 'baidu',
                name: '百度翻译',
                kind: ProviderKind.baidu,
                endpoint: '',
              ),
            )
            ..text = '你好，Pot。'
            ..status = ResultStatus.complete;
      app.results = [result];
      addTearDown(app.dispose);
      await tester.pumpWidget(PopupApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.text('Hello Pot.'), findsOneWidget);
      expect(find.text('你好，Pot。'), findsOneWidget);
      expect(find.text('历史记录'), findsNothing);
      expect(find.text('偏好设置'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('popup-result-baidu')));
      await tester.pumpAndSettle();
      expect(find.text('你好，Pot。'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('popup-result-baidu')));
      await tester.pumpAndSettle();
      expect(find.text('你好，Pot。'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('popup-source')), 'New text');
      expect(app.input, 'New text');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small popup remains usable during translation in dark mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 380);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(
      settings: AppSettings(darkMode: true),
      store: MemoryStore(),
    );
    addTearDown(app.dispose);
    app.busy = true;
    await tester.pumpWidget(PopupApp(controller: app));
    await tester.pump();
    expect(find.byKey(const Key('popup-translate')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Baidu form requires APP ID and secret, saves each in the proper place',
    (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore();
      final app = AppController(settings: AppSettings(), store: store);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderDialog(
              controller: app,
              initialKind: ProviderKind.baidu,
            ),
          ),
        ),
      );
      await tester.tap(find.text('保存服务'));
      await tester.pumpAndSettle();
      expect(find.text('请填写百度翻译 APP ID'), findsOneWidget);
      expect(find.text('请填写百度翻译密钥'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('provider-name')), '百度翻译');
      await tester.enterText(
        find.byKey(const Key('provider-app-id')),
        'test-app',
      );
      await tester.enterText(
        find.byKey(const Key('provider-api-key')),
        'test-secret',
      );
      await tester.tap(find.text('保存服务'));
      await tester.pumpAndSettle();
      expect(app.settings.providers.single.appId, 'test-app');
      expect(store.keys.values.single, 'test-secret');
      expect(
        app.settings.providers.single.toJson().values,
        isNot(contains('test-secret')),
      );
    },
  );
}
