import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:conduit/l10n/app_localizations.dart';

import '../../shared/theme/theme_extensions.dart';
import '../../shared/widgets/conduit_components.dart';
import '../../shared/widgets/themed_dialogs.dart';
import '../utils/debug_logger.dart';
import 'navigation_service.dart';

/// A single OWUI `confirmation` event flowing through [ConfirmationCoordinator].
///
/// Its [future] completes **exactly once** with the human's decision: `true`
/// only from a real Confirm tap; `false` on Cancel, back/dismiss, stream
/// teardown, missing navigator context, or any error — fail-closed by design,
/// mirroring the backend (`send_email` sends only on a truthy ack). First
/// writer wins, so a late user tap after a teardown cancel is a no-op.
class ConfirmationRequest {
  ConfirmationRequest(this.data);

  /// The `data` payload of the confirmation event (`title`, `message`, and
  /// optional `confirm_text` / `cancel_text`).
  final Map<String, dynamic> data;

  final Completer<bool> _completer = Completer<bool>();
  bool _resolved = false;
  VoidCallback? _dismiss;

  /// Resolves once with the decision. Attach the ack here.
  Future<bool> get future => _completer.future;

  /// True once the request has been answered/cancelled — the coordinator skips
  /// presenting an entry that was cancelled while still queued (no ghost dialog).
  bool get isResolved => _resolved;

  void _resolve(bool value) {
    if (_resolved) return;
    _resolved = true;
    if (!_completer.isCompleted) _completer.complete(value);
  }

  /// Cancel fail-closed (stream teardown / navigate-away). Resolves the future
  /// to `false` if not already answered and dismisses the dialog if it is on
  /// screen — so the backend never blocks to its 300s timeout.
  void cancel() {
    _resolve(false);
    final dismiss = _dismiss;
    if (dismiss != null) {
      try {
        dismiss();
      } catch (_) {}
    }
  }
}

/// Builds and shows the dialog for a request, returning the human's decision.
typedef ConfirmationPresenter =
    Future<bool> Function(BuildContext context, ConfirmationRequest request);

/// App-global, serial runner for OWUI `confirmation` events.
///
/// Exactly one confirmation dialog is on screen app-wide, ever — confirmations
/// from any chat/stream enqueue here and are shown strictly FIFO, one at a
/// time. This is deliberately app-scoped (not per-stream) so two concurrent
/// streams can never stack two native dialogs. Presentation goes through the
/// single root navigator via [NavigationService].
class ConfirmationCoordinator {
  ConfirmationCoordinator._();

  static final ConfirmationCoordinator instance = ConfirmationCoordinator._();

  final Queue<ConfirmationRequest> _queue = Queue<ConfirmationRequest>();
  bool _running = false;

  /// Root-navigator context lookup. Overridable in tests.
  @visibleForTesting
  BuildContext? Function() contextProvider = () => NavigationService.context;

  /// Dialog presenter. Overridable in tests to avoid a real navigator.
  @visibleForTesting
  ConfirmationPresenter presenter = defaultConfirmationPresenter;

