/// Where the embedded Email web app lives, and the rules for talking to it.
///
/// The Email section hosts a web app (served next to Open WebUI at
/// `<server>/email/app`) in a WebView. Everything here is pure so the
/// security-relevant decisions -- which origin receives the session token,
/// which messages the host accepts, which URLs leave the app -- are unit
/// tested without a WebView.
library;

import 'dart:convert';

/// `--dart-define=EMAIL_APP_URL=https://…` replaces the default
/// `<server>/email/app` location, for deployments that serve the web app
/// elsewhere.
const String emailAppUrlOverride = String.fromEnvironment('EMAIL_APP_URL');

/// Name of the JavaScript handler the page calls with
/// `window.flutter_inappwebview.callHandler('emailHost', message)`.
const String emailHostHandlerName = 'emailHost';

/// Message types exchanged with the web app. The names are a contract shared
/// with the web app and the web client's own embed; do not rename them.
abstract final class EmailHostMessageType {
  /// Host → page: `{type, token}` -- the signed-in session bearer.
  static const String token = 'email-token';

  /// Host → page: `{type, mode}` -- `light` or `dark`.
  static const String theme = 'email-theme';

  /// Host → page: `{type, id}` -- open one message (a tapped notification).
  static const String open = 'email-open';

  /// Page → host: `{type, url}` -- open a URL outside the app (Gmail consent).
  static const String openUrl = 'email-open-url';

  /// Page → host: `{type, url, filename?, contentType?}` -- save an
  /// attachment, which a WebView cannot do itself.
  static const String download = 'email-download';
}

/// The Email web app for the server at [serverUrl], without the theme query.
///
/// [override] (the `EMAIL_APP_URL` define) wins when set. Otherwise the app is
/// `<server>/email/app`, keeping any path prefix the server is hosted under.
/// Returns null when neither yields an absolute http(s) URL.
Uri? resolveEmailAppUri({
  required String? serverUrl,
  String override = emailAppUrlOverride,
}) {
  final trimmedOverride = override.trim();
  if (trimmedOverride.isNotEmpty) {
    return _httpUri(Uri.tryParse(trimmedOverride));
  }
  final server = _httpUri(Uri.tryParse(serverUrl?.trim() ?? ''));
  if (server == null) return null;
  final segments = [
    ...server.pathSegments.where((segment) => segment.isNotEmpty),
    'email',
    'app',
  ];
  return Uri(
    scheme: server.scheme,
    host: server.host,
    port: server.hasPort ? server.port : null,
    pathSegments: segments,
  );
}

/// [base] with the `theme` query set, so the page paints in the app's theme
/// before any script runs.
Uri emailAppInitialUri(Uri base, {required bool dark}) => base.replace(
  queryParameters: <String, String>{
    ...base.queryParameters,
    'theme': emailThemeMode(dark: dark),
  },
);

/// The `email-theme` mode string for a brightness.
String emailThemeMode({required bool dark}) => dark ? 'dark' : 'light';

/// The web origin (`scheme://host[:port]`) of an http(s) [uri], or null for
/// anything else (opaque, file, data, `about:blank`, relative).
String? emailOriginOf(Uri? uri) {
  final http = _httpUri(uri);
  if (http == null) return null;
  try {
    return http.origin;
  } on StateError {
    return null;
  }
}

/// Whether [uri] is on exactly [expectedOrigin].
bool isEmailOrigin(Uri? uri, String expectedOrigin) {
  final origin = emailOriginOf(uri);
  return origin != null && origin == expectedOrigin;
}

/// [origin] as an anchored regular expression, for the WebView allow lists
/// that are regular expressions (JavaScript-handler lists everywhere; user
/// script and bridge rules on Apple platforms). Dots become `[.]` rather than
/// an escaped dot because some of those lists are rebuilt as JavaScript
/// string literals, which drop a lone backslash.
String emailOriginPattern(String origin) {
  if (RegExp(r'^[A-Za-z0-9.:/-]+$').hasMatch(origin)) {
    return '^${origin.replaceAll('.', '[.]')}\$';
  }
  return '^${RegExp.escape(origin)}\$';
}

/// Whether a call to the [emailHostHandlerName] handler may be trusted: it
/// must come from the main frame, and both the frame's origin and the
/// document URL must be the Email web app's own origin. Subframes (the
/// "Discuss" chat, rendered mail) and navigated-away documents are ignored.
bool isAllowedEmailHostCall({
  required bool isMainFrame,
  required Uri? frameOrigin,
  required Uri? requestUrl,
  required String expectedOrigin,
}) =>
    isMainFrame &&
    isEmailOrigin(frameOrigin, expectedOrigin) &&
    isEmailOrigin(requestUrl, expectedOrigin);

/// Whether a URL the page asks to open outside the app may be launched. Only
/// https: the web app only ever hands over the Gmail consent page, and other
/// schemes (custom app links, `intent:`, `file:`) must not be reachable from
/// web content.
bool emailExternalUrlAllowed(Uri url) =>
    url.scheme == 'https' && url.host.isNotEmpty;

