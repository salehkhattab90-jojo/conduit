import 'dart:io';

import 'package:checks/checks.dart';
import 'package:conduit_core/deployment/deployment_policy.dart';
import 'package:conduit_core/deployment/ensure_locked_server.dart';
import 'package:conduit_core/models/openwebui_registry.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/persistence/hive_boxes.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/ports/key_value_store.dart';
import 'package:conduit_core/ports/secure_key_value_store.dart';
import 'package:conduit_core/services/optimized_storage_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

const _server = LockedServer(
  id: 'locked-server',
  name: 'Example',
  urls: ['https://chat.example.test', 'https://chat-backup.example.test'],
);

void main() {
  late Directory tempDir;
  late OptimizedStorageService storage;
  late WorkerManager workerManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('locked-server-test');
    Hive.init(tempDir.path);
    final boxes = HiveBoxes(
      preferences: await Hive.openBox<dynamic>(HiveBoxNames.preferences),
      caches: await Hive.openBox<dynamic>(HiveBoxNames.caches),
      attachmentQueue: await Hive.openBox<dynamic>(
        HiveBoxNames.attachmentQueue,
      ),
      metadata: await Hive.openBox<dynamic>(HiveBoxNames.metadata),
    );
    PreferencesStore.installLoader(() async => InMemoryKeyValueStore());
    await PreferencesStore.ensureInitialized();
    workerManager = WorkerManager(maxConcurrentTasks: 1);
    storage = OptimizedStorageService(
      secureStorage: InMemorySecureKeyValueStore(),
      boxes: boxes,
      workerManager: workerManager,
    );
  });

  tearDown(() async {
    workerManager.dispose();
    PreferencesStore.debugReset();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<OpenWebUiServer> savedServer() async {
    final registry = await storage.getOpenWebUiRegistryStrict();
    final account = registry.account(_server.id);
    check(account).isNotNull();
    return registry.server(account!.serverId)!;
  }

  test('seeds the server, its routes and the active account', () async {
    check(await ensureLockedServer(storage, _server)).isTrue();

    final configs = await storage.getServerConfigsStrict();
    check(configs.map((config) => config.id)).deepEquals([_server.id]);
    check(configs.single.url).equals(_server.urls.first);
    check(configs.single.name).equals(_server.name);
    check(await storage.getActiveServerId()).equals(_server.id);

    final server = await savedServer();
    check(server.name).equals(_server.name);
    check(server.endpoints.map((endpoint) => endpoint.url))
        .deepEquals(_server.urls);
  });

  test('is idempotent', () async {
    await ensureLockedServer(storage, _server);
    final before = await savedServer();

    check(await ensureLockedServer(storage, _server)).isFalse();
    check(await savedServer()).equals(before);
    check(await storage.getActiveServerId()).equals(_server.id);
  });

  test('follows a new address list, keeping the routes that stayed', () async {
    await ensureLockedServer(storage, _server);
    final before = await savedServer();
    const moved = LockedServer(
      id: 'locked-server',
      name: 'Renamed',
      urls: ['https://chat-backup.example.test/', 'https://new.example.test'],
    );

    check(await ensureLockedServer(storage, moved)).isTrue();

    final after = await savedServer();
    check(after.id).equals(before.id);
    check(after.name).equals('Renamed');
    check(after.endpoints).length.equals(2);
    // The backup route kept its id (and with it its settings and cookie).
    check(after.endpoints.first.id).equals(before.endpoints.last.id);
    check(after.endpoints.last.url).equals('https://new.example.test');
    check(await ensureLockedServer(storage, moved)).isFalse();
  });

  test('makes the locked account active again and leaves others', () async {
    await storage.saveServerConfigs(const [
      ServerConfig(id: 'other', name: 'Other', url: 'https://other.test'),
    ]);
    await storage.setActiveServerId('other');

    check(await ensureLockedServer(storage, _server)).isTrue();

    final ids = (await storage.getServerConfigsStrict()).map((c) => c.id);
    check(ids).unorderedEquals(['other', _server.id]);
    check(await storage.getActiveServerId()).equals(_server.id);
  });

  test('refuses a server without an address', () async {
    await check(
      ensureLockedServer(
        storage,
        const LockedServer(id: 'x', name: 'x', urls: []),
      ),
    ).throws<ArgumentError>();
  });
}
