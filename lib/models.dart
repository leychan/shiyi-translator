enum ProviderKind { compatible, deepl, libreTranslate, baidu }

extension ProviderKindInfo on ProviderKind {
  String get label => switch (this) {
    ProviderKind.compatible => 'Chat Completions 兼容接口',
    ProviderKind.deepl => 'DeepL',
    ProviderKind.libreTranslate => 'LibreTranslate',
    ProviderKind.baidu => '百度翻译',
  };

  String get defaultEndpoint => switch (this) {
    ProviderKind.compatible => 'https://api.openai.com/v1',
    ProviderKind.deepl => 'https://api-free.deepl.com',
    ProviderKind.libreTranslate => 'http://localhost:5000',
    ProviderKind.baidu => 'https://fanyi-api.baidu.com',
  };
}

const languages = <String, String>{
  'auto': '自动检测',
  'zh': '简体中文',
  'en': '英语',
  'ja': '日语',
  'ko': '韩语',
  'fr': '法语',
  'de': '德语',
  'es': '西班牙语',
  'ru': '俄语',
  'pt': '葡萄牙语',
};

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.endpoint,
    this.model = '',
    this.enabled = true,
    this.streaming = true,
    this.hasApiKey = false,
    this.appId = '',
  });

  final String id;
  final String name;
  final ProviderKind kind;
  final String endpoint;
  final String model;
  final bool enabled;
  final bool streaming;
  final bool hasApiKey;
  final String appId;

  ProviderConfig withEnabled(bool value) => ProviderConfig(
    id: id,
    name: name,
    kind: kind,
    endpoint: endpoint,
    model: model,
    enabled: value,
    streaming: streaming,
    hasApiKey: hasApiKey,
    appId: appId,
  );

  ProviderConfig withCredential(bool value) => ProviderConfig(
    id: id,
    name: name,
    kind: kind,
    endpoint: endpoint,
    model: model,
    enabled: enabled,
    streaming: streaming,
    hasApiKey: value,
    appId: appId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'endpoint': endpoint,
    'model': model,
    'enabled': enabled,
    'streaming': streaming,
    'hasApiKey': hasApiKey,
    'appId': appId,
  };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: ProviderKind.values.byName(json['kind'] as String),
    endpoint: json['endpoint'] as String,
    model: json['model'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    streaming: json['streaming'] as bool? ?? true,
    hasApiKey: json['hasApiKey'] as bool? ?? true,
    appId: json['appId'] as String? ?? '',
  );
}

enum ResultStatus { loading, complete, failed, cancelled }

class TranslationResult {
  TranslationResult({required this.provider});
  final ProviderConfig provider;
  String text = '';
  String? error;
  ResultStatus status = ResultStatus.loading;
  bool cached = false;
  Duration elapsed = Duration.zero;

  Map<String, dynamic> toJson() => {
    'provider': provider.toJson(),
    'text': text,
    'error': error,
    'status': status.name,
    'cached': cached,
    'elapsedMs': elapsed.inMilliseconds,
  };

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    final result = TranslationResult(
      provider: ProviderConfig.fromJson(
        Map<String, dynamic>.from(json['provider'] as Map),
      ),
    );
    result.text = json['text'] as String;
    result.error = json['error'] as String?;
    result.status = ResultStatus.values.byName(json['status'] as String);
    result.cached = json['cached'] as bool? ?? false;
    result.elapsed = Duration(milliseconds: json['elapsedMs'] as int? ?? 0);
    return result;
  }
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.text,
    required this.source,
    required this.target,
    required this.createdAt,
    required this.translations,
  });
  final String id;
  final String text;
  final String source;
  final String target;
  final DateTime createdAt;
  final Map<String, String> translations;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'source': source,
    'target': target,
    'createdAt': createdAt.toIso8601String(),
    'translations': translations,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    text: json['text'] as String,
    source: json['source'] as String,
    target: json['target'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    translations: Map<String, String>.from(json['translations'] as Map),
  );
}

class AppSettings {
  AppSettings({
    this.providers = const [],
    this.history = const [],
    this.source = 'auto',
    this.target = 'zh',
    this.darkMode = false,
    this.saveHistory = true,
    this.closeToTray = true,
  });
  List<ProviderConfig> providers;
  List<HistoryEntry> history;
  String source;
  String target;
  bool darkMode;
  bool saveHistory;
  bool closeToTray;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'providers': providers.map((p) => p.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
    'source': source,
    'target': target,
    'darkMode': darkMode,
    'saveHistory': saveHistory,
    'closeToTray': closeToTray,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    providers: (json['providers'] as List? ?? [])
        .map(
          (p) => ProviderConfig.fromJson(Map<String, dynamic>.from(p as Map)),
        )
        .toList(),
    history: (json['history'] as List? ?? [])
        .take(100)
        .map((h) => HistoryEntry.fromJson(Map<String, dynamic>.from(h as Map)))
        .toList(),
    source: languages.containsKey(json['source'])
        ? json['source'] as String
        : 'auto',
    target: json['target'] != 'auto' && languages.containsKey(json['target'])
        ? json['target'] as String
        : 'zh',
    darkMode: json['darkMode'] as bool? ?? false,
    saveHistory: json['saveHistory'] as bool? ?? true,
    closeToTray: json['closeToTray'] as bool? ?? true,
  );
}
