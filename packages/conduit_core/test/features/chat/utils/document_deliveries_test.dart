import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:conduit_core/features/chat/utils/document_deliveries.dart';
import 'package:conduit_markdown/conduit_markdown.dart';
import 'package:test/test.dart';

Map<String, dynamic> _file(String id, String name, {String? contentType}) => {
  'type': 'data',
  'url': '/api/v1/files/$id/content',
  'name': name,
  'content_type': ?contentType,
};

Map<String, dynamic> _preview(String id, String name) => {
  'type': 'preview',
  'url': '/api/v1/files/$id/content',
  'name': name,
  'content_type': 'application/pdf',
};

/// A native tool call whose result carries [files] and [embeds].
List<Map<String, dynamic>> _toolCall(
  String callId, {
  String name = 'generate_document',
  Map<String, dynamic> arguments = const {},
  List<Map<String, dynamic>> files = const [],
  List<Object> embeds = const [],
}) => [
  {
    'type': 'function_call',
    'call_id': callId,
    'name': name,
    'arguments': jsonEncode(arguments),
    'status': 'completed',
  },
  {
    'type': 'function_call_output',
    'call_id': callId,
    'output': [
      {'type': 'input_text', 'text': 'done'},
    ],
    'status': 'completed',
    if (files.isNotEmpty) 'files': files,
    if (embeds.isNotEmpty) 'embeds': embeds,
  },
];

