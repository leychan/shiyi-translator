import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class SelectionCapture {
  const SelectionCapture(this.text, this.label);
  final String text;
  final String label;
}

class SelectionService {
  static const channel = MethodChannel('dev.justtranslator/desktop');

  Future<String?> _command(String executable, List<String> arguments) async {
    Process? process;
    try {
      process = await Process.start(executable, arguments);
      final output = process.stdout.transform(const Utf8Decoder()).join();
      final errors = process.stderr.drain<void>();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill();
          return -1;
        },
      );
      await errors;
      final text = await output;
      return code == 0 && text.trim().isNotEmpty ? text : null;
    } on ProcessException {
      return null;
    }
  }

  Future<SelectionCapture> readSelection() async {
    String? selected;
    if (Platform.isLinux) {
      selected = Platform.environment['XDG_SESSION_TYPE'] == 'wayland'
          ? await _command('wl-paste', ['--primary', '--no-newline'])
          : await _command('xclip', ['-o', '-selection', 'primary']);
    } else if (Platform.isWindows || Platform.isMacOS) {
      try {
        selected = await channel.invokeMethod<String>('readSelection');
      } on PlatformException catch (error) {
        if (error.code == 'accessibility') {
          throw const SelectionException(
            '请在系统设置 → 隐私与安全性 → 辅助功能中允许 Just Translator 取词。',
          );
        }
      }
    }
    if (selected != null && selected.trim().isNotEmpty) {
      return SelectionCapture(selected, '划词取词');
    }
    final clipboard = await readClipboard();
    return SelectionCapture(clipboard.text, '剪贴板 · 未读取到选区');
  }

  Future<SelectionCapture> readClipboard() async {
    String? text;
    if (Platform.isLinux &&
        Platform.environment['XDG_SESSION_TYPE'] == 'wayland') {
      text = await _command('wl-paste', ['--no-newline']);
    }
    text ??= (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.trim().isEmpty) {
      throw const SelectionException('没有读取到文字。请先选中文字；如果目标应用不支持取词，请复制后再翻译。');
    }
    return SelectionCapture(text, '剪贴板');
  }
}

class SelectionException implements Exception {
  const SelectionException(this.message);
  final String message;
}
