import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// A file lock elects one instance; authenticated loopback IPC forwards actions.
class InstanceService {
  InstanceService({this.directory});
  final Directory? directory;
  RandomAccessFile? _lock;
  HttpServer? _server;
  File? _sessionFile;
  String? _token;
  Future<void> Function(String)? onAction;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? onRpc;
  final List<String> _pending = [];

  Future<bool> startOrForward(String action) async {
    final support = directory ?? await getApplicationSupportDirectory();
    await support.create(recursive: true);
    _sessionFile = File('${support.path}/session.json');
    final lock = await File('${support.path}/instance.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      await _forward(action);
      return false;
    }
    _lock = lock;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _token = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    await _sessionFile!.writeAsString(
      jsonEncode({'port': _server!.port, 'token': _token}),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', _sessionFile!.path]);
    }
    _server!.listen((request) async {
      if (request.method != 'POST' ||
          request.headers.value('authorization') != 'Bearer $_token') {
        request.response.statusCode = HttpStatus.forbidden;
      } else if (request.uri.path.startsWith('/popup/') && onRpc != null) {
        try {
          final bytes = <int>[];
          await for (final chunk in request) {
            bytes.addAll(chunk);
            if (bytes.length > 262144) {
              throw const FormatException('Request too large');
            }
          }
          final data = bytes.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          final response = await onRpc!(request.uri.path, data);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
        } catch (_) {
          request.response.statusCode = HttpStatus.badRequest;
        }
      } else if (![
        '/show',
        '/selection',
        '/clipboard',
        '/autostart',
      ].contains(request.uri.path)) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        final name = request.uri.path.substring(1);
        if (onAction == null) {
          _pending.add(name);
        } else {
          unawaited(onAction!(name));
        }
        request.response.statusCode = HttpStatus.accepted;
      }
      await request.response.close();
    });
    return true;
  }

  Future<void> _forward(String action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 15; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        final data = jsonDecode(
          await _sessionFile!.readAsString(),
        ) as Map<String, dynamic>;
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${data['port']}/$action'),
        );
        request.headers.set('authorization', 'Bearer ${data['token']}');
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        await response.drain<void>();
        if (response.statusCode != HttpStatus.accepted) {
          throw StateError('IPC rejected');
        }
        return;
      } catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('无法连接已运行的应用：$lastError');
  }

  Future<void> drainPending() async {
    for (final action in _pending.toList()) {
      await onAction?.call(action);
    }
    _pending.clear();
  }

  Future<void> close() async {
    await _server?.close(force: true);
    if (_lock != null) {
      await _sessionFile?.delete();
      await _lock!.unlock();
      await _lock!.close();
    }
  }
}
