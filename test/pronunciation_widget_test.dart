import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/widgets/pronunciation.dart';

void main() {
  testWidgets('英文单词显示朗读与音标，句子仅显示朗读', (tester) async {
    Future<void> show(String text, String language) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Pronunciation(text: text, language: language),
        ),
      ),
    );
    await show('hello', 'en');
    expect(find.byTooltip('朗读英文'), findsOneWidget);
    expect(find.text('查询音标（联网）'), findsOneWidget);
    await show('Hello world!', 'en');
    expect(find.byTooltip('朗读英文'), findsOneWidget);
    expect(find.text('查询音标（联网）'), findsNothing);
    await show('你好', 'zh');
    expect(find.byTooltip('朗读英文'), findsNothing);
  });
}
