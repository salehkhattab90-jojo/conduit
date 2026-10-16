import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit_core/features/chat/providers/model_controls_provider.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/model_controls.dart';

import '../../../shared/widgets/adaptive_selection_sheet.dart';

/// What a model control's row says: the picked option, or "Default" with the
/// model's default option when it has one (as the web client's menu does).
String modelControlSummary(
  AppLocalizations l10n,
  ModelControl control,
  String? pick,
) {
  final picked = control.option(pick);
  if (picked != null) return picked.label;
  return _defaultLabel(l10n, control);
}

String _defaultLabel(AppLocalizations l10n, ModelControl control) {
  final fallback = control.option(control.defaultOption);
  return fallback == null
      ? l10n.defaultLabel
      : '${l10n.defaultLabel} · ${fallback.label}';
}

/// Lets the user pick an option of [model]'s [control] (or go back to the
/// model's default) and stores it in their Open WebUI settings.
Future<void> showModelControlPicker(
  BuildContext context,
  WidgetRef ref,
  Model model,
  ModelControl control,
) async {
  final l10n = AppLocalizations.of(context)!;
  final current = ref.read(selectedModelControlChoiceProvider)[control.key];
  // Null stands for the model's default.
  final items = <({String? value, String label})>[
    (value: null, label: _defaultLabel(l10n, control)),
    for (final option in control.options)
      (value: option.value, label: option.label),
  ];
  final picked = await showAdaptiveSelectionSheet<({String? value})>(
    context: context,
    builder: (sheetContext) => AdaptiveSelectionSheet(
      title: control.label,
      description: control.description,
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return AdaptiveSelectionTile(
          title: item.label,
          selected: item.value == current,
          onTap: () => Navigator.of(sheetContext).pop((value: item.value)),
        );
      },
    ),
  );
  if (!context.mounted || picked == null || picked.value == current) return;
  try {
    await setModelControlOption(ref.read, model, control.key, picked.value);
  } on ModelControlsNotSavedException {
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: l10n.authForbidden,
      type: AdaptiveSnackBarType.error,
    );
  } catch (_) {
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: l10n.errorMessage,
      type: AdaptiveSnackBarType.error,
    );
  }
}
