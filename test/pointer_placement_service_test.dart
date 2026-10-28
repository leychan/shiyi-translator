import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/popup_placement.dart';
import 'package:just_translator/services/pointer_placement_service.dart';

const anchor = PopupAnchor(
  cursor: Offset(300, 200),
  workArea: Rect.fromLTWH(0, 0, 1920, 1040),
);

// Model KWin's scripts.size() IDs, including holes left by unloaded scripts.
class FakeKWinClient extends DBusClient {
  FakeKWinClient(List<int> existingIds)
    : super(DBusAddress.unix(path: '/unused-fake-kwin-bus')) {
    for (final id in existingIds) {
      final script = (id: id, file: null as String?);
      scripts['existing-$id'] = script;
      objects[id] = script;
    }
  }

  final scripts = <String, ({int id, String? file})>{};
  final objects = <int, ({int id, String? file})>{};
  final ran = <int>[];
  final loadedFiles = <File>[];
  late DBusObject replies;
  bool failRun = false;
  bool closed = false;

  @override
  String get uniqueName => ':1.100';

  @override
  Future<String?> getNameOwner(String name) async => ':1.8';

  @override
  Future<void> registerObject(DBusObject object) async => replies = object;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    String? destination,
    required DBusObjectPath path,
    String? interface,
    required String name,
    Iterable<DBusValue> values = const [],
    DBusSignature? replySignature,
    bool noReplyExpected = false,
    bool noAutoStart = false,
    bool allowInteractiveAuthorization = false,
  }) async {
    final args = values.toList();
    switch (name) {
      case 'Introspect':
        return DBusMethodSuccessResponse([
          DBusString(
            '<node>${objects.keys.map((id) => '<node name="Script$id"/>').join()}</node>',
          ),
        ]);
      case 'loadScript':
        final file = args[0].asString();
        final script = (id: scripts.length, file: file);
        scripts[args[1].asString()] = script;
        objects.putIfAbsent(script.id, () => script);
        loadedFiles.add(File(file));
        return DBusMethodSuccessResponse([DBusInt32(script.id)]);
      case 'run':
        final id = int.parse(path.value.split('Script').last);
        ran.add(id);
        final file = objects[id]!.file;
        if (file == null) throw StateError('Ran an unrelated existing script');
        if (failRun) throw StateError('Script execution failed');
        final token = File(file).uri.pathSegments.last.replaceFirst('.js', '');
        await replies.handleMethodCall(
          DBusMethodCall(
            sender: ':1.8',
            interface: 'dev.justtranslator.Placement',
            name: 'Reply',
            values: [
              DBusString(token),
              DBusString(jsonEncode(anchor.toJson())),
            ],
          ),
        );
        return DBusMethodSuccessResponse([]);
      case 'unloadScript':
        final script = scripts.remove(args.single.asString());
        if (script != null && objects[script.id] == script) {
          objects.remove(script.id);
        }
        return DBusMethodSuccessResponse([const DBusBoolean(true)]);
      default:
        throw StateError('Unexpected method: $name');
    }
  }
}

void main() {
  for (final ids in [
    <int>[],
    [0, 1],
    [1, 2],
    [2, 3],
  ]) {
    test('capture avoids occupied script paths $ids and cleans up', () async {
      final client = FakeKWinClient(ids);
      final bridge = KWinPlacementBridge(client: client);
      try {
        for (var i = 0; i < 2; i++) {
          final captured = await bridge.capture();
          expect(captured.cursor, anchor.cursor);
          expect(client.ran, everyElement(isNot(isIn(ids))));
          expect(client.scripts.keys, ids.map((id) => 'existing-$id'));
          expect(client.objects.keys, ids);
          for (final file in client.loadedFiles) {
            expect(await file.exists(), false);
          }
        }
      } finally {
        await bridge.dispose();
      }
      expect(client.closed, true);
    });
  }

  test(
    'retained placement survives captures and is cleaned up on dispose',
    () async {
      final client = FakeKWinClient([2, 3]);
      final bridge = KWinPlacementBridge(client: client);
      try {
        await bridge.prepare(123, anchor);
        expect(client.scripts.length, 3);
        await bridge.capture();
        expect(client.scripts.length, 3);
        await bridge.prepare(123, anchor);
        expect(client.scripts.length, 3);
        expect(client.ran, everyElement(isNot(isIn([2, 3]))));
      } finally {
        await bridge.dispose();
      }
      expect(client.scripts.keys, ['existing-2', 'existing-3']);
    },
  );

  test(
    'failed execution also unloads reserved slots and deletes script files',
    () async {
      final client = FakeKWinClient([2, 3])..failRun = true;
      final bridge = KWinPlacementBridge(client: client);
      try {
        await expectLater(bridge.capture(), throwsStateError);
        expect(client.scripts.keys, ['existing-2', 'existing-3']);
        expect(client.objects.keys, [2, 3]);
        for (final file in client.loadedFiles) {
          expect(await file.exists(), false);
        }
      } finally {
        await bridge.dispose();
      }
    },
  );
}
