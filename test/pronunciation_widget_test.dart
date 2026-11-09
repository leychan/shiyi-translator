import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/services/pronunciation_service.dart';
import 'package:just_translator/widgets/pronunciation.dart';

class FakePronunciationService extends PronunciationService {
  final requests = <String>[];
  final responses = <Completer<String>>[];

  @override
  Future<String> phonetic(String text, {Uri? endpoint}) {
    requests.add(text);
    final response = Completer<String>();
    responses.add(response);
    return response.future;
  }
}

void main() {
  testWidgets('自动查询音标，忽略旧结果，句子和中文不查询', (tester) async {
    final service = FakePronunciationService();
    Future<void> show(String text, String language) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Pronunciation(text: text, language: language, service: service),
        ),
      ),
    );
    await show('hello', 'en');
    expect(find.byTooltip('朗读英文'), findsOneWidget);
    expect(find.text('音标查询中…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 599));
    expect(service.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.requests, ['hello']);
    await show('world', 'en');
    service.responses.first.complete('/hello/');
    await tester.pump();
    expect(find.text('/hello/'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    service.responses.last.complete('/world/');
    await tester.pumpAndSettle();
    expect(find.text('/world/'), findsOneWidget);
    expect(tester.getTopLeft(find.byTooltip('朗读英文')).dx, lessThan(10));
    await show('Hello world!', 'en');
    expect(find.byTooltip('朗读英文'), findsOneWidget);
    expect(find.text('/world/'), findsNothing);
    await show('你好', 'zh');
    expect(find.byTooltip('朗读英文'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(service.requests, ['hello', 'world']);
  });

  testWidgets('输入防抖、查询失败后可重试', (tester) async {
    final service = FakePronunciationService();
    Future<void> show(String text) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Pronunciation(text: text, language: 'en', service: service),
        ),
      ),
    );
    await show('h');
    await tester.pump(const Duration(milliseconds: 300));
    await show('hello');
    await tester.pump(const Duration(milliseconds: 600));
    expect(service.requests, ['hello']);
    service.responses.first.completeError(Exception('暂不可用'));
    await tester.pumpAndSettle();
    expect(find.text('音标暂不可用，重试'), findsOneWidget);
    await tester.tap(find.text('音标暂不可用，重试'));
    await tester.pump();
    service.responses.last.complete('/hello/');
    await tester.pumpAndSettle();
    expect(find.text('/hello/'), findsOneWidget);
  });
}
