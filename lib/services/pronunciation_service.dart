import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PronunciationService {
  static final shared = PronunciationService();
  final Map<String, String> _cache = {};

  static bool isEnglish(String language, String text) =>
      text.trim().isNotEmpty &&
      (language == 'en' ||
          (language == 'auto' &&
              RegExp(r'[a-zA-Z]').hasMatch(text) &&
              !RegExp(r'[^\x00-\x7F\u2000-\u206F]').hasMatch(text)));

  static String? word(String text) {
    final value = text.trim().toLowerCase();
    return RegExp(r"^[a-z]+(?:['-][a-z]+)*$").hasMatch(value) ? value : null;
  }

  Future<String> phonetic(String text, {Uri? endpoint}) async {
    final value = word(text);
    if (value == null) throw Exception('音标查询仅支持英文单词。');
    if (_cache.containsKey(value)) return _cache[value]!;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri =
          endpoint ??
          Uri.https('api.dictionaryapi.dev', '/api/v2/entries/en/$value');
      final result = await (() async {
        final response = await (await client.getUrl(uri)).close();
        if (response.statusCode != 200) throw Exception('未找到该单词的音标。');
        final entries =
            jsonDecode(await utf8.decoder.bind(response).join()) as List;
        final values = <String>{};
        for (final entry in entries) {
          final phonetic = entry['phonetic'];
          if (phonetic is String && phonetic.isNotEmpty) values.add(phonetic);
          for (final item in (entry['phonetics'] as List? ?? [])) {
            final text = item['text'];
            if (text is String && text.isNotEmpty) values.add(text);
          }
        }
        if (values.isEmpty) throw Exception('该单词暂无音标。');
        return values.join('  ·  ');
      })().timeout(const Duration(seconds: 10));
      if (_cache.length >= 200) _cache.remove(_cache.keys.first);
      return _cache[value] = result;
    } on TimeoutException {
      throw Exception('音标查询超时，请重试。');
    } on SocketException {
      throw Exception('无法连接音标服务，请检查网络。');
    } finally {
      client.close(force: true);
    }
  }

  Future<Process> speak(String text) async {
    if (Platform.isMacOS) {
      return Process.start('say', ['-v', 'Samantha', '--', text]);
    }
    if (Platform.isWindows) {
      final process = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::NotSet, [System.Speech.Synthesis.VoiceAge]::NotSet, 0, [System.Globalization.CultureInfo]::GetCultureInfo("en-US")); $s.Speak([Console]::In.ReadToEnd())',
      ]);
      process.stdin.write(text);
      await process.stdin.close();
      return process;
    }
    if (Platform.isLinux) {
      for (final executable in ['espeak-ng', 'espeak']) {
        try {
          final process = await Process.start(executable, [
            '-v',
            'en-us',
            '--stdin',
          ]);
          process.stdin.write(text);
          await process.stdin.close();
          return process;
        } on ProcessException {
          continue;
        }
      }
      throw Exception('请先安装 espeak-ng 并确认音频输出可用。');
    }
    throw Exception('当前系统暂不支持朗读。');
  }
}
