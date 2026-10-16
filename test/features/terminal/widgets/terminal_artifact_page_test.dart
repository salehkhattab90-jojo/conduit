import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit/features/terminal/models/terminal_models.dart';
import 'package:conduit/features/terminal/widgets/terminal_artifact_page.dart';
import 'package:flutter_test/flutter_test.dart';

TerminalFileReadResult _text(String name, String text) =>
    TerminalFileReadResult(
      fileName: name,
      contentType: 'text/plain',
      text: text,
    );

void main() {
  group('terminalWebArtifactSource', () {
    test('renders HTML and SVG files by extension', () {
      const html = '<!doctype html><html><body>chart</body></html>';
      expect(terminalWebArtifactSource(_text('chart.html', html)), html);
      expect(
        terminalWebArtifactSource(_text('Page.HTM', '<p>x</p>')),
        '<p>x</p>',
      );
      expect(
        terminalWebArtifactSource(_text('icon.svg', '<svg></svg>')),
        '<svg></svg>',
      );
    });

    test('decodes an SVG the read endpoint returned as bytes', () {
      const svg = '<svg viewBox="0 0 1 1"></svg>';
      final preview = TerminalFileReadResult(
        fileName: 'logo',
        contentType: 'image/svg+xml',
        bytes: Uint8List.fromList(utf8.encode(svg)),
      );
      expect(terminalWebArtifactSource(preview), svg);

      const html = '<html><body>raw</body></html>';
      expect(
        terminalWebArtifactSource(
          TerminalFileReadResult(
            fileName: 'page',
            contentType: 'text/html; charset=utf-8',
            bytes: Uint8List.fromList(utf8.encode(html)),
          ),
        ),
        html,
      );
    });

    test('sniffs extensionless documents', () {
      expect(
        terminalWebArtifactSource(_text('output', '  <!DOCTYPE html><p/>')),
        isNotNull,
      );
      expect(terminalWebArtifactSource(_text('output', '<svg/>')), isNotNull);
      expect(terminalWebArtifactSource(_text('notes.txt', '<b>x</b>')), isNull);
    });

    test('never passes a URL or plain text through', () {
      // WebContentEmbed would load a URL as a remote page outside its sandbox.
      expect(
        terminalWebArtifactSource(_text('link.html', 'https://example.com')),
        isNull,
      );
      expect(
        terminalWebArtifactSource(_text('x.html', '//example.com')),
        isNull,
      );
      expect(terminalWebArtifactSource(_text('x.html', '   ')), isNull);
      expect(
        terminalWebArtifactSource(
          TerminalFileReadResult(
            fileName: 'photo.png',
            contentType: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
        isNull,
      );
    });
  });
}
