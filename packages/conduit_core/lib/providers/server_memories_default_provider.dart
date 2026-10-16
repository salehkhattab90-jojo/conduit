import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/providers/app_providers.dart';

/// The active server's memory default (`features.enable_memories`): whether
/// memory is on for a user who has not switched it themselves. Null while the
/// server's configuration is unknown, which counts as off.
final serverMemoriesDefaultProvider = Provider<bool?>((ref) {
  final api = ref.watch(apiServiceProvider);
  final config = ref.watch(backendConfigProvider).asData?.value;
  return openWebUiMemoriesDefault(config, api?.serverConfig.id);
});
