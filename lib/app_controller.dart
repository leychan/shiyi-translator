import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/storage_service.dart';
import 'services/translation_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.settings,
    required this.store,
    TranslationService? translator,
  }) : translator = translator ?? TranslationService();
  final AppSettings settings;
  final SettingsStore store;
  final TranslationService translator;
  final Map<String, String> _cache = {};
  List<TranslationResult> results = [];
  String input = '';
  String captureLabel = '手动输入';
  String? notice;
  bool busy = false;
  int page = 0;
  int _generation = 0;
  CancellationToken? _token;

  List<ProviderConfig> get enabledProviders =>
      settings.providers.where((p) => p.enabled).toList();
  void goTo(int value) {
    page = value;
    notifyListeners();
  }

  void message(String value) {
    notice = value;
    notifyListeners();
  }

  void clearMessage() {
    notice = null;
    notifyListeners();
  }

  void setInput(String value, {String? from}) {
    input = value;
    if (from != null) captureLabel = from;
    notifyListeners();
  }

  Future<void> persist() async {
    try {
      await store.save(settings);
    } catch (_) {
      message('无法保存本地配置，请检查目录写入权限。');
    }
  }

  Future<void> saveProvider(ProviderConfig config, String apiKey) async {
    // Never silently fall back to storing credentials in plaintext.
    final existing = settings.providers.where((p) => p.id == config.id);
    if (apiKey.isNotEmpty ||
        (existing.isNotEmpty && existing.first.hasApiKey)) {
      await store.writeKey(config.id, apiKey);
    }
    config = config.withCredential(apiKey.isNotEmpty);
    final next = settings.providers.where((p) => p.id != config.id).toList()
      ..add(config);
    final previous = settings.providers;
    settings.providers = next;
    try {
      await store.save(settings);
    } catch (_) {
      settings.providers = previous;
      rethrow;
    }
    _cache.clear();
    notifyListeners();
  }

  Future<void> removeProvider(String id) async {
    final previous = settings.providers;
    settings.providers = previous.where((p) => p.id != id).toList();
    try {
      await store.save(settings);
    } catch (_) {
      settings.providers = previous;
      rethrow;
    }
    if (previous.any((p) => p.id == id && p.hasApiKey)) {
      await store.deleteKey(id);
    }
    _cache.clear();
    notifyListeners();
  }

  Future<void> toggleProvider(ProviderConfig config, bool enabled) async {
    settings.providers = settings.providers
        .map((p) => p.id == config.id ? p.withEnabled(enabled) : p)
        .toList();
    notifyListeners();
    await persist();
  }

  void cancel({bool notify = true}) {
    _generation++;
    _token?.cancel();
    for (final result in results) {
      if (result.status == ResultStatus.loading) {
        result.status = ResultStatus.cancelled;
      }
    }
    busy = false;
    if (notify) notifyListeners();
  }

  Future<void> translate() async {
    final text = input.trim();
    if (text.isEmpty) {
      message('先输入或选取一段需要翻译的文字。');
      return;
    }
    if (text.length > 15000) {
      message('单次最多翻译 15,000 个字符，请分段翻译。');
      return;
    }
    final providers = enabledProviders;
    if (providers.isEmpty) {
      message('请先添加并启用一个翻译服务。');
      goTo(1);
      return;
    }
    cancel(notify: false);
    final generation = _generation;
    final token = CancellationToken();
    _token = token;
    final source = settings.source;
    final target = settings.target;
    final runResults = providers
        .map((p) => TranslationResult(provider: p))
        .toList();
    results = runResults;
    busy = true;
    page = 0;
    notice = null;
    notifyListeners();
    await Future.wait(
      runResults.map((result) async {
        final stopwatch = Stopwatch()..start();
        final config = result.provider;
        final cacheKey = '${config.toJson()}|$source|$target|$text';
        try {
          if (_cache.containsKey(cacheKey)) {
            result.text = _cache[cacheKey]!;
            result.cached = true;
          } else {
            String apiKey;
            try {
              apiKey = config.hasApiKey ? await store.readKey(config.id) : '';
            } catch (_) {
              throw const TranslationFailure('无法读取密钥，请解锁系统钥匙串后重试。');
            }
            token.check();
            final translated = await translator.translate(
              TranslationRequest(
                provider: config,
                text: text,
                source: source,
                target: target,
                apiKey: apiKey,
              ),
              token,
              onPartial: (partial) {
                if (generation != _generation) return;
                result.text = partial;
                notifyListeners();
              },
            );
            if (generation != _generation) return;
            result.text = translated;
            if (_cache.length >= 100) _cache.remove(_cache.keys.first);
            _cache[cacheKey] = result.text;
          }
          result.status = ResultStatus.complete;
        } on TranslationCancelled {
          result.status = ResultStatus.cancelled;
        } on TranslationFailure catch (error) {
          if (generation != _generation) return;
          result.error = error.message;
          result.status = ResultStatus.failed;
        } catch (_) {
          if (generation != _generation) return;
          result.error = '翻译失败，请检查服务配置后重试。';
          result.status = ResultStatus.failed;
        } finally {
          result.elapsed = stopwatch.elapsed;
          if (generation == _generation) notifyListeners();
        }
      }),
    );
    if (generation != _generation) return;
    busy = false;
    final successful = runResults.where(
      (r) => r.status == ResultStatus.complete,
    );
    if (settings.saveHistory && successful.isNotEmpty) {
      final now = DateTime.now();
      settings.history = [
        HistoryEntry(
          id: now.microsecondsSinceEpoch.toString(),
          text: text,
          source: source,
          target: target,
          createdAt: now,
          translations: {
            for (final r in successful)
              '${r.provider.name} · ${r.provider.id}': r.text,
          },
        ),
        ...settings.history,
      ].take(100).toList();
      await persist();
    }
    notifyListeners();
  }

  void restoreHistory(HistoryEntry entry) {
    cancel(notify: false);
    input = entry.text;
    settings.source = entry.source;
    settings.target = entry.target;
    captureLabel = '历史记录';
    results = entry.translations.entries.map((translation) {
      final result = TranslationResult(
        provider: ProviderConfig(
          id: 'history',
          name: translation.key.split(' · ').first,
          kind: ProviderKind.compatible,
          endpoint: '',
        ),
      );
      result.text = translation.value;
      result.status = ResultStatus.complete;
      return result;
    }).toList();
    page = 0;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    settings.history = [];
    _cache.clear();
    notifyListeners();
    await persist();
  }

  void settingsChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    cancel(notify: false);
    super.dispose();
  }
}
