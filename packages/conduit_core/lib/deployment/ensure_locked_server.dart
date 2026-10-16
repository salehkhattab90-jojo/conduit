import 'dart:async';

import 'package:collection/collection.dart';
import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/deployment/deployment_policy.dart';
import 'package:conduit_core/models/openwebui_registry.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/persistence/persistence_keys.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/providers/app_providers.dart'
    show activeServerProvider, serverConfigsProvider;
import 'package:conduit_core/providers/backend_mode_providers.dart';
import 'package:conduit_core/providers/storage_providers.dart';
import 'package:conduit_core/services/optimized_storage_service.dart';
import 'package:conduit_core/utils/debug_logger.dart';

/// Saves [server] as the active Open WebUI server, unless it already is.
///
/// Idempotent: the account [LockedServer.id] is created when missing, its
/// server's name and routes are brought in line with [LockedServer.name] and
/// [LockedServer.urls] (a route whose address is unchanged keeps its id,
/// settings and captured proxy cookie), and it is made the active account.
/// A seeded server looks like the ordinary "signed out, server kept" state,
/// so the router lands on sign-in. Any other saved account is left alone.
///
/// Returns whether anything was written.
Future<bool> ensureLockedServer(
  OptimizedStorageService storage,
  LockedServer server,
) async {
  if (server.urls.isEmpty) {
    throw ArgumentError.value(server.urls, 'server.urls', 'is empty');
  }
  var changed = false;

  final configs = await storage.getServerConfigsStrict();
  if (!configs.any((config) => config.id == server.id)) {
    await storage.saveServerConfigs([
      ...configs,
      ServerConfig(
        id: server.id,
        name: server.name,
        url: server.urls.first,
        isActive: true,
      ),
    ]);
    changed = true;
  }

  final registry = await storage.getOpenWebUiRegistryStrict();
  final account = registry.account(server.id);
  final saved = account == null ? null : registry.server(account.serverId);
  if (saved != null && !lockedServerMatches(saved, server)) {
    await storage.saveServer(
      OpenWebUiServer(
        id: saved.id,
        name: server.name,
        endpoints: lockedServerEndpoints(saved, server),
      ),
    );
    changed = true;
  }

  if (await storage.getActiveServerId() != server.id) {
    await storage.setActiveServerId(server.id);
    changed = true;
  }
  return changed;
}

/// Whether [saved] already has [server]'s name and routes, in order.
bool lockedServerMatches(OpenWebUiServer saved, LockedServer server) {
  if (saved.name != server.name) return false;
  if (saved.endpoints.length != server.urls.length) return false;
  for (var i = 0; i < server.urls.length; i++) {
    if (openWebUiServerIdentityUrl(saved.endpoints[i].url) !=
        openWebUiServerIdentityUrl(server.urls[i])) {
      return false;
    }
  }
  return true;
}

/// [server]'s routes, reusing each of [saved]'s routes whose address is
/// unchanged and minting an id for each new one.
List<OpenWebUiEndpoint> lockedServerEndpoints(
  OpenWebUiServer saved,
  LockedServer server,
) {
  final usedIds = {for (final endpoint in saved.endpoints) endpoint.id};
  final reused = <String>{};
  String newId(int index) {
    var candidate = 'endpoint:${server.id}:$index';
    var suffix = 2;
    while (!usedIds.add(candidate)) {
      candidate = 'endpoint:${server.id}:$index-${suffix++}';
    }
    return candidate;
  }

  final endpoints = <OpenWebUiEndpoint>[];
  for (final (index, url) in server.urls.indexed) {
    final identity = openWebUiServerIdentityUrl(url);
    final existing = saved.endpoints.firstWhereOrNull(
      (endpoint) =>
          !reused.contains(endpoint.id) &&
          openWebUiServerIdentityUrl(endpoint.url) == identity,
    );
    if (existing != null) {
      reused.add(existing.id);
      endpoints.add(existing);
    } else {
      endpoints.add(OpenWebUiEndpoint(id: newId(index), url: url));
    }
  }
  return endpoints;
}

/// Seeds the locked server of the [deploymentPolicyProvider] and keeps the
/// preferred backend on Open WebUI. Does nothing for an unlocked build.
final lockedServerBootstrapProvider = Provider<LockedServerBootstrap>(
  LockedServerBootstrap.new,
);

final class LockedServerBootstrap {
  LockedServerBootstrap(this._ref);

  final Ref _ref;
  Future<bool>? _inFlight;

  /// Runs [ensureLockedServer] for the locked server, once at a time.
  /// Returns whether the server is in place; a storage failure is logged and
  /// reads as false, and the next call tries again.
  Future<bool> ensure() => _inFlight ??= _ensure().whenComplete(() {
    _inFlight = null;
  });

  Future<bool> _ensure() async {
    final server = _ref.read(deploymentPolicyProvider).lockedServer;
    if (server == null) return true;
    try {
      final changed = await ensureLockedServer(
        _ref.read(optimizedStorageServiceProvider),
        server,
      );
      if (PreferencesStore.getString(PreferenceKeys.preferredBackend) !=
          PreferredBackend.owui.name) {
        await _ref
            .read(preferredBackendProvider.notifier)
            .set(PreferredBackend.owui);
      }
      if (changed) _ref.invalidate(serverConfigsProvider);
      return true;
    } catch (error, stackTrace) {
      DebugLogger.error(
        'locked-server-seed-failed',
        scope: 'deployment',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}

/// Puts the locked server back whenever there is no active server: after a
/// sign-out that could not keep it, or anything else that removed it. The
/// redirect holds the splash meanwhile. Read once by the host; does nothing
/// for an unlocked build.
final lockedServerGuardProvider = Provider<void>((ref) {
  if (!ref.watch(deploymentPolicyProvider).isLocked) return;
  ref.listen<AsyncValue<ServerConfig?>>(activeServerProvider, (_, next) {
    if (next.isLoading || next.hasError || next.value != null) return;
    unawaited(ref.read(lockedServerBootstrapProvider).ensure());
  }, fireImmediately: true);
});
