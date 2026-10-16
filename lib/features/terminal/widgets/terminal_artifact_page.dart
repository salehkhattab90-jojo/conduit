import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/platform_page_route.dart';
import '../../../shared/utils/utf16_sanitizer.dart';
import '../../../shared/widgets/adaptive_route_shell.dart';
import '../../../shared/widgets/platform_ui/platform_ui.dart';
import '../../../shared/widgets/platform_ui/vocabulary.dart';
import '../../../shared/widgets/web_content_embed.dart';
import '../models/terminal_models.dart';

/// The HTML or SVG markup of [preview] when it is a web artifact to show
/// rendered, or null.
///
/// The terminal read endpoint reports text files as `text/plain` whatever
/// their type, so an artifact is recognised by its extension, and an
/// extensionless or mislabelled one by how its markup starts. SVG can arrive
/// as bytes (`image/svg+xml`) and is then decoded.
///
/// Only markup (starting with `<`) is returned: a bare URL would make
/// [WebContentEmbed] load a remote page outside its sandbox.
String? terminalWebArtifactSource(TerminalFileReadResult preview) {
  final name = preview.fileName.toLowerCase();
  final contentType = preview.contentType.toLowerCase();
  final isHtml =
      name.endsWith('.html') ||
      name.endsWith('.htm') ||
      contentType.startsWith('text/html');
  final isSvg =
      name.endsWith('.svg') || contentType.startsWith('image/svg+xml');

  var source = preview.text;
  if (source == null && (isHtml || isSvg) && preview.bytes != null) {
    try {
      source = utf8.decode(preview.bytes!);
    } on FormatException {
      return null;
    }
  }
  if (source == null) return null;

  final head = source.trimLeft().toLowerCase();
  if (!head.startsWith('<')) return null;
  if (isHtml || isSvg) return source;
  if (head.startsWith('<!doctype html') ||
      head.startsWith('<html') ||
      head.startsWith('<svg')) {
    return source;
  }
  return null;
}

/// Pushes [TerminalArtifactPage] full screen over the app chrome.
Future<void> pushTerminalArtifactPage(
  BuildContext context, {
  required String title,
  required String source,
  Future<void> Function()? onDownload,
  void Function(ModalRoute<dynamic> route)? onShown,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = buildPlatformPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => TerminalArtifactPage(
      title: title,
      source: source,
      onDownload: onDownload,
    ),
  );
  onShown?.call(route);
  await navigator.push(route);
}

/// A terminal workspace HTML/SVG file rendered live in the sandboxed
/// [WebContentEmbed], with a Preview / Source switch and a Download action.
class TerminalArtifactPage extends StatefulWidget {
  const TerminalArtifactPage({
    super.key,
    required this.title,
    required this.source,
    this.onDownload,
  });

  final String title;

  /// HTML or SVG markup (see [terminalWebArtifactSource]).
  final String source;

  /// Null hides the Download action.
  final Future<void> Function()? onDownload;

  @override
  State<TerminalArtifactPage> createState() => _TerminalArtifactPageState();
}

class _TerminalArtifactPageState extends State<TerminalArtifactPage> {
  bool _showSource = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;
    final onDownload = widget.onDownload;

    return AdaptiveRouteShell(
      backgroundColor: theme.surfaceBackground,
      bodySafeArea: true,
      appBar: AdaptiveAppBar(
        title: sanitizeUtf16(widget.title),
        actions: [
          if (onDownload != null)
            AdaptiveAppBarAction(
              iosSymbol: 'square.and.arrow.down',
              icon: Icons.file_download_outlined,
              onPressed: () => unawaited(onDownload()),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.sm,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AdaptiveValueSegmentedControl<bool>(
                value: _showSource,
                onChanged: (value) => setState(() => _showSource = value),
                segments: [
                  AdaptiveSegment<bool>(
                    value: false,
                    label: Text(l10n.preview),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                  ),
                  AdaptiveSegment<bool>(
                    value: true,
                    label: Text(l10n.code),
                    icon: const Icon(Icons.code, size: 16),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _showSource
                ? DecoratedBox(
                    decoration: BoxDecoration(color: theme.codeBackground),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Text(
                        sanitizeUtf16(widget.source),
                        style: AppTypography.codeStyle.copyWith(
                          color: theme.codeText,
                        ),
                      ),
                    ),
                  )
                : WebContentEmbed(
                    source: widget.source,
                    deferUntilExpanded: false,
                    initiallyExpanded: true,
                    showChrome: false,
                    fillAvailableHeight: true,
                  ),
          ),
        ],
      ),
    );
  }
}
