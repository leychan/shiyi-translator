import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/services/pronunciation_service.dart';

void main() {
  test('英文识别与单词范围', () {
    expect(PronunciationService.isEnglish('en', 'Hello world!'), isTrue);
    expect(PronunciationService.isEnglish('auto', 'Hello world!'), isTrue);
    expect(PronunciationService.isEnglish('auto', '你好 Hello'), isFalse);
    expect(PronunciationService.isEnglish('fr', 'bonjour'), isFalse);
    expect(PronunciationService.word("don't"), "don't");
    expect(PronunciationService.word('Hello world!'), isNull);
  });

  test('解析多个音标、去重并缓存', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '[{"phonetic":"/hello/","phonetics":[{"text":"/hello/"},{"text":"/other/"}]}]',
      );
      await request.response.close();
    });
    final service = PronunciationService();
    final uri = Uri.parse('http://127.0.0.1:${server.port}/hello');
    expect(
      await service.phonetic('hello', endpoint: uri),
      '/hello/  ·  /other/',
    );
    expect(
      await service.phonetic('Hello', endpoint: uri),
      '/hello/  ·  /other/',
    );
    expect(requests, 1);
  });
}
