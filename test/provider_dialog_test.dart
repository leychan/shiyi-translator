import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/translation_service.dart';
import 'package:just_translator/widgets/provider_dialog.dart';

import 'support.dart';

class PendingTest {
  PendingTest(this.request, this.token);
  final TranslationRequest request;
  final CancellationToken token;
  final result = Completer<String>();
}

class TestTranslator extends TranslationService {
  final calls = <PendingTest>[];

  @override
  Future<String> translate(
    TranslationRequest input,
    CancellationToken token, {
    void Function(String text)? onPartial,
  }) {
    final call = PendingTest(input, token);
    calls.add(call);
    // Deliberately allow late replies to verify that the dialog ignores them.
    return call.result.future;
  }
}

void main() {
  late MemoryStore store;
  late TestTranslator translator;
  late AppController app;

  setUp(() {
    store = MemoryStore();
    translator = TestTranslator();
    app = AppController(
      settings: AppSettings(),
      store: store,
      translator: translator,
    );
  });
  tearDown(() => app.dispose());

  Future<void> open(
    WidgetTester tester, {
    ProviderKind kind = ProviderKind.compatible,
    ProviderConfig? existing,
    Size size = const Size(900, 900),
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TranslatorApp.buildTheme(
          dark ? Brightness.dark : Brightness.light,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ProviderDialog(
                  controller: app,
                  initialKind: kind,
                  provider: existing,
                ),
              ),
              child: const Text('打开服务'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开服务'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String value) async {
    final key = switch (label) {
      '显示名称' => 'name',
      '模型名称' => 'model',
      '服务地址' => 'endpoint',
      'APP ID' => 'app-id',
      _ => 'api-key',
    };
    final input = find.byKey(Key('provider-$key'));
    await tester.ensureVisible(input);
    await tester.enterText(input, value);
    await tester.pump();
  }

  testWidgets(
    'compact dark editor keeps actions visible while the form scrolls',
    (tester) async {
      await open(tester, size: const Size(600, 540), dark: true);
      expect(find.text('测试连接').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('provider-save')).hitTestable(),
        findsOneWidget,
      );
      await fill(tester, '模型名称', 'compact-model');
      await fill(tester, 'API Key（按服务要求填写）', 'test-key');
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      translator.calls.single.result.complete('你好，世界！');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('测试成功'));
      await tester.pumpAndSettle();
      expect(find.text('测试成功').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const Key('provider-save')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tests unsaved Baidu credentials without persisting or history', (
    tester,
  ) async {
    await open(tester, kind: ProviderKind.baidu);
    await fill(tester, '服务地址', 'http://localhost:8888');
    await fill(tester, 'APP ID', 'unsaved-app');
    await fill(tester, '密钥（Secret Key）', 'unsaved-secret');
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    final call = translator.calls.single;
    expect(call.request.provider.kind, ProviderKind.baidu);
    expect(call.request.provider.endpoint, 'http://localhost:8888');
    expect(call.request.provider.appId, 'unsaved-app');
    expect(call.request.apiKey, 'unsaved-secret');
    expect(call.request.text, 'Hello, world!');
    expect(call.request.source, 'en');
    expect(call.request.target, 'zh');
    expect(find.text('正在测试…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('provider-save')))
          .onPressed,
      isNull,
    );
    call.result.complete('你好，世界！');
    await tester.pumpAndSettle();
    expect(find.text('测试成功'), findsOneWidget);
    expect(find.text('你好，世界！'), findsOneWidget);
    expect(app.settings.providers, isEmpty);
    expect(app.settings.history, isEmpty);
    expect(app.results, isEmpty);
    expect(store.saves, 0);
    expect(store.keys, isEmpty);
    // The display name is optional for testing, but remains required to save.
    await tester.tap(find.text('保存服务'));
    await tester.pumpAndSettle();
    expect(find.text('请为这个服务取一个名字'), findsOneWidget);
    await fill(tester, '显示名称', '百度测试');
    expect(find.text('测试成功'), findsNothing);
    await tester.tap(find.text('保存服务'));
    await tester.pumpAndSettle();
    expect(app.settings.providers.single.appId, 'unsaved-app');
    expect(store.keys.values.single, 'unsaved-secret');
  });

  testWidgets('validates required connection fields before calling a service', (
    tester,
  ) async {
    await open(tester, kind: ProviderKind.baidu);
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('请填写百度翻译 APP ID'), findsOneWidget);
    expect(find.text('请填写百度翻译密钥'), findsOneWidget);
    expect(find.text('请为这个服务取一个名字'), findsNothing);
    expect(translator.calls, isEmpty);
  });

  testWidgets(
    'shows adapter failure and retries with the current model and key',
    (tester) async {
      await open(tester);
      await fill(tester, '模型名称', 'first-model');
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      translator.calls.single.result.completeError(
        const TranslationFailure('认证失败，请检查 API Key。'),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试失败'), findsOneWidget);
      expect(find.text('认证失败，请检查 API Key。'), findsOneWidget);
      await fill(tester, '模型名称', 'second-model');
      await fill(tester, 'API Key（按服务要求填写）', 'new-key');
      expect(find.text('测试失败'), findsNothing);
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      expect(translator.calls.last.request.provider.model, 'second-model');
      expect(translator.calls.last.request.provider.streaming, isTrue);
      expect(translator.calls.last.request.apiKey, 'new-key');
      translator.calls.last.result.complete('重试成功');
      await tester.pumpAndSettle();
      expect(find.text('测试成功'), findsOneWidget);
      expect(store.saves, 0);
    },
  );

  testWidgets('editing or cancelling aborts a test and discards late replies', (
    tester,
  ) async {
    await open(tester);
    await fill(tester, '模型名称', 'test-model');
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    final oldCall = translator.calls.single;
    await fill(tester, '模型名称', 'changed-model');
    expect(oldCall.token.cancelled, isTrue);
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    oldCall.result.complete('过时的结果');
    await tester.pump();
    expect(find.text('过时的结果'), findsNothing);
    expect(find.text('正在测试…'), findsOneWidget);
    await tester.tap(find.text('取消测试'));
    await tester.pumpAndSettle();
    expect(translator.calls.last.token.cancelled, isTrue);
    translator.calls.last.result.complete('取消后的结果');
    await tester.pumpAndSettle();
    expect(find.text('测试成功'), findsNothing);
    expect(find.text('取消后的结果'), findsNothing);
  });

  testWidgets(
    'editing an existing service uses stored key and close aborts request',
    (tester) async {
      final existing = provider().withCredential(true);
      store.keys[existing.id] = 'stored-secret';
      await open(tester, existing: existing);
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      final call = translator.calls.single;
      expect(call.request.apiKey, 'stored-secret');
      expect(call.request.provider.id, existing.id);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(call.token.cancelled, isTrue);
      call.result.complete('关闭后的结果');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(store.saves, 0);
    },
  );
}
