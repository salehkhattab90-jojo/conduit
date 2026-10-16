// The user's Open WebUI model-control picks for the chat's model.
//
// Mirrors the web client's Model Controls menu (`ModelControls.svelte`): the
// controls come from the model (`info.params.model_controls`), the picks are
// stored per user and per model in `ui.params.model_controls` (shared with the
// web client), and the chat request sends them (see
// `openWebUiModelControlsParam`). Offered to admins and to users whose
// `chat.controls` and `chat.params` permissions are not off, for models served
// by Open WebUI itself (not pipes, direct connections or Hermes).
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/direct_connections/providers/direct_connection_providers.dart';
import 'package:conduit_core/features/hermes/models/hermes_model.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/model_controls.dart';
import 'package:conduit_core/providers/app_providers.dart';

typedef ModelControlsReader = T Function<T>(ProviderListenable<T> provider);

/// Thrown when the server did not keep a pick (it drops `ui.params` for a user
/// without the `chat.controls` and `chat.params` permissions).
final class ModelControlsNotSavedException implements Exception {
  const ModelControlsNotSavedException();

  @override
  String toString() => 'The server did not save the model control.';
}

/// Whether model controls apply to [model] at all: only models Open WebUI
/// serves itself, as the web client offers them (no pipes, no direct
/// connections) and none of this app's own backends.
bool modelControlsApplyTo(ModelControlsReader read, Model model) {
  if (isHermesModel(model)) return false;
  if (read(directModelRegistryProvider).resolve(model) != null) return false;
  final metadata = model.metadata;
  if (metadata?['pipe'] != null) return false;
  if (metadata?['direct'] == true) return false;
  return true;
}

/// Whether the signed-in account may change model controls: admins, and users
/// whose `chat.controls` and `chat.params` permissions are not explicitly off
/// (missing means allowed, as in the web client). Hidden while the permissions
/// are unknown.
final modelControlsPermittedProvider = Provider<bool>((ref) {
  if (ref.watch(apiServiceProvider) == null) return false;
  if (ref.watch(currentUserProvider2)?.role == 'admin') return true;
  return ref
      .watch(userPermissionsProvider)
      .maybeWhen(
        data: (permissions) {
          final chat = permissions['chat'];
          if (chat is! Map) return true;
          return _allowed(chat['controls']) && _allowed(chat['params']);
        },
        orElse: () => false,
      );
});

/// The user's stored picks for every model, `{modelId: {key: option}}`.
final modelControlChoicesProvider = Provider<Map<String, Map<String, String>>>(
  (ref) =>
      ref.watch(personalizationSettingsProvider).asData?.value.modelControls ??
      const <String, Map<String, String>>{},
);

/// The controls the chat's model offers, or none when they do not apply.
final selectedModelControlsProvider = Provider<Map<String, ModelControl>>((
  ref,
) {
  final model = ref.watch(selectedModelProvider);
  if (model == null || !modelControlsApplyTo(ref.watch, model)) {
    return const <String, ModelControl>{};
  }
  return model.modelControls;
});

/// Whether the model picker shows the chat model's controls.
final modelControlsVisibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(selectedModelControlsProvider).isNotEmpty &&
      ref.watch(modelControlsPermittedProvider),
);

/// The user's picks for the chat's model that it still offers.
final selectedModelControlChoiceProvider = Provider<Map<String, String>>((
  ref,
) {
  final model = ref.watch(selectedModelProvider);
  if (model == null) return const <String, String>{};
  return applicableModelControlChoice(
    ref.watch(modelControlChoicesProvider)[model.id],
    ref.watch(selectedModelControlsProvider),
  );
});

/// Picks [option] for [model]'s control [key]; null goes back to the model's
/// default. Picks for options the model no longer offers are cleared at the
/// same time. Throws [ModelControlsNotSavedException] when the server did not
/// keep the pick.
Future<void> setModelControlOption(
  ModelControlsReader read,
  Model model,
  String key,
  String? option,
) async {
  final controls = model.modelControls;
  final control = controls[key];
  if (control == null) {
    throw ArgumentError.value(key, 'key', 'The model offers no such control');
  }
  if (option != null && !control.offers(option)) {
    throw const FormatException('This model does not offer that option.');
  }
  final stored = read(modelControlChoicesProvider)[model.id];
  final picks = <String, String?>{
    if (stored != null)
      for (final pick in stored.entries)
        if (!(controls[pick.key]?.offers(pick.value) ?? false)) pick.key: null,
    key: option,
  };
  final updated = await read(
    personalizationSettingsProvider.notifier,
  ).setModelControls(model.id, picks);
  if (updated.modelControls[model.id]?[key] != option) {
    throw const ModelControlsNotSavedException();
  }
}

bool _allowed(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'false':
      case '0':
      case 'no':
        return false;
    }
  }
  return true;
}
