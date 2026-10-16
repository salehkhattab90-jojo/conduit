import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/email/email_app_config.dart';
import 'package:conduit_core/features/email/providers/email_providers.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/utils/debug_logger.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/sidebar_layout_contract.dart';
import '../services/email_webview_storage.dart';

/// The Email sidebar tab: the server's email web app in a WebView, signed in
/// as the current account.
///
/// The WebView is created the first time the tab is shown and then kept, one
/// per (account, web app URL). The session token reaches only the web app's
/// own origin: a document-start script seeds `localStorage.token` there (the
/// web app and its same-origin "Discuss" chat read it), and an `email-token`
/// message follows once a load on that origin has finished. Requests from the
/// page are accepted only from its main frame on that origin.
class EmailTab extends ConsumerStatefulWidget {
  const EmailTab({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<EmailTab> createState() => _EmailTabState();
}

/// Identity of one WebView instance.
typedef _EmailSession = ({String accountId, Uri appUri, String origin});

class _EmailTabState extends ConsumerState<EmailTab> {
  /// The session the WebView was (or is being) created for. Null until the
  /// tab is first shown, so a hidden tab costs nothing.
  _EmailSession? _session;
  bool _storageReady = false;
  int _generation = 0;
  bool _loadFailed = false;

  InAppWebViewController? _controller;

  /// Origin of the document that finished loading, when it is the web app.
  bool _pageReady = false;
  String? _postedThemeMode;
  String? _seededToken;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(pendingEmailMessageProvider, (_, next) {
      if (next != null) unawaited(_deliverPendingMessage());
    });
    ref.listenManual<String?>(authTokenProvider3, (_, _) {
      final session = _session;
      final token = session == null ? null : _tokenFor(session);
      if (token != null && token != _seededToken) {
        unawaited(_reseedToken(session!, token));
      }
    });
  }

  _EmailSession? _resolveSession() {
    final api = ref.watch(apiServiceProvider);
    if (api == null) return null;
    final appUri = resolveEmailAppUri(serverUrl: api.serverConfig.url);
    final origin = emailOriginOf(appUri);
    if (appUri == null || origin == null) return null;
    return (accountId: api.serverConfig.id, appUri: appUri, origin: origin);
  }

  /// The bearer the active API client holds for [session], or null when that
  /// client now belongs to another account or address. Reading the token from
  /// the same client that names the server keeps one account's token from
  /// reaching another server's page mid-switch.
  String? _tokenFor(_EmailSession session) {
    final api = ref.read(apiServiceProvider);
    if (api == null || api.serverConfig.id != session.accountId) return null;
    if (resolveEmailAppUri(serverUrl: api.serverConfig.url) != session.appUri) {
      return null;
    }
    final token = api.authToken;
    return token == null || token.isEmpty ? null : token;
  }

  void _activate(_EmailSession session) {
    if (_session == session) return;
    _session = session;
    _storageReady = false;
    _resetPage();
    final storage = ref.read(emailWebViewStorageProvider);
    unawaited(
      storage
          .prepare(accountId: session.accountId, origin: session.origin)
          .whenComplete(() {
            if (!mounted || _session != session) return;
            setState(() => _storageReady = true);
          }),
    );
  }

  void _resetPage() {
    _controller = null;
    _pageReady = false;
    _postedThemeMode = null;
    _seededToken = null;
    _loadFailed = false;
  }

  void _retry() {
    setState(() {
      _generation++;
      _resetPage();
    });
  }

  Future<void> _evaluate(String source) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: source);
    } catch (error) {
      DebugLogger.warning(
        'email-webview-script-failed',
        scope: 'email/webview',
        data: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _onLoadStop(_EmailSession session, WebUri? url) async {
    if (_session != session) return;
    _pageReady = isEmailOrigin(url?.uriValue, session.origin);
    if (!_pageReady) return;
    final token = _tokenFor(session);
    if (token != null) {
      _seededToken = token;
      await _evaluate(
        emailTokenMessageScript(origin: session.origin, token: token),
      );
    }
    if (!mounted) return;
    await _postTheme(session, dark: _isDark(context));
    await _deliverPendingMessage();
  }

  Future<void> _postTheme(_EmailSession session, {required bool dark}) async {
    final mode = emailThemeMode(dark: dark);
    if (!_pageReady || _postedThemeMode == mode) return;
    _postedThemeMode = mode;
    await _evaluate(
      emailThemeMessageScript(origin: session.origin, dark: dark),
    );
  }

  Future<void> _deliverPendingMessage() async {
    final session = _session;
    if (session == null || !_pageReady) return;
    final id = ref.read(pendingEmailMessageProvider);
    if (id == null) return;
    ref.read(pendingEmailMessageProvider.notifier).clear();
    await _evaluate(emailOpenMessageScript(origin: session.origin, id: id));
  }

  /// The account's token changed without changing the account (a fresh
  /// sign-in): update the document-start script for later loads and hand the
  /// live page the new token.
  Future<void> _reseedToken(_EmailSession session, String token) async {
    final controller = _controller;
    if (_session != session || controller == null) return;
    _seededToken = token;
    try {
      await controller.removeAllUserScripts();
      await controller.addUserScript(userScript: _tokenScript(session, token));
    } catch (error) {
      DebugLogger.warning(
        'email-webview-user-script-failed',
        scope: 'email/webview',
        data: {'errorType': error.runtimeType.toString()},
      );
    }
    if (!_pageReady) return;
    await _evaluate(emailTokenSeedScript(origin: session.origin, token: token));
    await _evaluate(
      emailTokenMessageScript(origin: session.origin, token: token),
    );
  }

  UserScript _tokenScript(_EmailSession session, String token) => UserScript(
    source: emailTokenSeedScript(origin: session.origin, token: token),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
    allowedOriginRules: _originRules(session.origin),
  );

  /// Android takes origin rules (`scheme://host[:port]`); Apple platforms
  /// evaluate the same list as regular expressions.
  static Set<String> _originRules(String origin) =>
      Platform.isAndroid ? {origin} : {emailOriginPattern(origin)};

  Future<bool?> _onHostCall(
    _EmailSession session,
    JavaScriptHandlerFunctionData data,
  ) async {
    if (_session != session ||
        !isAllowedEmailHostCall(
          isMainFrame: data.isMainFrame,
          frameOrigin: data.origin.uriValue,
          requestUrl: data.requestUrl.uriValue,
          expectedOrigin: session.origin,
        )) {
      DebugLogger.warning('email-host-call-rejected', scope: 'email/webview');
      return false;
    }
    final message = EmailHostMessage.parse(
      data.args.isEmpty ? null : data.args.first,
      expectedOrigin: session.origin,
    );
    switch (message) {
      case EmailOpenUrlRequest(:final url):
        unawaited(_launchExternally(url));
        return true;
      case EmailDownloadRequest():
        unawaited(_download(message));
        return true;
      case null:
        DebugLogger.warning(
          'email-host-message-rejected',
          scope: 'email/webview',
        );
        return false;
    }
  }

  Future<void> _launchExternally(Uri url) async {
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } on PlatformException catch (error) {
      DebugLogger.warning(
        'email-open-url-failed',
        scope: 'email/webview',
        data: {'code': error.code},
      );
    }
  }

  /// Saves an attachment the web app cannot save itself: fetched through the
  /// app's own API client (the server's TLS settings apply and the bearer
  /// goes only to the server's origin), then offered through the share sheet.
  Future<void> _download(EmailDownloadRequest request) async {
    final api = ref.read(apiServiceProvider);
    final shareOrigin = _shareOrigin();
    try {
      if (api == null) throw StateError('no API client');
      final response = await api.dio.getUri<List<int>>(
        request.url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 2),
          headers: const <String, String>{'Accept': '*/*'},
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('empty attachment body');
      }
      final temp = await getTemporaryDirectory();
      final folder = await Directory(
        '${temp.path}/email_attachments/'
        '${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final file = File('${folder.path}/${request.filename}');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: request.filename,
              mimeType: request.contentType,
            ),
          ],
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (error) {
      DebugLogger.warning(
        'email-attachment-download-failed',
        scope: 'email/download',
        data: {'errorType': error.runtimeType.toString()},
      );
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: AppLocalizations.of(context)!.emailDownloadFailed,
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  NavigationActionPolicy _navigationPolicy(
    _EmailSession session,
    NavigationAction action,
  ) {
    final url = action.request.url?.uriValue;
    if (action.isForMainFrame != true || url == null) {
      return NavigationActionPolicy.ALLOW;
    }
    if (isEmailOrigin(url, session.origin)) {
      return NavigationActionPolicy.ALLOW;
    }
    // The WebView never leaves the web app; links in messages open in the
    // system browser instead.
    if (emailNavigationOpensExternally(url)) {
      unawaited(_launchExternally(url));
    }
    return NavigationActionPolicy.CANCEL;
  }

  static bool _isDark(BuildContext context) => context.conduitTheme.isDark;

  @override
  Widget build(BuildContext context) {
    // Rebuild when the session's token changes; the token itself is read from
    // the API client that owns the session.
    ref.watch(authTokenProvider3);
    final session = _resolveSession();
    final token = session == null ? null : _tokenFor(session);
    if (session == null || token == null) return const SizedBox.shrink();
    if (_session != null && _session != session) {
      // Another account or address: drop the old page now and create the
      // next one when the tab is shown again.
      _session = null;
      _storageReady = false;
      _resetPage();
    }
    if (widget.isActive) _activate(session);
    final active = _session;
    if (active == null || !_storageReady) return const SizedBox.shrink();

    final dark = _isDark(context);
    if (_pageReady && _postedThemeMode != emailThemeMode(dark: dark)) {
      unawaited(_postTheme(active, dark: dark));
    }

    return Padding(
      padding: EdgeInsets.only(
        top: sidebarTabContentTopPadding(context),
        bottom: sidebarTabContentBottomPadding(context),
      ),
      child: _loadFailed
          ? _EmailLoadFailed(onRetry: _retry)
          : InAppWebView(
              key: ValueKey<Object>((
                active.accountId,
                active.appUri.toString(),
                _generation,
              )),
              initialUrlRequest: URLRequest(
                url: WebUri.uri(emailAppInitialUri(active.appUri, dark: dark)),
              ),
              initialUserScripts: UnmodifiableListView([
                _tokenScript(active, token),
              ]),
              initialSettings: emailWebViewSettings(active.origin),
              onWebViewCreated: (controller) {
                if (_session != active) return;
                _controller = controller;
                _seededToken = token;
                controller.addJavaScriptHandler(
                  handlerName: emailHostHandlerName,
                  callback: (JavaScriptHandlerFunctionData data) =>
                      _onHostCall(active, data),
                );
              },
              onLoadStart: (_, _) {
                _pageReady = false;
                _postedThemeMode = null;
              },
              onLoadStop: (_, url) => _onLoadStop(active, url),
              shouldOverrideUrlLoading: (_, action) async =>
                  _navigationPolicy(active, action),
              onReceivedError: (_, request, error) {
                if (request.isForMainFrame != true ||
                    error.type == WebResourceErrorType.CANCELLED ||
                    !isEmailOrigin(request.url.uriValue, active.origin)) {
                  return;
                }
                if (mounted && _session == active) {
                  setState(() => _loadFailed = true);
                }
              },
              onDownloadStarting: (_, _) async => DownloadStartResponse(
                action: DownloadStartResponseAction.CANCEL,
                handled: true,
              ),
            ),
    );
  }
}

/// WebView settings for the Email web app at [origin]: the JavaScript bridge
/// and its handlers exist only in the main frame of that origin, the page
/// cannot open windows, and nothing reads local files.
InAppWebViewSettings emailWebViewSettings(String origin) {
  final pattern = emailOriginPattern(origin);
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    transparentBackground: true,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    allowFileAccess: false,
    allowContentAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    mediaPlaybackRequiresUserGesture: true,
    isInspectable: kDebugMode,
    javaScriptHandlersForMainFrameOnly: true,
    javaScriptHandlersOriginAllowList: {pattern},
    javaScriptBridgeForMainFrameOnly: true,
    javaScriptBridgeOriginAllowList: Platform.isAndroid ? {origin} : {pattern},
  );
}

class _EmailLoadFailed extends StatelessWidget {
  const _EmailLoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = context.conduitTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.emailLoadFailed,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textSecondary),
            ),
            const SizedBox(height: Spacing.md),
            AdaptiveButton(label: l10n.retry, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
