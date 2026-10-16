import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/providers/app_providers.dart';

/// Whether [config] says the server at [serverId] hosts the Email section.
///
/// The server reports `features.enable_email` only to a signed-in account, and
/// the cached config counts only when it was fetched from that server.
bool emailFeatureEnabled({
  required BackendConfig? config,
  required String serverId,
}) =>
    config != null && config.serverId == serverId && config.enableEmail == true;

/// Whether the Email section exists for the active account.
final emailFeatureEnabledProvider = Provider<bool>((ref) {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return false;
  final config = ref.watch(backendConfigProvider).asData?.value;
  // Most servers never report the flag; settle that before asking the client
  // which server it belongs to.
  if (config?.enableEmail != true) return false;
  return emailFeatureEnabled(config: config, serverId: api.serverConfig.id);
});

/// Set when something outside the widget tree -- a tapped notification --
/// asks to show the Email section.
///
/// The drawer shell consumes it once mounted: it selects the Email tab and
/// opens the drawer, which covers foreground, background and cold-start taps.
/// An account switch drops a request the previous account made.
final emailOpenRequestProvider = NotifierProvider<EmailOpenRequest, bool>(
  EmailOpenRequest.new,
);

class EmailOpenRequest extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(settledActiveAccountIdProvider);
    return false;
  }

  void request() => state = true;

  void consume() => state = false;
}

/// The message a tapped notification wants opened, held until the Email web
/// app has loaded and can be told to open it. Kept apart from
/// [emailOpenRequestProvider] so the shell and the tab consume independently.
final pendingEmailMessageProvider =
    NotifierProvider<PendingEmailMessage, String?>(PendingEmailMessage.new);

class PendingEmailMessage extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(settledActiveAccountIdProvider);
    return null;
  }

  void set(String? id) {
    final trimmed = id?.trim();
    state = trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void clear() => state = null;
}

/// Records a notification tap: remember [messageId] (when there is one) and
/// ask the shell to show the Email section.
void requestEmailOpen(Ref ref, String? messageId) {
  final id = messageId?.trim();
  if (id != null && id.isNotEmpty) {
    ref.read(pendingEmailMessageProvider.notifier).set(id);
  }
  ref.read(emailOpenRequestProvider.notifier).request();
}
