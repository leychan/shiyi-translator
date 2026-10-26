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
