import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dbus/dbus.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../popup_placement.dart';

class PointerPlacementService {
  KWinPlacementBridge? _kwin;
  bool get usesKWin =>
      Platform.isLinux &&
      Platform.environment['XDG_SESSION_TYPE'] == 'wayland' &&
      (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '')
          .toLowerCase()
          .contains('kde');

  Future<PopupAnchor?> capture() async {
    try {
      if (usesKWin) return await (_kwin ??= KWinPlacementBridge()).capture();
      if (Platform.isLinux &&
          Platform.environment['XDG_SESSION_TYPE'] == 'wayland') {
        return null;
      }
      final cursor = await screenRetriever.getCursorScreenPoint();
      final displays = await screenRetriever.getAllDisplays();
      if (displays.isEmpty) return null;
      Rect area(Display display) =>
          (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size);
      final matching = displays.where(
        (display) => area(display).contains(cursor),
      );
      double distance(Display display) {
        final bounds = area(display);
        return (cursor -
                Offset(
                  cursor.dx.clamp(bounds.left, bounds.right),
                  cursor.dy.clamp(bounds.top, bounds.bottom),
                ))
            .distanceSquared;
      }

      final display = matching.isNotEmpty
          ? matching.first
          : displays.reduce((a, b) => distance(a) <= distance(b) ? a : b);
      return PopupAnchor(cursor: cursor, workArea: area(display));
    } catch (_) {
      return null;
    }
  }

  Future<bool> prepare(int popupPid, PopupAnchor anchor) async {
    if (!usesKWin) return false;
    try {
      await (_kwin ??= KWinPlacementBridge()).prepare(popupPid, anchor);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await _kwin?.dispose();
  }
}

class _PlacementReplies extends DBusObject {
  _PlacementReplies(this.deliver)
    : super(DBusObjectPath('/dev/justtranslator/placement'));
  final void Function(String token, String payload, String sender) deliver;
  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'dev.justtranslator.Placement' ||
        call.name != 'Reply' ||
        call.signature != DBusSignature('ss')) {
      return DBusMethodErrorResponse.unknownMethod();
    }
    deliver(
      call.values[0].asString(),
      call.values[1].asString(),
      call.sender ?? '',
    );
    return DBusMethodSuccessResponse([]);
  }
}

/// KWin owns global coordinates on KDE Wayland. Scripts are temporary, target
/// only our popup PID, and are unloaded when replaced or the application quits.
class KWinPlacementBridge {
  final _client = DBusClient.session();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Future<void>? _initializing;
  late DBusRemoteObject _scripting;
  late Directory _directory;
  String? _owner;
  String? _placementScript;
  int _serial = 0;

  Future<void> _initialize() => _initializing ??= _setup();
  Future<void> _setup() async {
    _owner = await _client.getNameOwner('org.kde.KWin');
    if (_owner == null) throw StateError('KWin unavailable');
    await _client.registerObject(
      _PlacementReplies((token, payload, sender) {
        if (sender != _owner) return;
        final completer = _pending[token];
        if (completer == null || completer.isCompleted) return;
        try {
          completer.complete(jsonDecode(payload) as Map<String, dynamic>);
        } catch (error) {
          completer.completeError(error);
        }
      }),
    );
    _directory = await Directory.systemTemp.createTemp(
      'just-translator-placement-',
    );
    _scripting = DBusRemoteObject(
      _client,
      name: 'org.kde.KWin',
      path: DBusObjectPath('/Scripting'),
    );
  }

  String _reply(String token, String expression) =>
      'callDBus(${jsonEncode(_client.uniqueName)}, "/dev/justtranslator/placement", '
      '"dev.justtranslator.Placement", "Reply", ${jsonEncode(token)}, JSON.stringify($expression));';

