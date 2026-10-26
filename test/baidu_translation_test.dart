import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/services/translation_service.dart';

void main() {
  test(
    'Baidu official signature fixture uses raw UTF-8 query before encoding',
    () {
      final request = TranslationRequest(
        provider: const ProviderConfig(
          id: 'baidu',
          name: '百度翻译',
          kind: ProviderKind.baidu,
          endpoint: 'https://fanyi-api.baidu.com',
          appId: '2015063000000001',
        ),
        text: 'apple',
        source: 'auto',
        target: 'zh',
        apiKey: '12345678',
        salt: '1435660288',
      );
      expect(request.body['sign'], 'f89f9594663708c1605f3d736d01d2d4');
      expect(request.uri.path, '/api/trans/vip/translate');
    },
  );

  test('Baidu sends signed form data, maps languages, and joins multiple paragraphs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      server.listen((request) async {
        expect(request.uri.path, '/api/trans/vip/translate');
        expect(request.uri.hasQuery, false);
        expect(
          request.headers.contentType!.mimeType,
          'application/x-www-form-urlencoded',
        );
        expect(request.headers.value('authorization'), isNull);
        final raw = await utf8.decoder.bind(request).join();
        expect(raw, isNot(contains('test-secret')));
        final form = Uri.splitQueryString(raw);
        expect(form['q'], '你好 & a+b\n第二行');
        expect(form['from'], 'jp');
        expect(form['to'], 'kor');
        expect(form['appid'], 'test-app');
        expect(form['sign'], '19c0950cc1c1cecdb30c6ca05d1c94d2');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'from': 'jp',
            'to': 'kor',
            'trans_result': [
              {'src': '你好 & a+b', 'dst': '第一段'},
              {'src': '第二行', 'dst': '第二段'},
            ],
          }),
        );
        await request.response.close();
      });
      final input = TranslationRequest(
        provider: ProviderConfig(
          id: 'baidu',
          name: '百度翻译',
          kind: ProviderKind.baidu,
          endpoint: 'http://127.0.0.1:${server.port}',
          appId: 'test-app',
        ),
        text: '你好 & a+b\n第二行',
        source: 'ja',
        target: 'ko',
        apiKey: 'test-secret',
        salt: 'fixed-salt',
      );
      expect(
        await TranslationService().translate(input, CancellationToken()),
        '第一段\n第二段',
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('Baidu reports business errors returned with HTTP 200 without leaking server details', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"error_code":"54001","error_msg":"test-secret private query"}',
        );
        await request.response.close();
      });
      final input = TranslationRequest(
        provider: ProviderConfig(
          id: 'baidu',
          name: '百度翻译',
          kind: ProviderKind.baidu,
          endpoint: 'http://127.0.0.1:${server.port}',
          appId: 'test-app',
        ),
        text: 'test',
        source: 'auto',
        target: 'zh',
        apiKey: 'test-secret',
      );
      await expectLater(
        TranslationService().translate(input, CancellationToken()),
        throwsA(
          isA<TranslationFailure>().having(
            (e) => e.message,
            'safe error',
            allOf(
              contains('签名失败'),
              isNot(contains('test-secret')),
              isNot(contains('private query')),
            ),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'Baidu validates credentials and UTF-8 byte limit before sending a request',
    () async {
      const config = ProviderConfig(
        id: 'baidu',
        name: '百度翻译',
        kind: ProviderKind.baidu,
        endpoint: 'https://fanyi-api.baidu.com',
        appId: 'test-app',
      );
      await expectLater(
        TranslationService().translate(
          TranslationRequest(
            provider: config,
            text: 'Hello',
            source: 'auto',
            target: 'zh',
            apiKey: '',
          ),
          CancellationToken(),
        ),
        throwsA(
          isA<TranslationFailure>().having(
            (e) => e.message,
            'credentials',
            contains('APP ID'),
          ),
        ),
      );
      await expectLater(
        TranslationService().translate(
          TranslationRequest(
            provider: config,
            text: List.filled(2001, '中').join(),
            source: 'auto',
            target: 'en',
            apiKey: 'test-key',
          ),
          CancellationToken(),
        ),
        throwsA(
          isA<TranslationFailure>().having(
            (e) => e.message,
            'bytes',
            contains('6000 字节'),
          ),
        ),
      );
      final restored = ProviderConfig.fromJson(
        config.withCredential(true).withEnabled(false).toJson(),
      );
      expect(restored.appId, 'test-app');
      expect(restored.hasApiKey, true);
    },
  );
}
