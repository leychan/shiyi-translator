import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

import '../app_identity.dart';
import 'selection_service.dart';

class ShortcutService {
  DBusClient? _client;
  DBusObjectPath? _session;
  StreamSubscription<DBusSignal>? _activated;
  String label = 'Ctrl + Alt + Space';
  bool available = false;

  Future<void> register(Future<void> Function() onActivated) async {
    if (Platform.isLinux) {
      await _registerPortal(onActivated);
    } else {
      SelectionService.channel.setMethodCallHandler((call) async {
        if (call.method == 'translateSelection') await onActivated();
      });
      final registered = await SelectionService.channel.invokeMethod<bool>(
        'registerShortcut',
      );
      if (registered != true) throw StateError('快捷键已被其他软件占用');
      if (Platform.isMacOS) label = 'Control + Option + Space';
    }
    available = true;
  }

  Future<Map<String, DBusValue>> _request(
    DBusRemoteObject portal,
    String method,
    List<DBusValue> arguments,
    String token,
  ) async {
    final completer = Completer<DBusSignal>();
    final subscription =
        DBusSignalStream(
          _client!,
          sender: 'org.freedesktop.portal.Desktop',
          interface: 'org.freedesktop.portal.Request',
          name: 'Response',
        ).listen(
          (signal) {
            if (signal.path.value.endsWith('/$token') &&
                !completer.isCompleted) {
              completer.complete(signal);
            }
          },
          onError: (Object error) {
            if (!completer.isCompleted) completer.completeError(error);
          },
        );
    DBusObjectPath? requestPath;
    try {
      final response = await portal.callMethod(
        'org.freedesktop.portal.GlobalShortcuts',
        method,
        arguments,
        replySignature: DBusSignature('o'),
      );
      requestPath = response.values.first.asObjectPath();
      final signal = await completer.future.timeout(
        const Duration(seconds: 90),
      );
      if (signal.values.first.asUint32() != 0) throw StateError('快捷键授权未完成');
      return signal.values[1].asStringVariantDict();
    } on TimeoutException {
      if (requestPath != null) {
        await DBusRemoteObject(
          _client!,
          name: portal.name,
          path: requestPath,
        ).callMethod('org.freedesktop.portal.Request', 'Close', []);
      }
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _registerPortal(Future<void> Function() onActivated) async {
    await dispose();
    _client = DBusClient.session();
    final portal = DBusRemoteObject(
      _client!,
      name: 'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );
    try {
      await portal.callMethod(
        'org.freedesktop.host.portal.Registry',
        'Register',
        [
          const DBusString('dev.justtranslator.just_translator'),
          DBusDict.stringVariant({}),
        ],
      );
    } on DBusMethodResponseException catch (error) {
      // Older portals identify unsandboxed clients without the Registry API.
      if (![
        'org.freedesktop.DBus.Error.UnknownMethod',
        'org.freedesktop.DBus.Error.UnknownInterface',
      ].contains(error.errorName)) {
        rethrow;
      }
    }
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final createToken = 'jt_create_$suffix';
    final response = await _request(portal, 'CreateSession', [
      DBusDict.stringVariant({
        'handle_token': DBusString(createToken),
        'session_handle_token': DBusString('jt_session_$suffix'),
      }),
    ], createToken);
    _session = DBusObjectPath(response['session_handle']!.asString());
    _activated =
        DBusSignalStream(
          _client!,
          sender: 'org.freedesktop.portal.Desktop',
          interface: 'org.freedesktop.portal.GlobalShortcuts',
          name: 'Activated',
          path: portal.path,
        ).listen((signal) {
          if (signal.values[0].asObjectPath() == _session &&
              signal.values[1].asString() == 'translate-selection') {
            unawaited(onActivated());
          }
        });
    final bindToken = 'jt_bind_$suffix';
    final bound = await _request(portal, 'BindShortcuts', [
      _session!,
      DBusArray(DBusSignature('(sa{sv})'), [
        DBusStruct([
          const DBusString('translate-selection'),
          DBusDict.stringVariant({
            'description': const DBusString('$appName · 翻译选中文字'),
            'preferred_trigger': const DBusString('CTRL+ALT+space'),
          }),
        ]),
      ]),
      const DBusString(''),
      DBusDict.stringVariant({'handle_token': DBusString(bindToken)}),
    ], bindToken);
    final shortcuts = bound['shortcuts'];
    if (shortcuts is DBusArray && shortcuts.children.isNotEmpty) {
      final values = (shortcuts.children.first as DBusStruct).children;
      label =
          values[1].asStringVariantDict()['trigger_description']?.asString() ??
          label;
    } else {
      throw StateError('桌面环境未绑定快捷键');
    }
  }

  Future<void> dispose() async {
    available = false;
    await _activated?.cancel();
    _activated = null;
    if (_client != null) {
      try {
        if (_session != null) {
          await DBusRemoteObject(
            _client!,
            name: 'org.freedesktop.portal.Desktop',
            path: _session!,
          ).callMethod('org.freedesktop.portal.Session', 'Close', []);
        }
      } catch (_) {
        /* The desktop may have closed the session already. */
      }
      await _client!.close();
    }
    _client = null;
    _session = null;
  }
}
