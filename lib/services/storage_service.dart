import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Future<String> readKey(String id);
  Future<void> writeKey(String id, String value);
  Future<void> deleteKey(String id);
}

class StorageService implements SettingsStore {
  final _vault = const FlutterSecureStorage();
  Future<void> _writes = Future.value();
  String? loadWarning;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}/settings.json');
  }

  @override
  Future<AppSettings> load() async {
    final file = await _file();
    if (!await file.exists()) return AppSettings();
    try {
      return AppSettings.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      await file.copy(
        '${file.path}.invalid-${DateTime.now().millisecondsSinceEpoch}',
      );
    } on TypeError {
      await file.copy(
        '${file.path}.invalid-${DateTime.now().millisecondsSinceEpoch}',
      );
    } on ArgumentError {
      await file.copy(
        '${file.path}.invalid-${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    loadWarning = '原配置文件无法读取，已备份并使用默认设置。';
    return AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) {
    final snapshot = const JsonEncoder.withIndent('  ')
        .convert(settings.toJson());
    final write = _writes.then((_) async {
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  @override
  Future<String> readKey(String id) async =>
      await _vault.read(key: 'provider.$id') ?? '';
  @override
  Future<void> writeKey(String id, String value) async {
    if (value.isEmpty) {
      await deleteKey(id);
    } else {
      await _vault.write(key: 'provider.$id', value: value);
    }
  }

  @override
  Future<void> deleteKey(String id) => _vault.delete(key: 'provider.$id');
}
