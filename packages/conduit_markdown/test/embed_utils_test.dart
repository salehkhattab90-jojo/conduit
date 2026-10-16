import 'package:conduit_markdown/conduit_markdown.dart';
import 'package:test/test.dart';

void main() {
  group('isPreviewEmbed', () {
    test('accepts the structured preview shape', () {
      expect(
        isPreviewEmbed({
          'type': 'preview',
          'url': '/api/v1/files/abc/content',
          'name': 'Report.docx.pdf',
          'content_type': 'application/pdf',
        }),
        isTrue,
      );
    });

    test('rejects strings, html maps and url-less objects', () {
      expect(isPreviewEmbed('<div>html</div>'), isFalse);
      expect(isPreviewEmbed({'html': '<div/>'}), isFalse);
      expect(isPreviewEmbed({'type': 'preview'}), isFalse);
      expect(isPreviewEmbed({'type': 'preview', 'url': '  '}), isFalse);
      expect(isPreviewEmbed({'type': 'iframe', 'url': '/x'}), isFalse);
      expect(isPreviewEmbed(null), isFalse);
    });
  });

  group('sanitizeEmbedsForWebUi', () {
    test('returns null for nothing to save', () {
      expect(sanitizeEmbedsForWebUi(null), isNull);
      expect(sanitizeEmbedsForWebUi(const []), isNull);
      expect(
        sanitizeEmbedsForWebUi([
          {'src': '   '},
        ]),
        isNull,
      );
    });

    test('writes legacy embeds back as their source strings', () {
      expect(
        sanitizeEmbedsForWebUi([
          {'src': '<div>a</div>'},
          {'html': '<section>b</section>', 'src': '<section>b</section>'},
        ]),
        ['<div>a</div>', '<section>b</section>'],
      );
    });

    test('keeps preview objects, without the normalised src', () {
      expect(
        sanitizeEmbedsForWebUi([
          {
            'type': 'preview',
            'url': '/api/v1/files/abc/content',
            'name': 'Report.pdf',
            'content_type': 'application/pdf',
            'src': '/api/v1/files/abc/content',
          },
          {'src': '<div>artifact</div>'},
        ]),
        [
          {
            'type': 'preview',
            'url': '/api/v1/files/abc/content',
            'name': 'Report.pdf',
            'content_type': 'application/pdf',
          },
          '<div>artifact</div>',
        ],
      );
    });

    test('a preview object without name or content type stays minimal', () {
      expect(
        sanitizeEmbedsForWebUi([
          {'type': 'preview', 'url': '/api/v1/files/x/content'},
        ]),
        [
          {'type': 'preview', 'url': '/api/v1/files/x/content'},
        ],
      );
    });

    test('normalise then sanitise round-trips both shapes', () {
      final stored = <Object>[
        '<html><body>legacy</body></html>',
        {
          'type': 'preview',
          'url': '/api/v1/files/xyz/content',
          'name': 'Ledger.xlsx.pdf',
          'content_type': 'application/pdf',
        },
      ];
      expect(sanitizeEmbedsForWebUi(normalizeEmbedList(stored)), stored);
    });
  });
}
