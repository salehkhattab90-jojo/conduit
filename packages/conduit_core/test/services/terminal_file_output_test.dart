import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:conduit_core/services/terminal_file_output.dart';
import 'package:test/test.dart';

/// A `display_file` call and its result as Open WebUI 0.12.2 stores them
/// (`build_terminal_file_tool_result` → `process_tool_result`).
List<Map<String, dynamic>> _displayFileTrace({
  String callId = 'call_1',
  Map<String, dynamic> arguments = const {'path': 'report.html'},
  required Map<String, dynamic> result,
  String name = 'display_file',
}) => [
  {
    'type': 'function_call',
    'id': 'fc_1',
    'call_id': callId,
    'name': name,
    'arguments': jsonEncode(arguments),
    'status': 'completed',
  },
  {
    'type': 'function_call_output',
    'id': 'fco_1',
    'call_id': callId,
    'output': [
      {
        'type': 'input_text',
        'text': const JsonEncoder.withIndent('  ').convert(result),
      },
    ],
    'status': 'completed',
  },
];

Map<String, dynamic> _fileResult({
  String path = '/home/user/work/report.html',
  bool inline = false,
  Object? exists = true,
  Map<String, dynamic> extra = const {},
}) => {
  'path': path,
  'exists': exists,
  'type': 'file',
  'source': 'open_terminal',
  if (inline) 'displayed': true,
  'terminal_selector': 'term-1',
  'terminal_id': 'term-1',
  'session_id': 'chat-1',
  'full_path': path,
  'name': path.split('/').last,
  'mime_type': 'text/html',
  'content_type': 'text/html',
  ...extra,
};

void main() {
  group('openTerminalFilesFromOutput', () {
    test('reads the stored record of a display_file call', () {
      final records = openTerminalFilesFromOutput(
        _displayFileTrace(result: _fileResult()),
      );

      check(records).length.equals(1);
      final record = records.single;
      check(record.path).equals('/home/user/work/report.html');
      check(record.name).equals('report.html');
      check(record.terminalSelector).equals('term-1');
      check(record.terminalId).equals('term-1');
      check(record.terminalUrl).isNull();
      check(record.sessionId).equals('chat-1');
      check(record.mimeType).equals('text/html');
      check(record.displayed).isFalse();
      check(record.callId).equals('call_1');
    });

    test('reads an inline display_file, which sends no socket event', () {
      final records = openTerminalFilesFromOutput(
        _displayFileTrace(
          arguments: const {'path': 'chart.svg', 'inline': true},
          result: _fileResult(path: '/work/chart.svg', inline: true),
        ),
      );

      check(records).length.equals(1);
      check(records.single.path).equals('/work/chart.svg');
      check(records.single.displayed).isTrue();
    });

    test('skips a file that does not exist', () {
      check(
        openTerminalFilesFromOutput(
          _displayFileTrace(result: _fileResult(exists: false)),
        ),
      ).isEmpty();
    });

    test('skips results that are not an Open Terminal file', () {
      for (final result in <Map<String, dynamic>>[
        // A plain Open Terminal response, before the server rewrites it.
        {'path': '/work/a.html', 'exists': true},
        {..._fileResult(), 'source': 'other'},
        {..._fileResult(), 'type': 'text'},
        {..._fileResult(), 'terminal_selector': ''},
        {..._fileResult(), 'path': ''},
      ]) {
        check(openTerminalFilesFromOutput(_displayFileTrace(result: result)))
            .isEmpty();
      }
    });

    test('ignores other tools and results with no call', () {
      check(
        openTerminalFilesFromOutput(
          _displayFileTrace(name: 'write_file', result: _fileResult()),
        ),
      ).isEmpty();
      check(
        openTerminalFilesFromOutput([
          _displayFileTrace(result: _fileResult())[1],
        ]),
      ).isEmpty();
      check(openTerminalFilesFromOutput(null)).isEmpty();
    });

    test('takes the page from the arguments when the result has none', () {
      final records = openTerminalFilesFromOutput(
        _displayFileTrace(
          arguments: const {'path': 'doc.pdf', 'page': 4},
          result: _fileResult(path: '/work/doc.pdf'),
        ),
      );
      check(records.single.page).equals(4);
    });

    test('reads a direct terminal server and double-encoded arguments', () {
      final trace = _displayFileTrace(
        result: _fileResult(
          extra: const {
            'terminal_id': null,
            'terminal_url': 'https://terminal.example/',
            'terminal_selector': 'https://terminal.example/',
          },
        ),
      );
      trace.first['arguments'] = jsonEncode(trace.first['arguments']);

      final record = openTerminalFilesFromOutput(trace).single;
      check(record.terminalId).isNull();
      check(record.terminalUrl).equals('https://terminal.example/');
    });

    test('ignores image parts of the result', () {
      final trace = _displayFileTrace(result: _fileResult());
      (trace.last['output'] as List).add({
        'type': 'input_image',
        'image_url': '/api/v1/files/x/content',
      });
      check(openTerminalFilesFromOutput(trace)).length.equals(1);
    });

    test('keeps every file in order', () {
      final first = _displayFileTrace(
        callId: 'a',
        result: _fileResult(path: '/work/a.html'),
      );
      final second = _displayFileTrace(
        callId: 'b',
        result: _fileResult(path: '/work/b.svg'),
      );
      check(
        openTerminalFilesFromOutput([first[0], second[0], first[1], second[1]])
            .map((record) => record.path)
            .toList(),
      ).deepEquals(['/work/a.html', '/work/b.svg']);
    });
  });
}
