import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:conduit/l10n/app_localizations.dart';

import '../../core/deployment/deployment_providers.dart';
import '../../core/services/haptic_service.dart';
import '../theme/theme_extensions.dart';
import 'conduit_components.dart';
import 'themed_dialogs.dart';

/// Shows the sign-out confirmation and returns whether server connection
/// details should remain on this device. A null result means the user
/// cancelled.
///
/// A build locked to its server always keeps it: the dialog then only
/// confirms, and answers true.
Future<bool?> showSignOutOptionsDialog(BuildContext context) {
  final locked = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(deploymentPolicyProvider).isLocked;
  return ThemedDialogs.showCustom<bool>(
    context: context,
    builder: (_) => _SignOutOptionsDialog(serverKept: locked),
  );
}

class _SignOutOptionsDialog extends StatefulWidget {
  const _SignOutOptionsDialog({this.serverKept = false});

  final bool serverKept;

  @override
  State<_SignOutOptionsDialog> createState() => _SignOutOptionsDialogState();
}

class _SignOutOptionsDialogState extends State<_SignOutOptionsDialog> {
  late bool _keepServerDetails = widget.serverKept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;

    return ThemedDialogs.buildBase(
      context: context,
      title: l10n.signOut,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.signOutOptionsDescription,
            style: AppTypography.bodyMediumStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
          if (!widget.serverKept) const SizedBox(height: Spacing.sm),
          if (!widget.serverKept)
            CheckboxListTile.adaptive(
              key: const Key('sign-out-keep-server-details'),
              value: _keepServerDetails,
              onChanged: (value) {
                ConduitHaptics.selectionClick();
                setState(() => _keepServerDetails = value ?? false);
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                l10n.keepServerDetails,
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: theme.textPrimary,
                ),
              ),
              subtitle: Text(
                l10n.keepServerDetailsDescription,
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
        ],
      ),
      actions: [
        ConduitTextButton(
          text: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ConduitTextButton(
          key: const Key('sign-out-confirm'),
          text: l10n.signOut,
          onPressed: () => Navigator.of(context).pop(_keepServerDetails),
          isDestructive: true,
        ),
      ],
      scrollable: true,
    );
  }
}
