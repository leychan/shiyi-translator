import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/popup.dart';
import 'package:just_translator/widgets/provider_dialog.dart';

import 'support.dart';

void main() {
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
      await tester.enterText(
        find.widgetWithText(TextFormField, '显示名称'),
        '百度翻译',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'APP ID'),
        'test-app',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密钥（Secret Key）'),
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
