import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/locked_server.dart';
import '../../../core/providers/app_providers.dart';
import '../../auth/providers/unified_auth_providers.dart';

/// Email section — hosts the FADI inbox webapp (served by email-api at /app) in
/// a WebView. The OWUI bearer is injected into the page so it authenticates as
/// the signed-in user, and host actions the page emits (open the Gmail OAuth
/// URL, "discuss in chat") are bridged back to native via a JS handler.
class EmailTab extends ConsumerStatefulWidget {
  const EmailTab({super.key});

  @override
  ConsumerState<EmailTab> createState() => _EmailTabState();
}

class _EmailTabState extends ConsumerState<EmailTab> {
  InAppWebViewController? _controller;

  String _resolveUrl() {
    if (kEmailAppUrl.isNotEmpty) return kEmailAppUrl;
    final base =
        ref.read(activeServerProvider).asData?.value?.url ?? kLockedServerUrl;
    final trimmed =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/email/app';
  }

  Future<void> _injectToken() async {
    final controller = _controller;
    if (controller == null) return;
    final token = ref.read(authTokenProvider3);
    if (token == null || token.isEmpty) return;
    // JWTs contain no quotes/backslashes, but escape defensively anyway.
    final safe = token.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    await controller.evaluateJavascript(
      source: "window.postMessage({type:'fadi-token', token:'$safe'}, '*');",
    );
  }

  void _onHostMessage(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['type']) {
      case 'fadi-open-url':
        final url = raw['url'];
        if (url is String && url.isNotEmpty) {
          unawaited(
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          );
        }
        break;
      case 'fadi-discuss':
        // TODO(email): open a seeded OWUI chat for raw['email_id'] once the
        // discuss/seed-chat endpoint exists (Phase 4 follow-up).
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolveUrl();
    return InAppWebView(
      key: ValueKey<String>(url),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'fadiHost',
          callback: (args) {
            _onHostMessage(args.isNotEmpty ? args.first : null);
            return null;
          },
        );
      },
      onLoadStop: (controller, _) async {
        await _injectToken();
      },
    );
  }
}
