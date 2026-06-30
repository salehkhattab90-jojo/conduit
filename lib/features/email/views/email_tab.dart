import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/locked_server.dart';
import '../../../core/notifications/email_open_request.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/debug_logger.dart';
import '../../auth/providers/unified_auth_providers.dart';

/// Email section — hosts the email inbox webapp (served by email-api at /app)
/// in a WebView. The OWUI bearer is injected into the page — both as a
/// localStorage 'token' (so the in-app "Discuss in chat" overlay, an iframe to
/// OWUI's chat at the same origin, authenticates) and via postMessage (for the
/// webapp itself) — so it acts as the signed-in user. The only host action the
/// page emits, opening the Gmail OAuth URL externally, is bridged via a JS handler.
class EmailTab extends ConsumerStatefulWidget {
  const EmailTab({super.key});

  @override
  ConsumerState<EmailTab> createState() => _EmailTabState();
}

class _EmailTabState extends ConsumerState<EmailTab> {
  InAppWebViewController? _controller;
  String? _injectedMode;

  String _baseUrl() {
    if (kEmailAppUrl.isNotEmpty) return kEmailAppUrl;
    final base =
        ref.read(activeServerProvider).asData?.value?.url ?? kLockedServerUrl;
    final trimmed =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/email/app';
  }

  // theme in the initial URL avoids a first-paint flash; later changes go via JS.
  String _initialUrl(String mode) {
    final u = _baseUrl();
    return '$u${u.contains('?') ? '&' : '?'}theme=$mode';
  }

  Future<void> _injectToken() async {
    final controller = _controller;
    if (controller == null) return;
    final token = ref.read(authTokenProvider3);
    if (token == null || token.isEmpty) return;
    // JWTs contain no quotes/backslashes, but escape defensively anyway.
    final safe = token.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    // Seed localStorage 'token' (the OWUI session key) so the embedded "Discuss
    // in chat" overlay — an iframe to OWUI chat at the same origin — authenticates;
    // OWUI's own iframe relies on this, and postMessage alone leaves the chat
    // logged-out. The webapp's own bearer resolution reads localStorage 'token' too.
    await controller.evaluateJavascript(
      source:
          "try{localStorage.setItem('token','$safe');}catch(e){}"
          "window.postMessage({type:'email-token', token:'$safe'}, '*');",
    );
  }

  Future<void> _injectTheme(String mode) async {
    final controller = _controller;
    if (controller == null) return;
    _injectedMode = mode;
    await controller.evaluateJavascript(
      source: "window.postMessage({type:'email-theme', mode:'$mode'}, '*');",
    );
  }

  // Deep-link from a tapped push notification: ask the webapp to open that
  // specific message (its `id` is the same email_message id the webapp uses).
  Future<void> _injectOpenMessage(String id) async {
    final controller = _controller;
    if (controller == null) return;
    final safe = id.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    await controller.evaluateJavascript(
      source: "window.postMessage({type:'email-open', id:'$safe'}, '*');",
    );
  }

  void _onHostMessage(dynamic raw) {
    if (raw is! Map) return;
    // The only host action the webapp emits: open the Gmail OAuth URL in the
    // system browser (the OAuth flow can't complete inside the embedded webview).
    // "Discuss in chat" is handled in-app by the webapp (an overlay iframe), not
    // bridged to native.
    if (raw['type'] == 'email-open-url') {
      final url = raw['url'];
      if (url is String && url.isNotEmpty) {
        unawaited(
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        );
      }
      return;
    }
    // Attachment download: a blob URL + `<a download>` can't save a file inside a
    // WebView, so the webapp hands the request to us. We fetch the bytes with the
    // same bearer the page uses and open the system share/save sheet.
    if (raw['type'] == 'email-download') {
      final url = raw['url'];
      if (url is String && url.isNotEmpty) {
        final filename = raw['filename'];
        final contentType = raw['contentType'];
        unawaited(
          _downloadAttachment(
            url,
            filename is String && filename.isNotEmpty ? filename : 'attachment',
            contentType is String && contentType.isNotEmpty
                ? contentType
                : null,
          ),
        );
      }
      return;
    }
  }

  // Fetch an inbound-attachment URL with the active bearer and hand the real file
  // to the OS share/save sheet — the WebView can't persist a download itself.
  Future<void> _downloadAttachment(
    String url,
    String filename,
    String? contentType,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final token = ref.read(authTokenProvider3);
      final resp = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 2),
          headers: <String, String>{
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('empty attachment body');
      }
      final dir = await getTemporaryDirectory();
      final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final file = File('${dir.path}/${safe.isEmpty ? 'attachment' : safe}');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(
              file.path,
              name: filename,
              mimeType: contentType,
            ),
          ],
        ),
      );
    } catch (e) {
      DebugLogger.log(
        'Email attachment download failed: $e',
        scope: 'email/download',
      );
      messenger?.showSnackBar(
        const SnackBar(content: Text('Download failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // A notification tapped while this tab is already loaded: open the message.
    ref.listen<String?>(pendingEmailMessageProvider, (prev, next) {
      if (next != null && next.isNotEmpty && _controller != null) {
        unawaited(_injectOpenMessage(next));
        ref.read(pendingEmailMessageProvider.notifier).clear();
      }
    });
    final mode =
        Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
    // Re-sync theme when the app brightness changes after the page has loaded.
    if (_injectedMode != null && _injectedMode != mode) {
      unawaited(_injectTheme(mode));
    }
    return InAppWebView(
      // Key on the base URL (stable across theme changes) so the webview isn't
      // recreated when the theme toggles — those go through postMessage instead.
      key: ValueKey<String>(_baseUrl()),
      initialUrlRequest: URLRequest(url: WebUri(_initialUrl(mode))),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'emailHost',
          callback: (args) {
            _onHostMessage(args.isNotEmpty ? args.first : null);
            return null;
          },
        );
      },
      onLoadStop: (controller, _) async {
        await _injectToken();
        await _injectTheme(mode);
        // A push deep-link may have stashed a message to open on first load.
        final pending = ref.read(pendingEmailMessageProvider);
        if (pending != null && pending.isNotEmpty) {
          await _injectOpenMessage(pending);
          ref.read(pendingEmailMessageProvider.notifier).clear();
        }
      },
    );
  }
}
