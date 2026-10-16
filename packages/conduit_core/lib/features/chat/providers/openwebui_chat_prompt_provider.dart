import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:meta/meta.dart';

import 'package:conduit_core/models/openwebui_chat_prompt.dart';

@visibleForTesting
Duration? debugOpenWebUiPromptTimeoutOverride;

@immutable
class OpenWebUiLivePromptState {
  const OpenWebUiLivePromptState({
    required this.conversationId,
    required this.prompt,
  });

  final String conversationId;
  final OpenWebUiComposerPrompt prompt;
}

final openWebUiLivePromptProvider =
    NotifierProvider<OpenWebUiLivePromptNotifier, OpenWebUiLivePromptState?>(
      OpenWebUiLivePromptNotifier.new,
    );

/// One server request waiting for the user, in arrival order.
class _QueuedPrompt {
  _QueuedPrompt({
    required this.conversationId,
    required this.owner,
    required this.prompt,
    required void Function(dynamic response) acknowledge,
  }) : _acknowledge = acknowledge;

  final String conversationId;

  /// The stream that received the request, so its teardown can answer the
  /// requests it still holds. Null when the caller did not say.
  final Object? owner;
  final OpenWebUiComposerPrompt prompt;
  void Function(dynamic response)? _acknowledge;
  Timer? deadline;

  /// The answer that declines this request: `false` for a confirmation, a
  /// cancelled answer for a question form.
  dynamic get cancelResponse =>
      prompt.kind == OpenWebUiComposerPromptKind.confirmation
      ? false
      : const <String, dynamic>{'status': 'cancelled', 'answers': {}};

  /// Takes the acknowledgement, at most once: whoever takes it answers.
  void Function(dynamic response)? take() {
    final acknowledge = _acknowledge;
    _acknowledge = null;
    deadline?.cancel();
    deadline = null;
    return acknowledge;
  }
}

/// Server requests that wait for the user (`request:user_input` question
/// forms and `confirmation` prompts), shown one at a time in arrival order.
///
/// The state is the request on screen, the head of the queue. Every request
/// is answered exactly once: by the user, by its deadline, or as declined when
/// its conversation is left, the stream that received it ends, or the account
/// changes. A request cancelled while still queued is answered then and never
/// shown. A request delivered twice (one socket event fanned out to two
/// listeners shares one acknowledgement) is queued once.
class OpenWebUiLivePromptNotifier extends Notifier<OpenWebUiLivePromptState?> {
  final List<_QueuedPrompt> _queue = <_QueuedPrompt>[];
  final Expando<bool> _seenAcknowledgements = Expando<bool>(
    'openwebui-prompt-ack',
  );
  int _nextIdentity = 0;

  @override
  OpenWebUiLivePromptState? build() {
    ref.onDispose(_abandonAll);
    return null;
  }

  /// Requests waiting behind the one on screen.
  @visibleForTesting
  int get queuedCount => _queue.isEmpty ? 0 : _queue.length - 1;

  void handleSocketRequest({
    required String conversationId,
    required String type,
    required Map<String, dynamic> data,
    required void Function(dynamic response) acknowledge,
    Object? owner,
  }) {
    if (_seenAcknowledgements[acknowledge] == true) return;
    _seenAcknowledgements[acknowledge] = true;

    final identity =
        'live:${DateTime.now().microsecondsSinceEpoch}:${_nextIdentity++}';
    final OpenWebUiComposerPrompt prompt;
    if (type == 'request:user_input') {
      final parsed = parseOpenWebUiAskUserPrompt(data, identity: identity);
      if (parsed == null) {
        _safeAcknowledge(acknowledge, const <String, dynamic>{
          'error': 'Invalid user input request.',
        });
        return;
      }
      prompt = parsed;
    } else if (type == 'confirmation') {
      prompt = parseOpenWebUiConfirmationPrompt(data, identity: identity);
    } else {
      _safeAcknowledge(acknowledge, const <String, dynamic>{
        'error': 'Unsupported input request.',
      });
      return;
    }

    final entry = _QueuedPrompt(
      conversationId: conversationId,
      owner: owner,
      prompt: prompt,
      acknowledge: acknowledge,
    );
    // The server's wait starts when it sends the request, so a deadline runs
    // from arrival, also while the request is queued behind another.
    final timeout = prompt.timeout;
    if (timeout != null) {
      entry.deadline = Timer(
        debugOpenWebUiPromptTimeoutOverride ?? timeout,
        () => _settle(<_QueuedPrompt>[entry], cancel: true),
      );
    }
    _queue.add(entry);
    _publish();
  }

  void answer(String promptIdentity, Map<String, dynamic> answers) {
    final current = _current;
    if (current == null || current.prompt.identity != promptIdentity) return;
    _settle(
      <_QueuedPrompt>[current],
      response: <String, dynamic>{'status': 'answered', 'answers': answers},
    );
  }

  void decide(String promptIdentity, bool approved) {
    final current = _current;
    if (current == null ||
        current.prompt.identity != promptIdentity ||
        current.prompt.kind != OpenWebUiComposerPromptKind.confirmation) {
      return;
    }
    _settle(<_QueuedPrompt>[current], response: approved);
  }

  /// Declines the request on screen, if it is [promptIdentity], and shows the
  /// next one.
  void dismiss(String promptIdentity) {
    final current = _current;
    if (current == null || current.prompt.identity != promptIdentity) return;
    _settle(<_QueuedPrompt>[current], cancel: true);
  }

  /// Declines every request of [conversationId], on screen or queued.
  void cancelForConversation(String? conversationId) {
    if (conversationId == null) return;
    _settle(
      _queue.where((entry) => entry.conversationId == conversationId).toList(),
      cancel: true,
    );
  }

  /// Declines every request [owner] received: its stream has ended, so no
  /// answer given later could still reach the turn that asked.
  void cancelForOwner(Object owner) {
    _settle(
      _queue.where((entry) => identical(entry.owner, owner)).toList(),
      cancel: true,
    );
  }

  /// Declines every request, on screen or queued.
  void cancel() => _settle(List<_QueuedPrompt>.of(_queue), cancel: true);

  _QueuedPrompt? get _current => _queue.isEmpty ? null : _queue.first;

  void _settle(
    List<_QueuedPrompt> entries, {
    dynamic response,
    bool cancel = false,
  }) {
    if (entries.isEmpty) return;
    final answers = <(void Function(dynamic), dynamic)>[];
    for (final entry in entries) {
      _queue.remove(entry);
      final acknowledge = entry.take();
      if (acknowledge != null) {
        answers.add((acknowledge, cancel ? entry.cancelResponse : response));
      }
    }
    // The surface moves on before the server hears back, as it always has.
    _publish();
    for (final (acknowledge, reply) in answers) {
      _safeAcknowledge(acknowledge, reply);
    }
  }

  void _publish() {
    final current = _current;
    if (current == null) {
      if (state != null) state = null;
      return;
    }
    if (identical(state?.prompt, current.prompt)) return;
    state = OpenWebUiLivePromptState(
      conversationId: current.conversationId,
      prompt: current.prompt,
    );
  }

  void _abandonAll() {
    final entries = List<_QueuedPrompt>.of(_queue);
    _queue.clear();
    for (final entry in entries) {
      final acknowledge = entry.take();
      if (acknowledge != null) {
        _safeAcknowledge(acknowledge, entry.cancelResponse);
      }
    }
  }

  void _safeAcknowledge(
    void Function(dynamic response) acknowledge,
    dynamic response,
  ) {
    try {
      acknowledge(response);
    } catch (_) {}
  }
}
