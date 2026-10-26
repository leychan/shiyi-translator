import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/translation_service.dart';

import 'support.dart';

void main() {
  late HttpServer server;
  late String endpoint;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = 'http://127.0.0.1:${server.port}';
  });
  tearDown(() async {
    await server.close(force: true);
  });

  TranslationRequest input({
    ProviderKind kind = ProviderKind.compatible,
    bool streaming = true,
    String source = 'auto',
    String target = 'zh',
    String path = '/v1',
  }) => TranslationRequest(
    provider: provider(
      kind: kind,
      endpoint: '$endpoint$path',
      streaming: streaming,
    ),
    text: 'Hello world',
    source: source,
    target: target,
    apiKey: 'secret-test-key',
  );

  test(
    'compatible JSON request sends model, bearer token, and isolated input',
    () async {
      final request = input(streaming: false);
      server.listen((incoming) async {
        expect(incoming.uri.path, '/v1/chat/completions');
        expect(
          incoming.headers.value('authorization'),
          'Bearer secret-test-key',
        );
        final body = jsonDecode(await utf8.decoder.bind(incoming).join());
        expect(body['model'], 'test-model');
        expect(body['stream'], false);
        expect(body['messages'][1], {'role': 'user', 'content': 'Hello world'});
        incoming.response.headers.contentType = ContentType.json;
        incoming.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '你好，世界'},
              },
            ],
          }),
        );
        await incoming.response.close();
      });
      expect(
        await TranslationService().translate(request, CancellationToken()),
        '你好，世界',
      );
    },
  );

  test('stream decodes split UTF-8, comments, usage events, and DONE', () async {
    final partials = <String>[];
    server.listen((incoming) async {
      await incoming.drain<void>();
      incoming.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      final events =
          ': keepalive\n\ndata: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '你好'},
              },
            ],
          })}\n\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '，世界'},
              },
            ],
          })}\n\n'
          'data: {"choices":[],"usage":{"total_tokens":5}}\n\ndata: [DONE]\n\n';
      final bytes = utf8.encode(events);
      for (var offset = 0; offset < bytes.length; offset += 7) {
        incoming.response.add(
          bytes.sublist(offset, (offset + 7).clamp(0, bytes.length)),
        );
        await incoming.response.flush();
      }
      await incoming.response.close();
    });
    expect(
      await TranslationService().translate(
        input(),
        CancellationToken(),
        onPartial: partials.add,
      ),
      '你好，世界',
    );
    expect(partials, ['你好', '你好，世界']);
  });

  test('DeepL maps language variants and omits automatic source', () async {
    server.listen((incoming) async {
      expect(incoming.uri.path, '/v2/translate');
      expect(
        incoming.headers.value('authorization'),
        'DeepL-Auth-Key secret-test-key',
      );
      final body = jsonDecode(await utf8.decoder.bind(incoming).join());
      expect(body['target_lang'], 'EN-US');
      expect(body.containsKey('source_lang'), false);
      expect(body['text'], ['Hello world']);
      incoming.response.write('{"translations":[{"text":"Hello"}]}');
      await incoming.response.close();
    });
    expect(
      await TranslationService().translate(
        input(kind: ProviderKind.deepl, target: 'en', path: ''),
        CancellationToken(),
      ),
      'Hello',
    );
  });

  test('LibreTranslate uses its own request and response format', () async {
    server.listen((incoming) async {
      expect(incoming.uri.path, '/translate');
      final body = jsonDecode(await utf8.decoder.bind(incoming).join());
      expect(body['api_key'], 'secret-test-key');
      expect(body['q'], 'Hello world');
      expect(body['target'], 'zh');
      incoming.response.write('{"translatedText":"你好，世界"}');
      await incoming.response.close();
    });
    expect(
      await TranslationService().translate(
        input(kind: ProviderKind.libreTranslate, path: ''),
        CancellationToken(),
      ),
      '你好，世界',
    );
  });

  test(
    'authentication errors do not expose server response or credentials',
    () async {
      server.listen((incoming) async {
        incoming.response.statusCode = 401;
        incoming.response.write('secret-test-key');
        await incoming.response.close();
      });
      await expectLater(
        TranslationService().translate(input(), CancellationToken()),
        throwsA(
          isA<TranslationFailure>().having(
            (e) => e.message,
            'safe error',
            allOf(contains('认证失败'), isNot(contains('secret-test-key'))),
          ),
        ),
      );
    },
  );

  test('timeout aborts a response that never finishes', () async {
    server.listen((incoming) async {
      await incoming.drain<void>();
    });
    await expectLater(
      TranslationService(timeout: const Duration(milliseconds: 150))
          .translate(input(), CancellationToken()),
      throwsA(
        isA<TranslationFailure>().having(
          (e) => e.message,
          'timeout',
          contains('超时'),
        ),
      ),
    );
  });

  test('cancellation interrupts a streaming request', () async {
    final started = Completer<void>();
    server.listen((incoming) async {
      await incoming.drain<void>();
      incoming.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      incoming.response.bufferOutput = false;
      incoming.response.write(
        'data: {"choices":[{"delta":{"content":"一"}}]}\n\n',
      );
      await incoming.response.flush();
    });
    final token = CancellationToken();
    final translation = TranslationService().translate(
      input(),
      token,
      onPartial: (_) {
        if (!started.isCompleted) started.complete();
      },
    );
    final assertion = expectLater(
      translation,
      throwsA(isA<TranslationCancelled>()),
    );
    await started.future.timeout(const Duration(seconds: 3));
    token.cancel();
    await assertion;
  });

  test('stream errors and malformed output are reported', () async {
    server.listen((incoming) async {
      incoming.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      incoming.response.write(
        'data: {"error":{"message":"private server details"}}\n\n',
      );
      await incoming.response.close();
    });
    await expectLater(
      TranslationService().translate(input(), CancellationToken()),
      throwsA(isA<TranslationFailure>()),
    );
  });

  test(
    'endpoint normalization accepts full endpoint without duplicating paths',
    () {
      expect(
        input(path: '/v1/chat/completions/').uri.path,
        '/v1/chat/completions',
      );
      expect(
        input(kind: ProviderKind.deepl, path: '/v2/translate').uri.path,
        '/v2/translate',
      );
      expect(
        input(kind: ProviderKind.libreTranslate, path: '/api').uri.path,
        '/api/translate',
      );
    },
  );
}
