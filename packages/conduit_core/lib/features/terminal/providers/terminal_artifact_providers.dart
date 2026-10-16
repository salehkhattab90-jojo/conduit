import 'package:riverpod/riverpod.dart';

import '../../../services/terminal_file_output.dart';
import '../models/terminal_models.dart';
import '../services/terminal_service.dart';

/// A terminal workspace file an assistant message shows as an artifact card.
final class TerminalArtifactRef {
  const TerminalArtifactRef({
    required this.path,
    required this.name,
    this.page,
    this.terminalId,
    this.terminalUrl,
  });

  factory TerminalArtifactRef.fromRecord(OpenTerminalFileRecord record) =>
      TerminalArtifactRef(
        path: record.path,
        name: record.name,
        page: record.page,
        terminalId: record.terminalId,
        terminalUrl: record.terminalUrl,
      );

  /// A `terminal:display_file` event: only the resolved path and the page.
  factory TerminalArtifactRef.fromPath(String path, {int? page}) {
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty);
    return TerminalArtifactRef(
      path: path,
      name: parts.isEmpty ? path : parts.last,
      page: page != null && page > 0 ? page : null,
    );
  }

  final String path;
  final String name;
  final int? page;

  /// The terminal the file lives in, when the stored record names it.
  final String? terminalId;
  final String? terminalUrl;

  /// Identity of the file: two refs with the same key are one card.
  String get key => normalizeTerminalPath(path);

  @override
  bool operator ==(Object other) =>
      other is TerminalArtifactRef &&
      other.path == path &&
      other.name == name &&
      other.page == page &&
      other.terminalId == terminalId &&
      other.terminalUrl == terminalUrl;

  @override
  int get hashCode => Object.hash(path, name, page, terminalId, terminalUrl);
}

/// The artifact cards of one message: the files its stored `display_file`
/// results record, then the files only the live socket events reported,
/// one card per resolved path.
List<TerminalArtifactRef> terminalArtifactsForMessage({
  required List<dynamic>? output,
  Iterable<TerminalArtifactRef> live = const [],
}) {
  final byKey = <String, TerminalArtifactRef>{};
  for (final record in openTerminalFilesFromOutput(output)) {
    final ref = TerminalArtifactRef.fromRecord(record);
    byKey.putIfAbsent(ref.key, () => ref);
  }
  for (final ref in live) {
    byKey.putIfAbsent(ref.key, () => ref);
  }
  return List<TerminalArtifactRef>.unmodifiable(byKey.values);
}

/// The terminal to read [artifact] from.
///
/// A stored record names its terminal (`terminal_id` for a system terminal,
/// `terminal_url` for a direct server); that terminal is used, and when it is
/// no longer available there is none, so a file at the same path in another
/// terminal is never shown in its place. A file known only from a live
/// event has no terminal named and opens in the [selected] one, which is the
/// one the chat's tools ran against.
TerminalServerInfo? resolveTerminalServerForArtifact(
  TerminalArtifactRef artifact, {
  required List<TerminalServerInfo> servers,
  required TerminalServerInfo? selected,
}) {
  final terminalId = artifact.terminalId;
  final terminalUrl = artifact.terminalUrl;
  if (terminalId == null && terminalUrl == null) return selected;

  if (terminalId != null) {
    for (final server in servers) {
      if (server.isSystem && server.systemServerId == terminalId) {
        return server;
      }
    }
  }
  if (terminalUrl != null) {
    final wanted = _withoutTrailingSlashes(terminalUrl);
    for (final server in servers) {
      if (server.isDirect &&
          (_withoutTrailingSlashes(server.selectionId) == wanted ||
              _withoutTrailingSlashes(server.baseUrl.toString()) == wanted)) {
        return server;
      }
    }
  }
  return null;
}

String _withoutTrailingSlashes(String value) =>
    value.trim().replaceFirst(RegExp(r'/+$'), '');

/// Files `terminal:display_file` events reported, per assistant message id.
///
/// The stored `display_file` record covers native tool calling after a
/// reload; this keeps the card for the turn that is streaming and for
/// default-mode tool calls, whose results carry no such record. It is keyed
/// by message id and kept outside the message, so a server re-sync that
/// replaces the message does not drop it.
class TerminalLiveArtifactsNotifier
    extends Notifier<Map<String, List<TerminalArtifactRef>>> {
  /// Messages remembered at most; the oldest are forgotten first.
  static const int maxMessages = 200;

  @override
  Map<String, List<TerminalArtifactRef>> build() => const {};

  /// Records what a `terminal:*` event for [messageId] showed.
  void handleEvent(String messageId, String type, Map<String, dynamic> data) {
    if (type != 'terminal:display_file') return;
    final path = data['path'] is String ? (data['path'] as String).trim() : '';
    if (path.isEmpty) return;
    final rawPage = data['page'];
    final page = rawPage is int ? rawPage : int.tryParse('${rawPage ?? ''}');
    record(messageId, TerminalArtifactRef.fromPath(path, page: page));
  }

  void record(String messageId, TerminalArtifactRef artifact) {
    if (messageId.isEmpty || artifact.path.trim().isEmpty) return;
    final existing = state[messageId] ?? const <TerminalArtifactRef>[];
    if (existing.any((ref) => ref.key == artifact.key)) return;
    final next = Map<String, List<TerminalArtifactRef>>.of(state)
      ..remove(messageId);
    next[messageId] = List<TerminalArtifactRef>.unmodifiable([
      ...existing,
      artifact,
    ]);
    while (next.length > maxMessages) {
      next.remove(next.keys.first);
    }
    state = Map<String, List<TerminalArtifactRef>>.unmodifiable(next);
  }
}

final terminalLiveArtifactsProvider =
    NotifierProvider<
      TerminalLiveArtifactsNotifier,
      Map<String, List<TerminalArtifactRef>>
    >(TerminalLiveArtifactsNotifier.new);
