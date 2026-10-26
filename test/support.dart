import 'package:just_translator/models.dart';
import 'package:just_translator/services/storage_service.dart';

class MemoryStore implements SettingsStore {
  AppSettings settings = AppSettings();
  final keys = <String, String>{};
  int saves = 0;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async {
    settings = value;
    saves++;
  }

  @override
  Future<String> readKey(String id) async => keys[id] ?? '';
  @override
  Future<void> writeKey(String id, String value) async {
    keys[id] = value;
  }

  @override
  Future<void> deleteKey(String id) async {
    keys.remove(id);
  }
}

ProviderConfig provider({
  String id = 'test',
  ProviderKind kind = ProviderKind.compatible,
  String endpoint = 'http://127.0.0.1:9000/v1',
  bool streaming = true,
}) => ProviderConfig(
  id: id,
  name: 'Test $id',
  kind: kind,
  endpoint: endpoint,
  model: 'test-model',
  streaming: streaming,
);
