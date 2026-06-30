import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/utf16_sanitizer.dart';
import '../../../shared/widgets/adaptive_route_shell.dart';
import '../../../shared/widgets/web_content_embed.dart';

/// Full-screen preview of a generated document.
///
/// Shows the docgen HTML side-preview — which renders ANY document type
/// (docx/xlsx/pptx/pdf/md/html), since neither the web client nor a phone can
/// render Office formats natively; both just display this HTML preview — in a
/// sandboxed, zoomable web view. The Download action fetches the REAL file (the
/// user opens it in whatever app they prefer).
class DocumentPreviewPage extends ConsumerStatefulWidget {
  const DocumentPreviewPage({
    super.key,
    required this.previewHtml,
    required this.fileName,
    this.fileId,
  });

  /// The HTML side-preview emitted alongside the file.
  final String previewHtml;

  /// Display name of the real file (also used for the downloaded file).
  final String fileName;

  /// Open WebUI file id of the real file, for download. Null disables download.
  final String? fileId;

  @override
  ConsumerState<DocumentPreviewPage> createState() =>
      _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends ConsumerState<DocumentPreviewPage> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    final fileId = widget.fileId;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final api = ref.read(apiServiceProvider);
    if (fileId == null || fileId.isEmpty || api is! ApiService) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('This document can’t be downloaded.')),
      );
      return;
    }
    _downloading = true;
    try {
      final content = await api.getFileContent(fileId);
      // getFileContent returns raw base64 for non-image files (and a data: URL
      // for images) — strip the data-URL prefix if present, then decode.
      final b64 = content.startsWith('data:')
          ? content.substring(content.indexOf(',') + 1)
          : content;
      final bytes = base64Decode(b64);
      final dir = await getTemporaryDirectory();
      final safe = widget.fileName
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final file = File('${dir.path}/${safe.isEmpty ? 'document' : safe}');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(file.path, name: widget.fileName)]),
      );
    } catch (e) {
      DebugLogger.log('Failed to download document: $e', scope: 'chat/document');
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Couldn’t download this document. Please try again.'),
        ),
      );
    } finally {
      _downloading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    return AdaptiveRouteShell(
      backgroundColor: theme.surfaceBackground,
      bodySafeArea: true,
      appBar: AdaptiveAppBar(
        title: sanitizeUtf16(widget.fileName),
        actions: [
          AdaptiveAppBarAction(
            iosSymbol: 'square.and.arrow.down',
            icon: Platform.isIOS
                ? CupertinoIcons.cloud_download
                : Icons.file_download_outlined,
            onPressed: () => unawaited(_download()),
          ),
        ],
      ),
      body: SizedBox.expand(
        child: WebContentEmbed(
          source: widget.previewHtml,
          deferUntilExpanded: false,
          initiallyExpanded: true,
          showChrome: false,
          fillAvailableHeight: true,
        ),
      ),
    );
  }
}
