import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/app_controller.dart';
import 'package:just_translator/models.dart';
import 'package:just_translator/popup_placement.dart';
import 'package:just_translator/services/instance_service.dart';
import 'package:just_translator/services/popup_service.dart';
import 'package:just_translator/services/translation_service.dart';

import 'support.dart';

class FakeTranslator extends TranslationService {
  @override
  Future<String> translate(
    TranslationRequest input,
    CancellationToken token, {
    void Function(String)? onPartial,
  }) async => '译文：${input.text}';
}

void main() {
  test('popup state is isolated from main draft while credentials and history stay in owner', () async {
    final store = MemoryStore();
    store.keys['test'] = 'private-test-key';
    final main = AppController(
      settings: AppSettings(providers: [provider().withCredential(true)]),
      store: store,
    );
    final popup = PopupService(
      main,
      launchWindow: () async {},
      translator: FakeTranslator(),
    );
    try {
      main.input = '主窗口草稿';
      main.page = 2;
      await popup.present(text: '选中文字', label: '划词取词');
      await Future<void>.delayed(Duration.zero);
      expect(main.input, '主窗口草稿');
      expect(main.page, 2);
      expect(popup.controller.results.single.text, '译文：选中文字');
      expect(main.settings.history.single.text, '选中文字');
      final snapshot = popup.snapshot();
      expect(jsonEncode(snapshot), isNot(contains('private-test-key')));
      expect((snapshot['settings'] as Map).containsKey('history'), false);
      await popup.handle('/popup/configure', {'source': 'en', 'target': 'ja'});
      expect(main.settings.target, 'ja');
      expect(store.saves, greaterThan(0));
      await expectLater(
        popup.handle('/popup/configure', {'source': 'en', 'target': 'auto'}),
        throwsFormatException,
      );
    } finally {
      await popup.dispose();
      main.dispose();
    }
  });

  test('remote popup synchronizes over authenticated IPC and preserves local drafts', () async {
    final directory = await Directory.systemTemp.createTemp(
      'just-translator-popup-test-',
    );
    final instance = InstanceService(directory: directory);
    final main = AppController(
      settings: AppSettings(providers: [provider()]),
      store: MemoryStore(),
    );
    final popup = PopupService(
      main,
      launchWindow: () async {},
      translator: FakeTranslator(),
    );
    RemotePopupController? remote;
    try {
      await instance.startOrForward('show');
      instance.onRpc = popup.handle;
      const anchor = PopupAnchor(
        cursor: Offset(-1200, 300),
        workArea: Rect.fromLTWH(-1920, 0, 1920, 1040),
      );
      await popup.present(text: 'first', translate: false, anchor: anchor);
      final session = jsonDecode(
        await File('${directory.path}/session.json').readAsString(),
      );
      remote = RemotePopupController(
        PopupConnection(
          port: session['port'] as int,
          token: session['token'] as String,
        ),
      );
      await remote.start();
      expect(remote.input, 'first');
      expect(remote.anchor!.cursor, anchor.cursor);
      remote.setInput('正在编辑的草稿');
      main.settings.darkMode = true;
      main.settingsChanged();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(remote.input, '正在编辑的草稿');
      remote.setInput('second');
      await remote.translate();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(remote.results.single.text, '译文：second');
      const nextAnchor = PopupAnchor(
        cursor: Offset(1800, 900),
        workArea: Rect.fromLTWH(0, 0, 1920, 1040),
      );
      await popup.present(
        text: '新的划词',
        label: '划词取词',
        translate: false,
        anchor: nextAnchor,
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(remote.input, '新的划词');
      expect(remote.anchor!.cursor, nextAnchor.cursor);
      expect(main.input, isEmpty);
    } finally {
      remote?.dispose();
      await popup.dispose();
      main.dispose();
      await instance.close();
      await directory.delete(recursive: true);
    }
  });
}
