import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:conduit_core/features/terminal/models/terminal_models.dart';
import 'package:conduit_core/features/terminal/providers/terminal_artifact_providers.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

List<Map<String, dynamic>> _storedDisplayFile(
  String path, {
  String callId = 'call_1',
  String terminalId = 'term-1',
}) => [
  {
    'type': 'function_call',
    'call_id': callId,
    'name': 'display_file',
    'arguments': jsonEncode({'path': path.split('/').last}),
  },
  {
    'type': 'function_call_output',
    'call_id': callId,
    'output': [
      {
        'type': 'input_text',
        'text': jsonEncode({
          'type': 'file',
          'source': 'open_terminal',
          'path': path,
          'name': path.split('/').last,
          'terminal_selector': terminalId,
          'terminal_id': terminalId,
        }),
      },
    ],
  },
];

TerminalServerInfo _system(String id) => TerminalServerInfo(
  kind: TerminalServerKind.system,
  selectionId: id,
  systemServerId: id,
  baseUrl: Uri.parse('https://owui.example/api/v1/terminals/$id'),
);

TerminalServerInfo _direct(String url) => TerminalServerInfo(
  kind: TerminalServerKind.direct,
  selectionId: url,
  baseUrl: Uri.parse(url.replaceFirst(RegExp(r'/+$'), '')),
);

void main() {
  group('terminalArtifactsForMessage', () {
    test('one card per resolved path across the record and live events', () {
      final artifacts = terminalArtifactsForMessage(
        output: [
          ..._storedDisplayFile('/work/report.html'),
          ..._storedDisplayFile('/work/chart.svg', callId: 'call_2'),
        ],
        live: [
          TerminalArtifactRef.fromPath('/work//report.html'),
          TerminalArtifactRef.fromPath('/work/notes.txt', page: 2),
        ],
      );

      check(
        artifacts.map((artifact) => artifact.path).toList(),
      ).deepEquals(['/work/report.html', '/work/chart.svg', '/work/notes.txt']);
      // The stored record wins: it names the terminal.
      check(artifacts.first.terminalId).equals('term-1');
      check(artifacts.last.page).equals(2);
    });

    test('live events alone still give cards', () {
      check(
        terminalArtifactsForMessage(
          output: null,
          live: [TerminalArtifactRef.fromPath('/work/a.html')],
        ).single.name,
      ).equals('a.html');
    });
  });

  group('TerminalLiveArtifactsNotifier', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    TerminalLiveArtifactsNotifier notifier() =>
        container.read(terminalLiveArtifactsProvider.notifier);

    test('records display_file paths per message, once each', () {
      notifier()
        ..handleEvent('msg-1', 'terminal:display_file', {'path': ' /w/a.html '})
        ..handleEvent('msg-1', 'terminal:display_file', {'path': '/w/a.html'})
        ..handleEvent('msg-1', 'terminal:display_file', {
          'path': '/w/b.pdf',
          'page': '3',
        })
        ..handleEvent('msg-2', 'terminal:display_file', {'path': '/w/c.svg'})
        ..handleEvent('msg-1', 'terminal:write_file', {'path': '/w/d.txt'})
        ..handleEvent('msg-1', 'terminal:display_file', {'path': ''});

      final state = container.read(terminalLiveArtifactsProvider);
      check(state['msg-1']!.map((artifact) => artifact.path).toList())
          .deepEquals(['/w/a.html', '/w/b.pdf']);
      check(state['msg-1']!.last.page).equals(3);
      check(state['msg-2']!.single.path).equals('/w/c.svg');
    });

    test('forgets the oldest messages past the limit', () {
      for (var i = 0; i <= TerminalLiveArtifactsNotifier.maxMessages; i++) {
        notifier().handleEvent('msg-$i', 'terminal:display_file', {
          'path': '/w/$i.html',
        });
      }

      final state = container.read(terminalLiveArtifactsProvider);
      check(state.length).equals(TerminalLiveArtifactsNotifier.maxMessages);
      check(state.containsKey('msg-0')).isFalse();
      check(
        state.containsKey('msg-${TerminalLiveArtifactsNotifier.maxMessages}'),
      ).isTrue();
    });
  });

  group('resolveTerminalServerForArtifact', () {
    final selected = _system('selected');
    final servers = [
      selected,
      _system('term-1'),
      _direct('https://terminal.example'),
    ];

    test('opens a live-only file in the selected terminal', () {
      check(
        resolveTerminalServerForArtifact(
          TerminalArtifactRef.fromPath('/w/a.html'),
          servers: servers,
          selected: selected,
        ),
      ).identicalTo(selected);
    });

    test('opens a stored file in the terminal it names', () {
      check(
        resolveTerminalServerForArtifact(
          const TerminalArtifactRef(
            path: '/w/a.html',
            name: 'a.html',
            terminalId: 'term-1',
          ),
          servers: servers,
          selected: selected,
        ),
      ).identicalTo(servers[1]);
      check(
        resolveTerminalServerForArtifact(
          const TerminalArtifactRef(
            path: '/w/a.html',
            name: 'a.html',
            terminalUrl: 'https://terminal.example/',
          ),
          servers: servers,
          selected: selected,
        ),
      ).identicalTo(servers[2]);
    });

    test('never substitutes another terminal for a missing one', () {
      check(
        resolveTerminalServerForArtifact(
          const TerminalArtifactRef(
            path: '/w/a.html',
            name: 'a.html',
            terminalId: 'gone',
          ),
          servers: servers,
          selected: selected,
        ),
      ).isNull();
    });
  });
}
