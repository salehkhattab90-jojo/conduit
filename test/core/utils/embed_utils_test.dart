import 'package:checks/checks.dart';
import 'package:conduit/core/utils/embed_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPreviewEmbed', () {
    test('true for the structured preview shape', () {
      check(
        isPreviewEmbed({
          'type': 'preview',
          'url': '/api/v1/files/abc/content',
          'name': 'Report.pdf',
          'content_type': 'application/pdf',
        }),
      ).isTrue();
    });

    test('false for strings, html maps, and url-less objects', () {
      check(isPreviewEmbed('<div>html</div>')).isFalse();
      check(isPreviewEmbed({'html': '<div/>'})).isFalse();
      check(isPreviewEmbed({'type': 'preview'})).isFalse();
      check(isPreviewEmbed({'type': 'preview', 'url': '  '})).isFalse();
      check(isPreviewEmbed(null)).isFalse();
    });
  });

  group('sanitizeEmbedsForWebUi', () {
    test('flattens legacy html embeds to source strings (unchanged)', () {
      final out = sanitizeEmbedsForWebUi([
        {'src': '<div>a</div>'},
        {'html': '<section>b</section>', 'src': '<section>b</section>'},
      ]);
      check(out!).deepEquals(['<div>a</div>', '<section>b</section>']);
    });

    test('preserves preview objects — never corrupts the server contract', () {
      final out = sanitizeEmbedsForWebUi([
        {
          'type': 'preview',
          'url': '/api/v1/files/abc/content',
          'name': 'Report.pdf',
          'content_type': 'application/pdf',
          'src': '/api/v1/files/abc/content', // normalizeEmbedList artifact
        },
        {'src': '<div>artifact</div>'},
      ]);
      check(out!).deepEquals([
        {
          'type': 'preview',
          'url': '/api/v1/files/abc/content',
          'name': 'Report.pdf',
          'content_type': 'application/pdf',
        },
        '<div>artifact</div>',
      ]);
    });

    test('round-trip: normalize then sanitize keeps the object shape', () {
      final normalized = normalizeEmbedList([
        {
          'type': 'preview',
          'url': '/api/v1/files/xyz/content',
          'name': 'Ledger.pdf',
          'content_type': 'application/pdf',
        },
      ]);
      final out = sanitizeEmbedsForWebUi(normalized);
      check(out!.single as Map<String, dynamic>).deepEquals({
        'type': 'preview',
        'url': '/api/v1/files/xyz/content',
        'name': 'Ledger.pdf',
        'content_type': 'application/pdf',
      });
    });
  });
}
