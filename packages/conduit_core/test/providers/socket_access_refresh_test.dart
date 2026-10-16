import 'dart:async';

import 'package:checks/checks.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/socket_access_refresh_provider.dart';
import 'package:conduit_core/services/socket_service.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

class _FakeSocket implements SocketService {
  final accessUpdates = StreamController<void>.broadcast();

  @override
  Stream<void> get onAccessUpdated => accessUpdates.stream;

  @override
  ServerConfig get serverConfig => const ServerConfig(
    id: 'server',
    name: 'Server',
    url: 'https://example.test',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CountingModels extends Models {
  int refreshes = 0;

  @override
  Future<List<Model>> build() async => const <Model>[];

  @override
  Future<void> refresh() async => refreshes++;
}

final _socketHolder = NotifierProvider<_SocketHolder, SocketService?>(
  _SocketHolder.new,
);

class _SocketHolder extends Notifier<SocketService?> {
  @override
  SocketService? build() => null;

  void set(SocketService? socket) => state = socket;
}

void main() {
  test('an access change re-reads permissions and models', () async {
    var permissionReads = 0;
    final models = _CountingModels();
    final first = _FakeSocket();
    final second = _FakeSocket();
    final container = ProviderContainer(
      overrides: [
        socketServiceProvider.overrideWith((ref) => ref.watch(_socketHolder)),
        userPermissionsProvider.overrideWith((ref) async {
          permissionReads++;
          return const <String, dynamic>{};
        }),
        modelsProvider.overrideWith(() => models),
      ],
    );
    addTearDown(container.dispose);
    container.read(_socketHolder.notifier).set(first);
    container.listen(userPermissionsProvider, (_, _) {});
    await container.read(userPermissionsProvider.future);
    container.read(socketAccessRefreshProvider);
    check(permissionReads).equals(1);

    first.accessUpdates.add(null);
    await Future<void>.delayed(Duration.zero);
    await container.read(userPermissionsProvider.future);
    check(permissionReads).equals(2);
    check(models.refreshes).equals(1);

    // It follows the socket service to its replacement.
    container.read(_socketHolder.notifier).set(second);
    await Future<void>.delayed(Duration.zero);
    first.accessUpdates.add(null);
    await Future<void>.delayed(Duration.zero);
    check(models.refreshes).equals(1);

    second.accessUpdates.add(null);
    await Future<void>.delayed(Duration.zero);
    await container.read(userPermissionsProvider.future);
    check(permissionReads).equals(3);
    check(models.refreshes).equals(2);
  });
}