  Future<Map<String, dynamic>> _run(
    String Function(String token) body, {
    bool retain = false,
  }) async {
    await _initialize();
    final connection = _client.uniqueName.replaceAll(
      RegExp(r'[^a-zA-Z0-9_]'),
      '_',
    );
    final token = 'jt_${pid}_${connection}_${++_serial}';
    final name = 'just-translator-$token';
    final file = File('${_directory.path}/$token.js');
    await file.writeAsString(body(token), flush: true);
    final completer = Completer<Map<String, dynamic>>();
    _pending[token] = completer;
    try {
      final loaded = await _scripting.callMethod(
        'org.kde.kwin.Scripting',
        'loadScript',
        [DBusString(file.path), DBusString(name)],
      );
      final id = loaded.values.single.asInt32();
      if (id < 0) throw StateError('KWin rejected positioning script');
      final script = DBusRemoteObject(
        _client,
        name: 'org.kde.KWin',
        path: DBusObjectPath('/Scripting/Script$id'),
      );
      await script.callMethod('org.kde.kwin.Script', 'run', []);
      final result = await completer.future.timeout(const Duration(seconds: 2));
      if (result['error'] != null) throw StateError('KWin positioning failed');
      if (retain) _placementScript = name;
      return result;
    } finally {
      _pending.remove(token);
      if (!retain || _placementScript != name) await _unload(name);
      if (await file.exists()) await file.delete();
    }
  }

  Future<PopupAnchor> capture() async {
    final result = await _run(
      (token) =>
          '''
try {
  var p = workspace.cursorPos;
  var output = workspace.screenAt(p) || workspace.activeScreen;
  var area = workspace.clientArea(KWin.MaximizeArea, output, workspace.currentDesktop);
  ${_reply(token, '{x:p.x,y:p.y,left:area.x,top:area.y,width:area.width,height:area.height}')}
} catch (e) { ${_reply(token, '{error:String(e)}')} }
''',
    );
    return PopupAnchor.fromJson(result);
  }

  Future<void> prepare(int popupPid, PopupAnchor anchor) async {
    await _initialize();
    if (_placementScript != null) {
      await _unload(_placementScript!);
      _placementScript = null;
    }
    await _run(
      (token) =>
          '''
try {
  var anchor = ${jsonEncode(anchor.toJson())};
  var targetPid = $popupPid;
  var positioned = false;
  function matches(window) {
    return window && Number(window.pid) === targetPid &&
      String(window.resourceClass) === 'dev.justtranslator.just_translator';
  }
  function place(window, force) {
    if (!matches(window) || (positioned && !force)) return;
    var area = anchor;
    var geometry = window.frameGeometry;
    var width = Math.min(geometry.width > 0 ? geometry.width : 480, area.width - 16);
    var height = Math.min(geometry.height > 0 ? geometry.height : 700, area.height - 16);
    var x = anchor.x + 14, y = anchor.y + 18;
    if (x + width > area.left + area.width - 8) x = anchor.x - width - 14;
    if (y + height > area.top + area.height - 8) y = anchor.y - height - 18;
    x = Math.max(area.left + 8, Math.min(x, area.left + area.width - width - 8));
    y = Math.max(area.top + 8, Math.min(y, area.top + area.height - height - 8));
    window.frameGeometry = {x:Math.round(x),y:Math.round(y),width:width,height:height};
    positioned = true;
  }
  function watch(window) {
    if (!matches(window)) return;
    window.windowShown.connect(function() { place(window, true); });
    place(window, true);
  }
  workspace.windowAdded.connect(watch);
  workspace.windowActivated.connect(function(window) { place(window, false); });
  workspace.windowList().forEach(watch);
  ${_reply(token, '{ready:true}')}
} catch (e) { ${_reply(token, '{error:String(e)}')} }
''',
      retain: true,
    );
  }

  Future<void> _unload(String name) async {
    try {
      await _scripting.callMethod('org.kde.kwin.Scripting', 'unloadScript', [
        DBusString(name),
      ]);
    } catch (_) {
      /* KWin may already have removed the script. */
    }
  }

  Future<Rect?> popupGeometry(int popupPid) async {
    final result = await _run(
      (token) =>
          '''
var window = workspace.windowList().find(function(w) { return w.pid === $popupPid; });
var geometry = window ? window.frameGeometry : null;
${_reply(token, 'geometry ? {x:geometry.x,y:geometry.y,width:geometry.width,height:geometry.height} : {missing:true}')}
''',
    );
    if (result['missing'] == true) return null;
    return Rect.fromLTWH(
      (result['x'] as num).toDouble(),
      (result['y'] as num).toDouble(),
      (result['width'] as num).toDouble(),
      (result['height'] as num).toDouble(),
    );
  }

  Future<void> dispose() async {
    if (_initializing != null) {
      try {
        await _initializing;
        if (_placementScript != null) await _unload(_placementScript!);
        if (await _directory.exists()) await _directory.delete(recursive: true);
      } catch (_) {
        /* The desktop can disappear during logout. */
      }
    }
    await _client.close();
  }
}
