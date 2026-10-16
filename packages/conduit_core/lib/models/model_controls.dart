// Open WebUI 0.12 model controls: per-model choices an admin offers (for
// example "Thinking: Off / On"), each option expanding into custom params on
// the server.
//
// The model list carries them as `info.params.model_controls`
// (`{key: {label, description?, default?, display?, options: {opt: {label}}}}`,
// server `utils/models.py` `public_model_params`). A user's picks live per
// model in their settings at `ui.params.model_controls` (`{modelId: {key:
// opt}}`), shared with the web client, and a chat request carries them as
// `params.model_controls`. The server answers 400 to an option the model no
// longer offers, so picks are checked against the model before sending.
import 'package:meta/meta.dart';

/// The request and settings key for model controls.
const String kModelControlsParam = 'model_controls';

/// One option of a [ModelControl].
@immutable
class ModelControlOption {
  const ModelControlOption({required this.value, required this.label});

  /// The key the request sends.
  final String value;
  final String label;
}

/// One control a model offers, as the server describes it.
@immutable
class ModelControl {
  const ModelControl({
    required this.key,
    required this.label,
    required this.options,
    this.description,
    this.defaultOption,
    this.display = 'menu',
  });

  final String key;
  final String label;
  final String? description;

  /// The option the server applies when the user has picked none, if any.
  final String? defaultOption;

  /// `menu` or `slider`; both are offered as a list of options here.
  final String display;

  /// In the server's order.
  final List<ModelControlOption> options;

  bool offers(String option) => options.any((entry) => entry.value == option);

  ModelControlOption? option(String? value) {
    if (value == null) return null;
    for (final entry in options) {
      if (entry.value == value) return entry;
    }
    return null;
  }
}

/// The controls in a model's `info.params.model_controls`, in the server's
/// order. Malformed entries (no label, no options) are skipped.
Map<String, ModelControl> parseModelControls(Object? raw) {
  if (raw is! Map || raw.isEmpty) return const <String, ModelControl>{};
  final controls = <String, ModelControl>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    final value = entry.value;
    if (key.isEmpty || value is! Map) continue;
    final label = _text(value['label']);
    final rawOptions = value['options'];
    if (label == null || rawOptions is! Map) continue;
    final options = <ModelControlOption>[];
    for (final option in rawOptions.entries) {
      final optionKey = option.key.toString().trim();
      final optionValue = option.value;
      final optionLabel = optionValue is Map
          ? _text(optionValue['label'])
          : null;
      if (optionKey.isEmpty || optionLabel == null) continue;
      options.add(ModelControlOption(value: optionKey, label: optionLabel));
    }
    if (options.isEmpty) continue;
    final defaultOption = _text(value['default']);
    controls[key] = ModelControl(
      key: key,
      label: label,
      description: _text(value['description']),
      defaultOption:
          defaultOption != null && options.any((o) => o.value == defaultOption)
          ? defaultOption
          : null,
      display: _text(value['display']) ?? 'menu',
      options: List<ModelControlOption>.unmodifiable(options),
    );
  }
  return Map<String, ModelControl>.unmodifiable(controls);
}

/// The user's stored picks, `{modelId: {key: option}}`, out of a raw
/// `model_controls` settings value. Non-string picks are dropped.
Map<String, Map<String, String>> parseModelControlChoices(Object? raw) {
  if (raw is! Map || raw.isEmpty) {
    return const <String, Map<String, String>>{};
  }
  final choices = <String, Map<String, String>>{};
  for (final entry in raw.entries) {
    final modelId = entry.key.toString();
    final picks = entry.value;
    if (modelId.isEmpty || picks is! Map) continue;
    final parsed = <String, String>{
      for (final pick in picks.entries)
        if (pick.value is String && (pick.value as String).isNotEmpty)
          pick.key.toString(): pick.value as String,
    };
    if (parsed.isNotEmpty) {
      choices[modelId] = Map<String, String>.unmodifiable(parsed);
    }
  }
  return Map<String, Map<String, String>>.unmodifiable(choices);
}

/// [choice] limited to what [controls] still offers: picks for a removed
/// control or an option the control no longer has are dropped, so a request
/// never names one (the server rejects those with 400).
Map<String, String> applicableModelControlChoice(
  Map<String, String>? choice,
  Map<String, ModelControl> controls,
) {
  if (choice == null || choice.isEmpty || controls.isEmpty) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final pick in choice.entries)
      if (controls[pick.key]?.offers(pick.value) ?? false) pick.key: pick.value,
  };
}

/// The controls in a chat request's `model_item` (`info.params.model_controls`).
Map<String, ModelControl> modelControlsOfModelItem(Object? modelItem) {
  if (modelItem is! Map) return const <String, ModelControl>{};
  final info = modelItem['info'];
  final params = info is Map ? info['params'] : null;
  return parseModelControls(params is Map ? params['model_controls'] : null);
}

/// The `params.model_controls` value of a chat request: for each model the
/// request is for, the user's stored picks it still offers. Models without a
/// pick left are omitted; null when none is left at all.
///
/// [storedChoices] is the raw `ui.params.model_controls` settings value;
/// [modelItems] maps each target model id to its `model_item`.
Map<String, Map<String, String>>? openWebUiModelControlsParam({
  required Object? storedChoices,
  required Map<String, Object?> modelItems,
}) {
  final stored = parseModelControlChoices(storedChoices);
  if (stored.isEmpty) return null;
  final result = <String, Map<String, String>>{};
  for (final entry in modelItems.entries) {
    final picks = applicableModelControlChoice(
      stored[entry.key],
      modelControlsOfModelItem(entry.value),
    );
    if (picks.isNotEmpty) result[entry.key] = picks;
  }
  return result.isEmpty ? null : result;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
