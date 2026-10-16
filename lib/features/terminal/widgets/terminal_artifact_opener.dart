import 'dart:async';

import 'package:conduit_core/features/terminal/providers/terminal_artifact_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/utf16_sanitizer.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../controllers/terminal_controller_gateways.dart';
import '../models/terminal_models.dart';
import '../providers/terminal_providers.dart';
import 'terminal_artifact_page.dart';
import 'terminal_files_section.dart';

/// Opens a file a chat message showed with `display_file`, fetched live from
/// its terminal workspace: HTML and SVG render full screen, other files open
/// in the Files panel's preview dialog. Both offer the download.
Future<void> openTerminalArtifact(
  BuildContext context,
  WidgetRef ref,
  TerminalArtifactRef artifact,
) async {
  final l10n = AppLocalizations.of(context)!;
  final service = ref.read(terminalServiceProvider);
  final sessionScopeId = ref.read(terminalSessionScopeIdProvider);

  void report(String message) {
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.error,
    );
  }

  TerminalServerInfo? server;
  if (service != null) {
    try {
      server = resolveTerminalServerForArtifact(
        artifact,
        servers: await ref.read(terminalAvailableServersProvider.future),
        selected: await ref.read(terminalSelectedServerProvider.future),
      );
    } catch (_) {
      server = null;
    }
  }
  if (!context.mounted) return;
  if (service == null || server == null) {
    report(l10n.terminalFailedToLoadFiles);
    return;
  }
  final terminal = server;

  Future<void> download() async {
    try {
      final downloaded = await service.downloadFile(
        terminal,
        artifact.path,
        sessionScopeId: sessionScopeId,
      );
      await const DefaultTerminalBrowserPlatformGateway().saveDownload(
        downloaded,
      );
    } catch (_) {
      report(l10n.terminalDownloadFailed);
    }
  }

  final TerminalFileReadResult preview;
  try {
    preview = await service.readFile(
      terminal,
      artifact.path,
      sessionScopeId: sessionScopeId,
    );
  } catch (_) {
    report(l10n.terminalFailedToLoadFiles);
    return;
  }
  if (!context.mounted) return;

  if (terminalWebArtifactSource(preview) case final source?) {
    await pushTerminalArtifactPage(
      context,
      title: artifact.name,
      source: source,
      onDownload: download,
    );
    return;
  }

  await ThemedDialogs.showCustom<void>(
    context: context,
    builder: (dialogContext) => ThemedDialogs.buildBase(
      context: dialogContext,
      title: sanitizeUtf16(artifact.name),
      content: terminalFilePreviewContent(
        dialogContext,
        l10n,
        preview,
        page: artifact.page,
      ),
      actions: [
        ConduitTextButton(
          text: l10n.close,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        ConduitTextButton(
          text: l10n.download,
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(download());
          },
          isPrimary: true,
        ),
      ],
    ),
  );
}