  /// Enqueue a confirmation. Returns its [ConfirmationRequest]; the caller
  /// awaits [ConfirmationRequest.future] for the decision and may call
  /// [ConfirmationRequest.cancel] on teardown.
  ConfirmationRequest request(Map<String, dynamic> data) {
    final req = ConfirmationRequest(data);
    _queue.add(req);
    unawaited(_drain());
    return req;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final req = _queue.removeFirst();
        if (req.isResolved) {
          // Cancelled while queued — never present a ghost dialog.
          continue;
        }
        final ctx = contextProvider();
        if (ctx == null) {
          req._resolve(false); // fail closed: no UI surface
          continue;
        }
        try {
          final result = await presenter(ctx, req);
          req._resolve(result);
        } catch (e) {
          DebugLogger.log(
            'confirmation presenter failed: $e',
            scope: 'streaming/helper',
          );
          req._resolve(false);
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Test hook: drop any queued requests (does not resolve them).
  @visibleForTesting
  void resetForTest() {
    _queue.clear();
    _running = false;
    contextProvider = () => NavigationService.context;
    presenter = defaultConfirmationPresenter;
  }
}

/// Default presenter: a scrollable, inert, themed confirmation dialog that
/// mirrors the web `ConfirmDialog` (title + markdown-styled body + Cancel /
/// Confirm, with the body scrolling when tall so the buttons stay visible).
Future<bool> defaultConfirmationPresenter(
  BuildContext context,
  ConfirmationRequest request,
) async {
  final data = request.data;
  final l10n = AppLocalizations.of(context);

  final rawTitle = data['title']?.toString().trim() ?? '';
  final title = rawTitle.isNotEmpty ? rawTitle : (l10n?.confirm ?? 'Confirm');
  final message = data['message']?.toString() ?? '';
  final confirmText =
      data['confirm_text']?.toString() ?? l10n?.confirm ?? 'Confirm';
  final cancelText =
      data['cancel_text']?.toString() ?? l10n?.cancel ?? 'Cancel';

  final result = await ThemedDialogs.showCustom<bool>(
    context: context,
    barrierDismissible: false, // force an explicit choice
    builder: (dialogCtx) {
      // Let teardown pop THIS route (back/tap-out is disabled above).
      request._dismiss = () {
        final nav = Navigator.of(dialogCtx);
        if (nav.canPop()) nav.pop(false);
      };
      return ThemedDialogs.buildBase(
        context: dialogCtx,
        title: title,
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogCtx).size.height * 0.6,
            maxWidth: double.maxFinite,
          ),
          child: SingleChildScrollView(
            child: ConfirmationMessageBody(message: message),
          ),
        ),
        actions: [
          ConduitTextButton(
            text: cancelText,
            onPressed: () => Navigator.of(dialogCtx).pop(false),
          ),
          ConduitTextButton(
            text: confirmText,
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            isPrimary: true,
          ),
        ],
      );
    },
  );
  request._dismiss = null;
  return result ?? false;
}

/// Inert renderer for the confirmation body.
///
/// The body is model/email-derived and therefore untrusted, so it is NEVER run
/// through the app's full markdown pipeline (which can route Mermaid/ChartJS/
/// HTML through a WebView and load remote images). This widget emits only bold
/// labels, `>` blockquotes, and literal text — no links, images, HTML, WebView,
/// or gesture recognizers — and inherits ambient [Directionality] per line, so
/// Arabic/mixed content renders correctly and a quoted body line can never
/// impersonate a header.
class ConfirmationMessageBody extends StatelessWidget {
  const ConfirmationMessageBody({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final baseStyle = DefaultTextStyle.of(context).style;
    final quoteColor = theme.dividerColor;

    final lines = message.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }
      final trimmedLeft = line.trimLeft();
      if (trimmedLeft == '>' || trimmedLeft.startsWith('> ')) {
        final quoted = trimmedLeft.replaceFirst(RegExp(r'^>\s?'), '');
        children.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: quoteColor, width: 2)),
            ),
            child: Text.rich(
              _inlineBold(quoted, baseStyle.copyWith(color: theme.textSecondary)),
              textAlign: TextAlign.start,
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text.rich(_inlineBold(line, baseStyle), textAlign: TextAlign.start),
          ),
        );
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Renders `**bold**` spans; everything else is literal text. No tappable spans,
/// no recognizers — purely inert [TextSpan]s.
TextSpan _inlineBold(String line, TextStyle base) {
  final parts = line.split('**');
  final spans = <TextSpan>[];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    final isBold = i.isOdd; // text between the 1st and 2nd `**` etc.
    spans.add(
      TextSpan(
        text: parts[i],
        style: isBold ? base.copyWith(fontWeight: FontWeight.w600) : base,
      ),
    );
  }
  return TextSpan(style: base, children: spans);
}
