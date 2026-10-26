import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../app_controller.dart';
import '../models.dart';
import '../popup_placement.dart';
import 'pointer_placement_service.dart';
import 'storage_service.dart';
import 'translation_service.dart';

/// The application process owns translation, credentials, and persistence.
/// The popup is a separate native window and receives only presentation state.
class PopupService {
  PopupService(
    this.main, {
    this.executable,
    this.environment,
    this.launchWindow,
    TranslationService? translator,
    PointerPlacementService? placement,
  }) : placement = placement ?? PointerPlacementService() {
    controller = AppController(
      settings: main.settings,
      store: main.store,
      translator: translator,
    );
    controller.addListener(_changed);
    main.addListener(_mainChanged);
  }
  final AppController main;
  final PointerPlacementService placement;
  PopupAnchor? _anchor;
  final String? executable;
  final Map<String, String>? environment;
  final Future<void> Function()? launchWindow;
  late final AppController controller;
  Process? _process;
  int _revision = 0;
  int _presentation = 0;
  bool _disposed = false;
  Future<void>? _launching;
  Future<void>? _closing;
  bool connected = false;
  bool get isRunning => _process != null;
  int? get processId => _process?.pid;
  Future<void> Function()? openSettings;

  void _changed() {
    _revision++;
    main.settingsChanged();
  }

  void _mainChanged() {
    _revision++;
  }

  Map<String, dynamic> snapshot() => {
    'revision': _revision,
    'presentation': _presentation,
    'anchor': _anchor?.toJson(),
    'input': controller.input,
    'captureLabel': controller.captureLabel,
    'notice': controller.notice,
    'busy': controller.busy,
    'settings': {
      'providers': main.settings.providers.map((p) => p.toJson()).toList(),
      'source': main.settings.source,
      'target': main.settings.target,
      'darkMode': main.settings.darkMode,
    },
    'results': controller.results.map((r) => r.toJson()).toList(),
  };

  Future<void> present({
    String? text,
    String? label,
    bool translate = true,
    PopupAnchor? anchor,
  }) async {
    if (_disposed) return;
    _anchor = anchor;
    if (text != null) {
      controller.cancel(notify: false);
      controller.results = [];
      controller.notice = null;
      controller.setInput(text, from: label ?? '手动输入');
    }
    _presentation++;
    _revision++;
    await _ensureWindow();
    if (translate && controller.input.trim().isNotEmpty) {
      unawaited(controller.translate());
    }
  }

  Future<void> _ensureWindow() async {
    if (_process != null || _disposed) return;
    if (_launching != null) {
      await _launching;
      return;
    }
    _launching = _launch();
    try {
      await _launching;
    } finally {
      _launching = null;
    }
  }

  Future<void> _launch() async {
    if (launchWindow != null) {
      await launchWindow!();
      return;
    }
    final process = await Process.start(
      executable ?? Platform.resolvedExecutable,
      ['--popup'],
      environment: environment,
    );
    if (_disposed) {
      process.kill();
      return;
    }
    _process = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) {
          _process = null;
          connected = false;
        }
      }),
    );
  }

  Future<Map<String, dynamic>> handle(
    String path,
    Map<String, dynamic> data,
  ) async {
    switch (path) {
      case '/popup/state':
        connected = true;
        break;
      case '/popup/prepare-position':
        final expected = data['presentation'];
        final positioned =
            expected == _presentation &&
            _process != null &&
            _anchor != null &&
            await placement.prepare(_process!.pid, _anchor!);
        return {...snapshot(), 'positionedByCompositor': positioned};
      case '/popup/translate':
        final text = data['text'] as String;
        if (text.length > 15000) {
          controller.message('单次最多翻译 15,000 个字符，请分段翻译。');
          break;
        }
        _setLanguages(data);
        controller.setInput(text, from: '手动输入');
        unawaited(controller.translate());
      case '/popup/cancel':
        controller.cancel();
      case '/popup/configure':
        _setLanguages(data);
        await controller.persist();
        _changed();
      case '/popup/clear-notice':
        controller.clearMessage();
      case '/popup/open-settings':
        await openSettings?.call();
      default:
        throw const FormatException('Unknown popup action');
    }
    return snapshot();
  }

  void _setLanguages(Map<String, dynamic> data) {
    final source = data['source'];
    final target = data['target'];
    if (!languages.containsKey(source) ||
        !languages.containsKey(target) ||
        target == 'auto') {
      throw const FormatException('Invalid language');
    }
    main.settings.source = source as String;
    main.settings.target = target as String;
  }

  Future<void> dispose() => _closing ??= _close();

  Future<void> _close() async {
    _disposed = true;
    main.removeListener(_mainChanged);
    controller.removeListener(_changed);
    controller.dispose();
    await placement.dispose();
    _process?.kill();
    if (_process != null) await _process!.exitCode;
    _process = null;
  }
}

