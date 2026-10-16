import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conduit_core/features/chat/utils/document_deliveries.dart';
import 'package:conduit_core/features/terminal/controllers/terminal_controller_gateways.dart'
    show safeTerminalFileName;
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:conduit_core/utils/debug_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/utf16_sanitizer.dart';
import '../../../shared/widgets/adaptive_route_shell.dart';
import '../../../shared/widgets/markdown/renderer/pdf_inline_view.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/platform_ui/vocabulary.dart';
import '../../../shared/widgets/web_content_embed.dart';

/// Full-screen preview of a generated document, with the download of its
/// real file.
///
/// A structured preview (a rendered PDF of the real file) is fetched with the
/// session's authentication and shown by [PdfInlineView]; a legacy HTML
/// preview or an HTML artifact renders in the sandboxed [WebContentEmbed].
/// Download fetches the real file through the files API and hands it to the
/// share sheet, so it opens in whatever app the user prefers; with no real
/// file (an artifact, or a preview whose file did not arrive) there is no
/// Download action.
class DocumentPreviewPage extends ConsumerStatefulWidget {
  const DocumentPreviewPage({
    super.key,
    required this.delivery,
    required this.title,
  });

  final DocumentDelivery delivery;
  final String title;

  @override
  ConsumerState<DocumentPreviewPage> createState() =>
      _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends ConsumerState<DocumentPreviewPage> {
  bool _downloading = false;

  Future<void> _download(String fileId) async {
    if (_downloading) return;
    final l10n = AppLocalizations.of(context)!;
    final api = ref.read(apiServiceProvider);
    final worker = ref.read(workerManagerProvider);
    _downloading = true;
    try {
      if (api is! ApiService) throw StateError('No API session');
      final content = await api.getFileContent(fileId);
      // Raw base64 for documents; a data URL for images.
      final encoded = content.startsWith('data:')
          ? content.substring(content.indexOf(',') + 1)
          : content;
      final bytes = await worker.schedule<String, Uint8List>(
        _decodeDocumentBase64,
        encoded,
        debugLabel: 'document_download_decode',
      );
      final directory = await getTemporaryDirectory();
      final fileName = safeTerminalFileName(widget.title);
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path, name: fileName)]),
      );
    } catch (error) {
      DebugLogger.error(
        'document-download-failed',
        scope: 'chat/document',
        error: error,
      );
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: l10n.terminalDownloadFailed,
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      _downloading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final delivery = widget.delivery;
    final fileId = delivery.fileId;
    final previewUrl = delivery.previewUrl;
    final previewHtml = delivery.previewHtml;

    final Widget body;
    if (previewUrl != null) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Center(
          child: PdfInlineView(
            url: previewUrl,
            label: delivery.previewName ?? widget.title,
          ),
        ),
      );
    } else if (previewHtml != null) {
      body = WebContentEmbed(
        source: previewHtml,
        deferUntilExpanded: false,
        initiallyExpanded: true,
        showChrome: false,
        fillAvailableHeight: true,
      );
    } else {
      body = const SizedBox.shrink();
    }

    return AdaptiveRouteShell(
      backgroundColor: theme.surfaceBackground,
      bodySafeArea: true,
      appBar: AdaptiveAppBar(
        title: sanitizeUtf16(widget.title),
        actions: [
          if (fileId != null)
            AdaptiveAppBarAction(
              iosSymbol: 'square.and.arrow.down',
              icon: Icons.file_download_outlined,
              onPressed: () => unawaited(_download(fileId)),
            ),
        ],
      ),
      body: SizedBox.expand(child: body),
    );
  }
}

Uint8List _decodeDocumentBase64(String raw) =>
    base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
