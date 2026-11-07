import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/services/linux_tray_status.dart';

class TrayWatcher extends DBusObject {
  TrayWatcher() : super(DBusObjectPath('/StatusNotifierWatcher'));
  List<String> items = [];
  bool host = true;

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (name == 'RegisteredStatusNotifierItems') {
      return DBusGetPropertyResponse(DBusArray.string(items));
    }
    return DBusGetPropertyResponse(DBusBoolean(host));
  }
}

class TrayItem extends DBusObject {
  TrayItem() : super(DBusObjectPath('/org/ayatana/NotificationItem/test'));
  String status = 'Active';

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async =>
      DBusGetPropertyResponse(DBusString(status));
}

void main() {
  test(
    'only a registered, active item owned by this process is usable',
    () async {
      // Use a private bus; never register test items on the user's desktop.
      final daemon = await Process.start('dbus-daemon', [
        '--session',
        '--nofork',
        '--print-address=1',
      ]);
      final address = DBusAddress(
        await daemon.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
      );
      final owner = DBusClient(address);
      final watcher = TrayWatcher();
      final item = TrayItem();
      try {
        await owner.requestName('org.kde.StatusNotifierWatcher');
        await owner.registerObject(watcher);
        await owner.registerObject(item);
        final status = LinuxTrayStatus(connect: () => DBusClient(address));
        // Exporting the native item without registering it was the actual failure.
        expect(await status.isAvailable(), false);
        watcher.items = ['${owner.uniqueName}${item.path.value}'];
        expect(await status.isAvailable(), true);
        expect(
          await LinuxTrayStatus(
            connect: () => DBusClient(address),
            processId: pid + 1,
          ).isAvailable(),
          false,
        );
        item.status = 'Passive';
        expect(await status.isAvailable(), false);
        item.status = 'NeedsAttention';
        expect(await status.isAvailable(), true);
        watcher.host = false;
        expect(await status.isAvailable(), false);
        watcher.host = true;
        watcher.items.insert(0, ':1.999999/StatusNotifierItem');
        expect(await status.isAvailable(), true);
        await owner.releaseName('org.kde.StatusNotifierWatcher');
        expect(await status.isAvailable(), false);
      } finally {
        await owner.close();
        daemon.kill();
        await daemon.exitCode;
      }
    },
    skip: !Platform.isLinux,
  );
}