class PopupConnection {
  PopupConnection({required this.port, required this.token});
  final int port;
  final String token;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

  static Future<PopupConnection> connect() async {
    final directory = await getApplicationSupportDirectory();
    final json = jsonDecode(
      await File('${directory.path}/session.json').readAsString(),
    ) as Map<String, dynamic>;
    return PopupConnection(
      port: json['port'] as int,
      token: json['token'] as String,
    );
  }

  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic> data = const {},
  ]) async {
    final request = await _client.postUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Popup connection unavailable');
    }
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  }

  void close() => _client.close(force: true);
}

class RemotePopupController extends AppController {
  RemotePopupController(this.connection)
    : super(settings: AppSettings(), store: StorageService());
  final PopupConnection connection;
  Timer? _poll;
  bool _polling = false;
  bool _draft = false;
  bool _disposed = false;
  int _pendingSettings = 0;
  int _revision = -1;
  int _presentation = -1;
  PopupAnchor? anchor;
  int _failures = 0;
  Future<void> Function()? onPresent;
  Future<void> Function()? onDisconnected;

  Future<void> start() async {
    _apply(await connection.request('/popup/state'));
    _poll = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      _apply(await connection.request('/popup/state'));
      _failures = 0;
    } catch (_) {
      if (++_failures >= 3) {
        _poll?.cancel();
        await onDisconnected?.call();
      }
    } finally {
      _polling = false;
    }
  }

  void _apply(Map<String, dynamic> data) {
    if (_disposed || (data['revision'] as int) <= _revision) return;
    _revision = data['revision'] as int;
    final present = data['presentation'] as int;
    final newCapture = present != _presentation;
    _presentation = present;
    anchor = data['anchor'] == null
        ? null
        : PopupAnchor.fromJson(
            Map<String, dynamic>.from(data['anchor'] as Map),
          );
    if (newCapture) _draft = false;
    if (!_draft) input = data['input'] as String;
    final latest = AppSettings.fromJson(
      Map<String, dynamic>.from(data['settings'] as Map),
    );
    settings.providers = latest.providers;
    settings.darkMode = latest.darkMode;
    if (_pendingSettings == 0 || newCapture) {
      settings.source = latest.source;
      settings.target = latest.target;
    }
    captureLabel = data['captureLabel'] as String;
    notice = data['notice'] as String?;
    busy = data['busy'] as bool;
    results = (data['results'] as List)
        .map(
          (r) =>
              TranslationResult.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
    notifyListeners();
    if (newCapture) unawaited(onPresent?.call());
  }

  @override
  void setInput(String value, {String? from}) {
    _draft = true;
    super.setInput(value, from: from);
  }

  @override
  Future<void> translate() async {
    final submitted = input;
    try {
      final data = await connection.request('/popup/translate', {
        'text': submitted,
        'source': settings.source,
        'target': settings.target,
      });
      if (input == submitted) _draft = false;
      _apply(data);
    } catch (_) {
      if (!_disposed) message('连接翻译服务失败，请重新打开弹窗。');
    }
  }

  @override
  void cancel({bool notify = true}) {
    if (_disposed) return;
    unawaited(_command('/popup/cancel'));
  }

  @override
  void clearMessage() {
    super.clearMessage();
    unawaited(_command('/popup/clear-notice'));
  }

  @override
  Future<void> persist() async {
    _pendingSettings++;
    try {
      _apply(
        await connection.request('/popup/configure', {
          'source': settings.source,
          'target': settings.target,
        }),
      );
    } catch (_) {
      if (!_disposed) message('无法保存语言设置，请重试。');
    } finally {
      _pendingSettings--;
    }
  }

  Future<void> openServiceSettings() => _command('/popup/open-settings');
  Future<bool> preparePosition() async {
    try {
      final result = await connection.request('/popup/prepare-position', {
        'presentation': _presentation,
      });
      return result['positionedByCompositor'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _command(String path) async {
    try {
      _apply(await connection.request(path));
    } catch (_) {
      if (!_disposed) message('连接已断开，请重新打开弹窗。');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    connection.close();
    super.dispose();
  }
}
