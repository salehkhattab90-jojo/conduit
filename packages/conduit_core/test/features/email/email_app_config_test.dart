import 'dart:convert';

import 'package:conduit_core/features/email/email_app_config.dart';
import 'package:test/test.dart';

/// The JavaScript literal passed as the first argument after [marker].
Object? _literalAfter(String script, String marker) {
  final start = script.indexOf(marker);
  expect(start, isNonNegative, reason: 'marker $marker missing in $script');
  final rest = script.substring(start + marker.length);
  // Literals are JSON; find the shortest prefix that decodes.
  for (var end = 1; end <= rest.length; end++) {
    try {
      return jsonDecode(rest.substring(0, end));
    } on FormatException {
      continue;
    }
  }
  fail('no literal after $marker in $script');
}

void main() {
  group('resolveEmailAppUri', () {
    test('defaults to <server>/email/app', () {
      expect(
        resolveEmailAppUri(serverUrl: 'https://chat.example.com', override: ''),
        Uri.parse('https://chat.example.com/email/app'),
      );
    });

    test(
      'keeps a path prefix and drops trailing slash, query and fragment',
      () {
        expect(
          resolveEmailAppUri(
            serverUrl: 'https://example.com/owui/?x=1#frag',
            override: '',
          ),
          Uri.parse('https://example.com/owui/email/app'),
        );
      },
    );

    test('keeps a non-default port', () {
      expect(
        resolveEmailAppUri(serverUrl: 'http://10.0.0.5:8080', override: ''),
        Uri.parse('http://10.0.0.5:8080/email/app'),
      );
    });

    test('the EMAIL_APP_URL override wins', () {
      expect(
        resolveEmailAppUri(
          serverUrl: 'https://chat.example.com',
          override: ' https://mail.example.org/app ',
        ),
        Uri.parse('https://mail.example.org/app'),
      );
    });

    test('rejects anything that is not an absolute http(s) URL', () {
      expect(resolveEmailAppUri(serverUrl: null, override: ''), isNull);
      expect(resolveEmailAppUri(serverUrl: '', override: ''), isNull);
      expect(
        resolveEmailAppUri(serverUrl: 'chat.example.com', override: ''),
        isNull,
      );
      expect(
        resolveEmailAppUri(serverUrl: 'file:///etc/passwd', override: ''),
        isNull,
      );
      expect(
        resolveEmailAppUri(
          serverUrl: 'https://chat.example.com',
          override: 'javascript:alert(1)',
        ),
        isNull,
      );
      expect(
        resolveEmailAppUri(
          serverUrl: 'https://user:pw@chat.example.com',
          override: '',
        ),
        isNull,
      );
    });
  });

  test('emailAppInitialUri sets the theme and keeps other parameters', () {
    final base = Uri.parse('https://mail.example.org/app?lang=en&theme=x');
    final dark = emailAppInitialUri(base, dark: true);
    expect(dark.queryParameters, {'lang': 'en', 'theme': 'dark'});
    expect(
      emailAppInitialUri(
        Uri.parse('https://a.example/email/app'),
        dark: false,
      ).toString(),
      'https://a.example/email/app?theme=light',
    );
  });

  group('origins', () {
    test('normalises default ports and host case', () {
      expect(
        emailOriginOf(Uri.parse('https://Mail.Example.com:443/email/app')),
        'https://mail.example.com',
      );
      expect(
        emailOriginOf(Uri.parse('http://mail.example.com:8080/x')),
        'http://mail.example.com:8080',
      );
    });

    test('non-web documents have no origin', () {
      expect(emailOriginOf(null), isNull);
      expect(emailOriginOf(Uri.parse('about:blank')), isNull);
      expect(emailOriginOf(Uri.parse('data:text/html,hi')), isNull);
      expect(emailOriginOf(Uri.parse('/relative')), isNull);
      expect(emailOriginOf(Uri.parse('')), isNull);
    });

    test('isEmailOrigin is exact', () {
      const origin = 'https://mail.example.com';
      expect(
        isEmailOrigin(Uri.parse('https://mail.example.com/a'), origin),
        isTrue,
      );
      expect(
        isEmailOrigin(Uri.parse('https://mail.example.com.evil.net/'), origin),
        isFalse,
      );
      expect(
        isEmailOrigin(Uri.parse('http://mail.example.com/'), origin),
        isFalse,
      );
      expect(
        isEmailOrigin(Uri.parse('https://mail.example.com:8443/'), origin),
        isFalse,
      );
    });

    test('emailOriginPattern is anchored and treats dots literally', () {
      final pattern = emailOriginPattern('https://mail.example.com');
      expect(pattern, r'^https://mail[.]example[.]com$');
      final regex = RegExp(pattern);
      expect(regex.hasMatch('https://mail.example.com'), isTrue);
      expect(regex.hasMatch('https://mail-example.com'), isFalse);
      expect(regex.hasMatch('https://mail.example.com.evil.net'), isFalse);
      expect(
        regex.hasMatch('https://evil.net/https://mail.example.com'),
        isFalse,
      );
      expect(
        RegExp(emailOriginPattern('http://[::1]:8080'))
            .hasMatch('http://[::1]:8080'),
        isTrue,
      );
    });
  });

  group('isAllowedEmailHostCall', () {
    const origin = 'https://mail.example.com';
    final page = Uri.parse('https://mail.example.com/email/app?theme=dark');

    test('accepts the main frame on the web app origin', () {
      expect(
        isAllowedEmailHostCall(
          isMainFrame: true,
          frameOrigin: Uri.parse(origin),
          requestUrl: page,
          expectedOrigin: origin,
        ),
        isTrue,
      );
    });

    test('rejects subframes, other origins and navigated-away documents', () {
      expect(
        isAllowedEmailHostCall(
          isMainFrame: false,
          frameOrigin: Uri.parse(origin),
          requestUrl: page,
          expectedOrigin: origin,
        ),
        isFalse,
      );
      expect(
        isAllowedEmailHostCall(
          isMainFrame: true,
          frameOrigin: Uri.parse('https://evil.example'),
          requestUrl: page,
          expectedOrigin: origin,
        ),
        isFalse,
      );
      expect(
        isAllowedEmailHostCall(
          isMainFrame: true,
          frameOrigin: Uri.parse(origin),
          requestUrl: Uri.parse('https://evil.example/'),
          expectedOrigin: origin,
        ),
        isFalse,
      );
      expect(
        isAllowedEmailHostCall(
          isMainFrame: true,
          frameOrigin: Uri.parse('null'),
          requestUrl: Uri.parse('about:blank'),
          expectedOrigin: origin,
        ),
        isFalse,
      );
    });
  });

  group('EmailHostMessage.parse', () {
    const origin = 'https://mail.example.com';

    EmailHostMessage? parse(Object? raw) =>
        EmailHostMessage.parse(raw, expectedOrigin: origin);

    test('email-open-url accepts https only', () {
      final message = parse({
        'type': 'email-open-url',
        'url': 'https://accounts.google.com/o/oauth2/auth?x=1#y',
      });
      expect(message, isA<EmailOpenUrlRequest>());
      expect((message! as EmailOpenUrlRequest).url.host, 'accounts.google.com');
      for (final url in [
        'http://accounts.google.com/',
        'intent://scan/#Intent;scheme=zxing;end',
        'javascript:alert(1)',
        'file:///etc/hosts',
        'mailto:a@b.c',
        'conduit://open',
        '',
      ]) {
        expect(
          parse({'type': 'email-open-url', 'url': url}),
          isNull,
          reason: url,
        );
      }
    });

    test('email-download accepts the web app origin only', () {
      final message = parse({
        'type': 'email-download',
        'url': 'https://mail.example.com/email/emails/7/inbound-attachments/0',
        'filename': '../../report.pdf',
        'contentType': ' application/pdf ',
      });
      expect(message, isA<EmailDownloadRequest>());
      final download = message! as EmailDownloadRequest;
      expect(download.filename, 'report.pdf');
      expect(download.contentType, 'application/pdf');

      expect(
        parse({
          'type': 'email-download',
          'url': 'https://evil.example/steal',
          'filename': 'x',
        }),
        isNull,
      );
      expect(
        parse({
          'type': 'email-download',
          'url': 'http://mail.example.com/email/emails/7',
        }),
        isNull,
      );
      final bare =
          parse({
                'type': 'email-download',
                'url': 'https://mail.example.com/email/emails/7/inbound-attachments/0',
              })!
              as EmailDownloadRequest;
      expect(bare.filename, 'attachment');
      expect(bare.contentType, isNull);
    });

    test('ignores malformed and unknown messages', () {
      expect(parse(null), isNull);
      expect(parse('email-open-url'), isNull);
      expect(parse(<String, Object?>{}), isNull);
      expect(
        parse({'type': 'email-discuss', 'url': 'https://a.example'}),
        isNull,
      );
      expect(parse({'type': 'email-open-url', 'url': 42}), isNull);
      expect(parse({'type': 7, 'url': 'https://a.example'}), isNull);
    });
  });

  group('sanitizeEmailAttachmentFilename', () {
    test('keeps ordinary names', () {
      expect(
        sanitizeEmailAttachmentFilename('Invoice 2026.pdf'),
        'Invoice 2026.pdf',
      );
    });

    test('strips directories, reserved characters and leading dots', () {
      expect(sanitizeEmailAttachmentFilename('../../etc/passwd'), 'passwd');
      expect(sanitizeEmailAttachmentFilename(r'C:\Users\a\b.txt'), 'b.txt');
      expect(
        sanitizeEmailAttachmentFilename('a:b*c?"d<e>f|g.txt'),
        'a_b_c__d_e_f_g.txt',
      );
      expect(sanitizeEmailAttachmentFilename('..hidden'), 'hidden');
      expect(
        sanitizeEmailAttachmentFilename('line\nbreak\u0000.txt'),
        'line_break_.txt',
      );
    });

    test('falls back when nothing is left', () {
      expect(sanitizeEmailAttachmentFilename(null), 'attachment');
      expect(sanitizeEmailAttachmentFilename(''), 'attachment');
      expect(sanitizeEmailAttachmentFilename('../'), 'attachment');
      expect(sanitizeEmailAttachmentFilename('...'), 'attachment');
    });

    test('bounds the length and keeps the extension', () {
      final name = '${'a' * 300}.docx';
      final safe = sanitizeEmailAttachmentFilename(name);
      expect(safe.length, 120);
      expect(safe, endsWith('.docx'));
    });
  });

  group('scripts', () {
    const origin = 'https://mail.example.com';
    const nasty = 'a"b\'c\\d</script>\u2028e\nf';

    test('the token seed checks the exact origin before writing', () {
      final script = emailTokenSeedScript(origin: origin, token: nasty);
      expect(
        script,
        startsWith(
          '(function(){if(window.location.origin!=='
          '"https://mail.example.com")return;',
        ),
      );
      expect(_literalAfter(script, 'setItem("token",'), nasty);
      expect(script, isNot(contains('\u2028')));
      expect(script, isNot(contains('\n')));
    });

    test('messages carry an explicit target origin, never "*"', () {
      final script = emailTokenMessageScript(origin: origin, token: nasty);
      expect(script, isNot(contains("'*'")));
      expect(script, isNot(contains('"*"')));
      expect(script, contains(',"https://mail.example.com");'));
      expect(script, contains('window.location.origin!=='));
      expect(_literalAfter(script, 'window.postMessage('), {
        'type': 'email-token',
        'token': nasty,
      });
    });

    test('theme and open messages use the protocol names', () {
      expect(
        _literalAfter(
          emailThemeMessageScript(origin: origin, dark: true),
          'window.postMessage(',
        ),
        {'type': 'email-theme', 'mode': 'dark'},
      );
      expect(
        _literalAfter(
          emailOpenMessageScript(origin: origin, id: "x');alert(1);//"),
          'window.postMessage(',
        ),
        {'type': 'email-open', 'id': "x');alert(1);//"},
      );
    });
  });

  test('external launch policies', () {
    expect(emailExternalUrlAllowed(Uri.parse('https://a.example/x')), isTrue);
    expect(emailExternalUrlAllowed(Uri.parse('http://a.example/x')), isFalse);
    expect(
      emailNavigationOpensExternally(Uri.parse('http://a.example')),
      isTrue,
    );
    expect(emailNavigationOpensExternally(Uri.parse('tel:123')), isFalse);
    expect(emailNavigationOpensExternally(Uri.parse('intent://x')), isFalse);
  });
}
