import 'package:flutter/foundation.dart';

/// Durable, in-memory store of Open Terminal `display_file` artifact paths,
/// keyed by assistant message id.
///
/// This lives OUTSIDE the chat message object on purpose. The artifact signal is
/// client-only — the server's copy of the message doesn't carry it — so storing
/// it on the message metadata meant a server re-sync (which happens on scroll /
/// chat reload) replaced the message and wiped it, and the card vanished. Keyed
/// by message id here, it survives those re-syncs for the life of the session.
class TerminalArtifactStore extends ChangeNotifier {
  final Map<String, List<String>> _byMessage = <String, List<String>>{};

  List<String> pathsFor(String messageId) =>
      _byMessage[messageId] ?? const <String>[];

  void add(String messageId, String path) {
    if (messageId.isEmpty || path.isEmpty) return;
    final list = _byMessage.putIfAbsent(messageId, () => <String>[]);
    if (list.contains(path)) return;
    list.add(path);
    notifyListeners();
  }
}

/// Process-wide singleton. The streaming layer (which has no Riverpod `Ref`)
/// writes to it directly; message widgets read it reactively via a
/// [ListenableBuilder] on this instance.
final terminalArtifactStore = TerminalArtifactStore();
