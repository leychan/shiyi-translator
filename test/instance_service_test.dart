import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/services/instance_service.dart';

void main() {
  test(
    'IPC requires a token and queues actions until the window is ready',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'just-translator-ipc-',
      );
      final instance = InstanceService(directory: directory);
      final client = HttpClient();
      try {
        expect(await instance.startOrForward('show'), true);
        final session = jsonDecode(
          await File('${directory.path}/session.json').readAsString(),
        );
        final uri = Uri.parse('http://127.0.0.1:${session['port']}/selection');
        final unauthenticated = await client.postUrl(uri);
        final rejected = await unauthenticated.close();
        expect(rejected.statusCode, HttpStatus.forbidden);
        await rejected.drain<void>();
        final request = await client.postUrl(uri);
        request.headers.set('authorization', 'Bearer ${session['token']}');
        final accepted = await request.close();
        expect(accepted.statusCode, HttpStatus.accepted);
        await accepted.drain<void>();
        final startup = await client.postUrl(uri.replace(path: '/autostart'));
        startup.headers.set('authorization', 'Bearer ${session['token']}');
        final startupAccepted = await startup.close();
        expect(startupAccepted.statusCode, HttpStatus.accepted);
        await startupAccepted.drain<void>();
        final actions = <String>[];
        instance.onAction = (action) async {
          actions.add(action);
        };
        await instance.drainPending();
        expect(actions, ['selection', 'autostart']);
      } finally {
        client.close(force: true);
        await instance.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