void main() {
  group('collectDocumentDeliveries', () {
    test('nothing to pair leaves files and embeds as they are', () {
      final files = [
        {'type': 'image', 'url': '/api/v1/files/img/content'},
        _file('f1', 'notes.md'),
      ];
      final result = collectDocumentDeliveries(files: files);

      check(result.deliveries).isEmpty();
      check(result.files).deepEquals(files);
      check(result.embeds).isEmpty();
    });

    test('a tool result preview pairs with its file: one card', () {
      final result = collectDocumentDeliveries(
        output: _toolCall(
          'c1',
          files: [_file('real-1', 'Report.docx')],
          embeds: [_preview('prev-1', 'Report.docx.pdf')],
        ),
      );

      final delivery = result.deliveries.single;
      check(delivery.kind).equals(DocumentDeliveryKind.preview);
      check(delivery.fileName).equals('Report.docx');
      check(delivery.fileId).equals('real-1');
      check(delivery.previewUrl).equals('/api/v1/files/prev-1/content');
      check(delivery.extension).equals('docx');
      check(result.files).isEmpty();
    });

    test('a PDF previews itself', () {
      final pdf = _file('pdf-1', 'Ledger.pdf', contentType: 'application/pdf');
      final result = collectDocumentDeliveries(
        output: _toolCall(
          'c1',
          files: [pdf],
          embeds: [_preview('pdf-1', 'Ledger.pdf')],
        ),
      );

      check(result.deliveries.single.fileId).equals('pdf-1');
      check(result.deliveries.single.extension).equals('pdf');
    });

    test('several documents in one result pair by name', () {
      final result = collectDocumentDeliveries(
        output: _toolCall(
          'c1',
          files: [_file('a', 'Plan.xlsx'), _file('b', 'Deck.pptx')],
          embeds: [
            _preview('pb', 'Deck.pptx.pdf'),
            _preview('pa', 'Plan.xlsx.pdf'),
          ],
        ),
      );

      check(result.deliveries.map((d) => (d.fileName, d.previewUrl)).toList())
          .deepEquals([
            ('Deck.pptx', '/api/v1/files/pb/content'),
            ('Plan.xlsx', '/api/v1/files/pa/content'),
          ]);
    });

    test('one card per delivery across tool calls', () {
      final result = collectDocumentDeliveries(
        output: [
          ..._toolCall(
            'c1',
            files: [_file('a', 'One.docx')],
            embeds: [_preview('pa', 'One.docx.pdf')],
          ),
          ..._toolCall(
            'c2',
            files: [_file('b', 'Two.docx')],
            embeds: [_preview('pb', 'Two.docx.pdf')],
          ),
        ],
      );

      check(result.deliveries.map((d) => d.fileName).toList())
          .deepEquals(['One.docx', 'Two.docx']);
    });

    test('a preview whose file did not arrive still gets a card', () {
      final result = collectDocumentDeliveries(
        embeds: normalizeEmbedList([_preview('p1', 'Report.docx.pdf')]),
      );

      final delivery = result.deliveries.single;
      check(delivery.fileId).isNull();
      check(delivery.displayName).equals('Report.docx');
      check(result.embeds).isEmpty();
    });

    test('message-level preview objects and their file pair, chip hidden', () {
      final image = {'type': 'image', 'url': '/api/v1/files/img/content'};
      final result = collectDocumentDeliveries(
        files: [image, _file('real-1', 'Report.docx')],
        embeds: normalizeEmbedList([_preview('prev-1', 'Report.docx.pdf')]),
      );

      check(result.deliveries.single.fileId).equals('real-1');
      check(result.files).deepEquals([image]);
      // Preview objects never reach the inline embed renderer.
      check(result.embeds).isEmpty();
    });

    test('a legacy HTML preview pairs with the single file', () {
      final result = collectDocumentDeliveries(
        files: [_file('real-1', 'Memo.docx')],
        embeds: normalizeEmbedList(['<html><body>memo</body></html>']),
      );

      final delivery = result.deliveries.single;
      check(delivery.kind).equals(DocumentDeliveryKind.htmlPreview);
      check(delivery.fileId).equals('real-1');
      check(delivery.previewHtml).equals('<html><body>memo</body></html>');
      check(result.files).isEmpty();
      check(result.embeds).isEmpty();
    });

    test('an HTML embed with no file is an artifact named by its call', () {
      final result = collectDocumentDeliveries(
        embeds: normalizeEmbedList(['<svg viewBox="0 0 1 1"></svg>']),
        output: _toolCall(
          'c1',
          name: 'show',
          arguments: const {'path': '/work/out/chart.svg'},
        ),
      );

      final delivery = result.deliveries.single;
      check(delivery.isArtifact).isTrue();
      check(delivery.fileName).equals('chart.svg');
      check(delivery.extension).equals('svg');
      check(result.embeds).isEmpty();
    });

    test('an unnamed artifact is identified as HTML', () {
      final result = collectDocumentDeliveries(
        output: _toolCall('c1', embeds: ['<div>widget</div>']),
      );

      check(result.deliveries.single.fileName).isNull();
      check(result.deliveries.single.extension).equals('html');
    });

    test('ambiguous HTML embeds render as before', () {
      final embeds = normalizeEmbedList(['<div>a</div>', '<div>b</div>']);
      final result = collectDocumentDeliveries(
        files: [_file('f', 'x.docx')],
        embeds: embeds,
      );

      check(result.deliveries).isEmpty();
      check(result.embeds).deepEquals(embeds);
      check(result.files).length.equals(1);
    });

    test('a tool file without a preview is listed with the files', () {
      final result = collectDocumentDeliveries(
        files: [_file('dup', 'Data.csv')],
        output: [
          ..._toolCall('c1', files: [_file('md', 'Notes.md')]),
          ..._toolCall('c2', files: [_file('dup', 'Data.csv')]),
          ..._toolCall(
            'c3',
            files: [
              {'type': 'image', 'url': '/api/v1/files/img/content'},
            ],
          ),
        ],
      );

      check(result.deliveries).isEmpty();
      check(result.files.map((file) => file['name']).toList())
          .deepEquals(['Data.csv', 'Notes.md']);
    });

    test('the same delivery in the message and its tool result shows once', () {
      final file = _file('real-1', 'Report.docx');
      final preview = _preview('prev-1', 'Report.docx.pdf');
      final result = collectDocumentDeliveries(
        files: [file],
        embeds: normalizeEmbedList([preview]),
        output: _toolCall('c1', files: [file], embeds: [preview]),
      );

      check(result.deliveries).length.equals(1);
      check(result.files).isEmpty();
    });
  });

  group('openWebUiFileIdFromUrl', () {
    test('reads relative, absolute and bare ids', () {
      check(openWebUiFileIdFromUrl('/api/v1/files/abc/content')).equals('abc');
      check(openWebUiFileIdFromUrl('/api/v1/files/abc')).equals('abc');
      check(
        openWebUiFileIdFromUrl('https://owui.example/api/v1/files/abc/content'),
      ).equals('abc');
      check(openWebUiFileIdFromUrl('abc-123')).equals('abc-123');
      check(openWebUiFileIdFromUrl('data:image/png;base64,AAA')).isNull();
      check(openWebUiFileIdFromUrl(null)).isNull();
    });
  });

  group('documentExtension', () {
    test('is the real extension, lower case', () {
      check(documentExtension('Report.DOCX')).equals('docx');
      check(documentExtension('archive.tar.gz')).equals('gz');
      check(documentExtension('README')).isNull();
      check(documentExtension('.env')).isNull();
      check(documentExtension('model.safetensors')).equals('safet');
    });
  });
}
