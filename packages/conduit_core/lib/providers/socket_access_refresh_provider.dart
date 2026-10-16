import 'dart:async';

import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/socket_service.dart';
import 'package:conduit_core/utils/debug_logger.dart';

/// Reads the account's permissions and models again when the server says its
/// access changed (Open WebUI 0.12 sends `access:updated` on role and group
/// changes, then reconnects the session), as the web client does on its next
/// `connect`. Started once by app startup and kept alive; it follows the
/// socket service across account and server changes.
final socketAccessRefreshProvider = Provider<void>((ref) {
  StreamSubscription<void>? subscription;
  void bind(SocketService? socket) {
    unawaited(subscription?.cancel());
    subscription = null;
    if (socket == null) return;
    try {
      subscription = socket.onAccessUpdated.listen((_) {
        if (!identical(socket, ref.read(socketServiceProvider))) return;
        refreshAfterAccessChange(ref);
      });
    } catch (_) {
      // A stand-in service without the stream: nothing to follow.
    }
  }

  ref.listen<SocketService?>(
    socketServiceProvider,
    (_, next) => bind(next),
    fireImmediately: true,
  );
  ref.onDispose(() => unawaited(subscription?.cancel()));
});

/// Drops the cached permissions and reloads the models, which the server
/// filters by the account's access.
void refreshAfterAccessChange(Ref ref) {
  DebugLogger.log('Account access changed; refreshing', scope: 'socket');
  ref.invalidate(userPermissionsProvider);
  unawaited(
    ref.read(modelsProvider.notifier).refresh().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      DebugLogger.error(
        'models-refresh-after-access-change-failed',
        scope: 'socket',
        error: error,
        stackTrace: stackTrace,
      );
    }),
  );
}
