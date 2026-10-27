import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/translation_service.dart';

import 'support.dart';

class ControlledTranslator extends TranslationService {
  final calls = <String, Completer<String>>{};
  @override
  Future<String> translate(
    TranslationRequest input,
    CancellationToken token, {
    void Function(String)? onPartial,
  }) {
    final completer = Completer<String>();
    calls['${input.provider.id}:${input.text}'] = completer;
    return completer.future;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

class UnwritableStore extends MemoryStore {
  @override
  Future<void> save(AppSettings value) async => throw StateError('unwritable');
}

void main() {
  late MemoryStore store;
  late ControlledTranslator translator;
  late AppController app;
  setUp(() {
    store = MemoryStore();
    translator = ControlledTranslator();
    app = AppController(
      settings: AppSettings(providers: [provider()]),
      store: store,
      translator: translator,
    );
  });
  tearDown(() {
    app.dispose();
  });

  test('provider order persists in both directions and filters disabled services in place', () async {
    app.settings.providers = [
      provider(id: 'one'),
      provider(id: 'two').withEnabled(false),
      provider(id: 'three'),
    ];
    await app.reorderProviders(0, 2);
    expect(app.settings.providers.map((p) => p.id), ['two', 'three', 'one']);
    expect(app.enabledProviders.map((p) => p.id), ['three', 'one']);
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(store.settings.toJson())),
    );
    expect(restored.providers.map((p) => p.id), ['two', 'three', 'one']);
    await app.reorderProviders(2, 0);
    expect(app.settings.providers.map((p) => p.id), ['one', 'two', 'three']);
    expect(store.saves, 2);
    await app.reorderProviders(0, 0);
    await app.reorderProviders(-1, 0);
    await app.reorderProviders(0, 4);
    expect(store.saves, 2);
  });

  test('editing a provider preserves its ordered position', () async {
    app.settings.providers = [
      provider(id: 'one'),
      provider(id: 'two'),
      provider(id: 'three'),
    ];
    await app.saveProvider(
      provider(id: 'two', endpoint: 'http://localhost:9001/v1'),
      'test-key',
    );
    expect(app.settings.providers.map((p) => p.id), ['one', 'two', 'three']);
    expect(app.settings.providers[1].endpoint, 'http://localhost:9001/v1');
  });

  test('reordering during translation preserves requests and ignores completion order', () async {
    app.settings.providers = [provider(id: 'one'), provider(id: 'two')];
    app.input = 'hello';
    final run = app.translate();
    await flush();
    translator.calls['two:hello']!.complete('第二个服务先返回');
    await flush();
    expect(app.orderedResults.map((r) => r.provider.id), ['one', 'two']);
    await app.reorderProviders(0, 1);
    expect(app.busy, true);
    expect(app.orderedResults.map((r) => r.provider.id), ['two', 'one']);
    expect(app.orderedResults.first.text, '第二个服务先返回');
    translator.calls['one:hello']!.completeError(
      const TranslationFailure('请求失败'),
    );
    await run;
    expect(app.orderedResults.map((r) => r.provider.id), ['two', 'one']);
    expect(app.orderedResults.first.status, ResultStatus.complete);
    expect(app.orderedResults.last.status, ResultStatus.failed);
    expect(app.results.map((r) => r.provider.id), ['one', 'two']);
    final cachedRun = app.translate();
    await flush();
    // The successful service remains cached after a reorder.
    expect(app.results.first.provider.id, 'two');
    expect(app.results.first.cached, true);
    translator.calls['one:hello']!.complete('第一个服务重试完成');
    await cachedRun;
  });

  test(
    'historical results follow current service order and keep removed services',
    () {
      app.settings.providers = [provider(id: 'one'), provider(id: 'two')];
      app.restoreHistory(
        HistoryEntry(
          id: 'history',
          text: 'hello',
          source: 'en',
          target: 'zh',
          createdAt: DateTime(2026),
          translations: {
            'Second · two': '二',
            'Removed · missing': '旧译文',
            'First · label · one': '一',
            'Legacy': '更早的译文',
          },
        ),
      );
      expect(app.orderedResults.map((r) => r.provider.id), [
        'one',
        'two',
        'missing',
        'history-3',
      ]);
      expect(app.orderedResults.map((r) => r.text), ['一', '二', '旧译文', '更早的译文']);
      expect(app.orderedResults.first.provider.name, 'First · label');
    },
  );

