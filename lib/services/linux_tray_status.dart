import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// A successful tray_manager call does not guarantee registration with the host.
class LinuxTrayStatus {
  LinuxTrayStatus({DBusClient Function()? connect, int? processId})
    : _connect = connect ?? DBusClient.session,
      _processId = processId ?? pid;

  final DBusClient Function() _connect;
  final int _processId;

  Future<bool> isAvailable() async {
    final client = _connect();
    try {
      return await _check(client).timeout(const Duration(seconds: 2));
    } catch (_) {
      return false;
    } finally {
      await client.close();
    }
  }

  Future<bool> _check(DBusClient client) async {
    const watcherInterface = 'org.kde.StatusNotifierWatcher';
    final watcher = DBusRemoteObject(
      client,
      name: watcherInterface,
      path: DBusObjectPath('/StatusNotifierWatcher'),
    );
    if (!(await watcher.getProperty(
      watcherInterface,
      'IsStatusNotifierHostRegistered',
    )).asBoolean()) {
      return false;
    }
    final items = (await watcher.getProperty(
      watcherInterface,
      'RegisteredStatusNotifierItems',
    )).asStringArray();
    for (final item in items) {
      try {
        final slash = item.indexOf('/');
        final name = slash < 0 ? item : item.substring(0, slash);
        final path = slash < 0 ? '/StatusNotifierItem' : item.substring(slash);
        if (await client.getConnectionUnixProcessId(name) != _processId) {
          continue;
        }
        final status = (await DBusRemoteObject(
          client,
          name: name,
          path: DBusObjectPath(path),
        ).getProperty('org.kde.StatusNotifierItem', 'Status')).asString();
        if (status == 'Active' || status == 'NeedsAttention') return true;
      } catch (_) {
        // An unrelated tray item may disappear while the list is being read.
      }
    }
    return false;
  }
}