/// Whether a main-frame navigation away from the web app should be handed to
/// the system browser (a link in a message) rather than dropped. The WebView
/// itself never leaves the web app's origin.
bool emailNavigationOpensExternally(Uri url) =>
    (url.scheme == 'https' || url.scheme == 'http') && url.host.isNotEmpty;

/// A request the web app sends to the host, already validated.
sealed class EmailHostMessage {
  const EmailHostMessage();

  /// Parses one handler argument. Returns null for anything malformed,
  /// unknown, or not allowed (a non-https external URL, an attachment URL off
  /// the web app's [expectedOrigin]).
  static EmailHostMessage? parse(
    Object? raw, {
    required String expectedOrigin,
  }) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final url = raw['url'];
    if (type is! String || url is! String || url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;
    switch (type) {
      case EmailHostMessageType.openUrl:
        return emailExternalUrlAllowed(parsed)
            ? EmailOpenUrlRequest(parsed)
            : null;
      case EmailHostMessageType.download:
        if (!isEmailOrigin(parsed, expectedOrigin)) return null;
        final filename = raw['filename'];
        final contentType = raw['contentType'];
        return EmailDownloadRequest(
          url: parsed,
          filename: sanitizeEmailAttachmentFilename(
            filename is String ? filename : null,
          ),
          contentType: contentType is String && contentType.trim().isNotEmpty
              ? contentType.trim()
              : null,
        );
    }
    return null;
  }
}

/// `email-open-url`: open [url] in the system browser.
final class EmailOpenUrlRequest extends EmailHostMessage {
  const EmailOpenUrlRequest(this.url);

  final Uri url;
}

/// `email-download`: fetch [url] (same origin as the web app) and hand the
/// file to the system share sheet.
final class EmailDownloadRequest extends EmailHostMessage {
  const EmailDownloadRequest({
    required this.url,
    required this.filename,
    this.contentType,
  });

  final Uri url;

  /// Safe as a single path segment; never empty.
  final String filename;
  final String? contentType;
}

/// A file name from web content made safe to write into a directory: no path
/// separators, reserved or control characters, leading dots, or unbounded
/// length. Falls back to `attachment`.
String sanitizeEmailAttachmentFilename(String? name) {
  const fallback = 'attachment';
  if (name == null) return fallback;
  var base = name.split(RegExp(r'[\\/]')).last;
  base = base
      .replaceAll(RegExp(r'[\x00-\x1f\x7f:*?"<>|]'), '_')
      .trim()
      .replaceFirst(RegExp(r'^\.+'), '')
      .trim();
  if (base.isEmpty) return fallback;
  const maxLength = 120;
  if (base.length <= maxLength) return base;
  final dot = base.lastIndexOf('.');
  final extension = dot > 0 && base.length - dot <= 16
      ? base.substring(dot)
      : '';
  return base.substring(0, maxLength - extension.length) + extension;
}

/// AT_DOCUMENT_START user script seeding `localStorage.token`, which the web
/// app and its same-origin "Discuss" chat (an Open WebUI iframe) read for the
/// session. The script re-checks the document's exact origin itself: the
/// WebView's origin rules are regular expressions on some platforms, and an
/// unanchored pattern would also match look-alike hosts.
String emailTokenSeedScript({required String origin, required String token}) =>
    '(function(){'
    'if(window.location.origin!==${_jsLiteral(origin)})return;'
    'try{window.localStorage.setItem("token",${_jsLiteral(token)});}'
    'catch(e){}'
    '})();';

/// Posts [message] to the page, but only while the document is still on
/// [origin], and with [origin] as the explicit target -- never `'*'`.
String emailPostMessageScript({
  required String origin,
  required Map<String, Object?> message,
}) =>
    '(function(){'
    'if(window.location.origin!==${_jsLiteral(origin)})return;'
    'window.postMessage(${_jsLiteral(message)},${_jsLiteral(origin)});'
    '})();';

/// `email-token` for [token].
String emailTokenMessageScript({
  required String origin,
  required String token,
}) => emailPostMessageScript(
  origin: origin,
  message: {'type': EmailHostMessageType.token, 'token': token},
);

/// `email-theme` for the given brightness.
String emailThemeMessageScript({required String origin, required bool dark}) =>
    emailPostMessageScript(
      origin: origin,
      message: {
        'type': EmailHostMessageType.theme,
        'mode': emailThemeMode(dark: dark),
      },
    );

/// `email-open` for one message id.
String emailOpenMessageScript({required String origin, required String id}) =>
    emailPostMessageScript(
      origin: origin,
      message: {'type': EmailHostMessageType.open, 'id': id},
    );

/// A JSON value as a JavaScript literal. JSON is a JavaScript subset except
/// for U+2028/U+2029 in older engines, so those are escaped too.
String _jsLiteral(Object? value) =>
    jsonEncode(value)
        .replaceAll(String.fromCharCode(0x2028), r'\u2028')
        .replaceAll(String.fromCharCode(0x2029), r'\u2029');

Uri? _httpUri(Uri? uri) {
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri;
}