  test(
    'save failures are reported while keeping the new order usable in memory',
    () async {
      final controller = AppController(
        settings: AppSettings(
          providers: [
            provider(id: 'one'),
            provider(id: 'two'),
          ],
        ),
        store: UnwritableStore(),
      );
      addTearDown(controller.dispose);
      await controller.reorderProviders(0, 1);
      expect(controller.settings.providers.first.id, 'two');
      expect(controller.notice, contains('无法保存'));
    },
  );

  test('new request wins over late response from an older request', () async {
    app.input = 'old';
    final first = app.translate();
    await flush();
    app.input = 'new';
    final second = app.translate();
    await flush();
    translator.calls['test:new']!.complete('新的译文');
    await second;
    translator.calls['test:old']!.complete('过期译文');
    await first;
    expect(app.results.single.text, '新的译文');
    expect(app.settings.history.map((e) => e.text), ['new']);
    expect(app.busy, false);
  });

  test(
    'one failed provider does not discard another successful result',
    () async {
      app.settings.providers = [provider(id: 'one'), provider(id: 'two')];
      app.input = 'hello';
      final run = app.translate();
      await flush();
      translator.calls['one:hello']!.complete('你好');
      translator.calls['two:hello']!.completeError(
        const TranslationFailure('额度不足'),
      );
      await run;
      expect(app.results.first.status, ResultStatus.complete);
      expect(app.results.last.status, ResultStatus.failed);
      expect(app.settings.history.single.translations.values, ['你好']);
    },
  );

  test(
    'cancel stops busy state and late response cannot save history',
    () async {
      app.input = 'hello';
      final run = app.translate();
      await flush();
      app.cancel();
      expect(app.busy, false);
      expect(app.results.single.status, ResultStatus.cancelled);
      translator.calls['test:hello']!.complete('迟到的译文');
      await run;
      expect(app.settings.history, isEmpty);
      expect(app.results.single.text, isEmpty);
    },
  );

  test(
    'repeated requests use cache, changing language bypasses cache',
    () async {
      app.input = 'hello';
      final first = app.translate();
      await flush();
      translator.calls['test:hello']!.complete('你好');
      await first;
      await app.translate();
      expect(app.results.single.cached, true);
      app.settings.target = 'ja';
      final next = app.translate();
      await flush();
      translator.calls['test:hello']!.complete('こんにちは');
      await next;
      expect(app.results.single.cached, false);
      expect(app.results.single.text, 'こんにちは');
    },
  );

  test(
    'disabling history does not retain new source or translations',
    () async {
      app.settings.saveHistory = false;
      app.input = 'private';
      final run = app.translate();
      await flush();
      translator.calls['test:private']!.complete('私密');
      await run;
      expect(app.settings.history, isEmpty);
    },
  );

  test(
    'credentials are separate from JSON and support independent instances',
    () async {
      await app.saveProvider(provider(id: 'one'), 'key-one');
      await app.saveProvider(provider(id: 'two'), 'key-two');
      expect(store.keys, {'one': 'key-one', 'two': 'key-two'});
      final json = jsonEncode(app.settings.toJson());
      expect(json, isNot(contains('key-one')));
      expect(json, isNot(contains('key-two')));
      final restored = AppSettings.fromJson(jsonDecode(json));
      expect(restored.providers.length, 3);
    },
  );

  test(
    'empty input and no enabled services never make network calls',
    () async {
      await app.translate();
      expect(translator.calls, isEmpty);
      app.input = 'hello';
      app.settings.providers = [];
      await app.translate();
      expect(app.page, 1);
      expect(translator.calls, isEmpty);
    },
  );
}
