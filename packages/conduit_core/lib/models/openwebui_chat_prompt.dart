import 'dart:convert';

import 'chat_message.dart';

import 'package:meta/meta.dart';

enum OpenWebUiComposerPromptKind { askUser, toolApproval, confirmation }

enum OpenWebUiToolCallAction { approve, reject, answer }

@immutable
class OpenWebUiPromptOption {
  const OpenWebUiPromptOption({required this.label, required this.description});

  final String label;
  final String description;
}

@immutable
class OpenWebUiPromptQuestion {
  const OpenWebUiPromptQuestion({
    required this.id,
    required this.header,
    required this.question,
    required this.options,
    required this.allowOther,
  });

  final String id;
  final String header;
  final String question;
  final List<OpenWebUiPromptOption> options;
  final bool allowOther;
}

@immutable
class OpenWebUiComposerPrompt {
  const OpenWebUiComposerPrompt({
    required this.identity,
    required this.kind,
    this.title = '',
    this.message = '',
    this.questions = const <OpenWebUiPromptQuestion>[],
    this.timeout = const Duration(minutes: 2),
    this.confirmText,
    this.cancelText,
    this.messageIsCode = false,
  });

  final String identity;
  final OpenWebUiComposerPromptKind kind;
  final String title;
  final String message;
  final List<OpenWebUiPromptQuestion> questions;

  /// How long the client keeps the prompt open before answering it as
  /// cancelled. Null keeps it open until it is answered or its stream ends: the
  /// server waits on a plain `confirmation` for as long as its
  /// `WEBSOCKET_EVENT_CALLER_TIMEOUT` allows, so a client deadline would only
  /// deny it silently.
  final Duration? timeout;

  /// The server's own labels for the decision buttons (`confirm_text` /
  /// `cancel_text`), or null for the app's defaults.
  final String? confirmText;
  final String? cancelText;

  /// Whether [message] is formatted tool-call arguments (shown as code) rather
  /// than prose.
  final bool messageIsCode;
}

@immutable
class OpenWebUiPendingToolPrompt {
  const OpenWebUiPendingToolPrompt({
    required this.messageId,
    required this.callId,
    required this.toolName,
    required this.prompt,
  });

  final String messageId;
  final String callId;
  final String toolName;
  final OpenWebUiComposerPrompt prompt;
}

String boundedOpenWebUiString(Object? value, int maxLength) {
  final normalized = value?.toString().trim() ?? '';
  if (normalized.length <= maxLength) return normalized;
  var end = maxLength;
  final last = normalized.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return normalized.substring(0, end);
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

Map<String, dynamic>? _decodeArguments(Object? value) {
  Object? current = value;
  for (var attempt = 0; attempt < 3 && current is String; attempt++) {
    try {
      current = jsonDecode(current);
    } catch (_) {
      return null;
    }
  }
  return _stringMap(current);
}

OpenWebUiComposerPrompt? parseOpenWebUiAskUserPrompt(
  Object? value, {
  required String identity,
}) {
  final data = _stringMap(value);
  final rawQuestions = data?['questions'];
  if (data == null || rawQuestions is! List || rawQuestions.length > 3) {
    return null;
  }
  if (rawQuestions.isEmpty) return null;

  final defaultAllowOther = data['allow_other'] is bool
      ? data['allow_other'] as bool
      : true;
  final seenIds = <String>{};
  final questions = <OpenWebUiPromptQuestion>[];
  for (var index = 0; index < rawQuestions.length; index++) {
    final rawQuestion = _stringMap(rawQuestions[index]);
    final rawOptions = rawQuestion?['options'];
    if (rawQuestion == null ||
        rawOptions is! List ||
        rawOptions.length < 2 ||
        rawOptions.length > 3) {
      return null;
    }

    final id = boundedOpenWebUiString(rawQuestion['id'], 64);
    final question = boundedOpenWebUiString(rawQuestion['question'], 500);
    if (id.isEmpty || question.isEmpty || !seenIds.add(id)) return null;

    final options = <OpenWebUiPromptOption>[];
    for (final rawOption in rawOptions) {
      final option = _stringMap(rawOption);
      final label = boundedOpenWebUiString(option?['label'], 80);
      final description = boundedOpenWebUiString(option?['description'], 240);
      if (option == null || label.isEmpty || description.isEmpty) return null;
      options.add(
        OpenWebUiPromptOption(label: label, description: description),
      );
    }

    questions.add(
      OpenWebUiPromptQuestion(
        id: id,
        header: boundedOpenWebUiString(rawQuestion['header'], 48).isEmpty
            ? 'Question ${index + 1}'
            : boundedOpenWebUiString(rawQuestion['header'], 48),
        question: question,
        options: List<OpenWebUiPromptOption>.unmodifiable(options),
        allowOther: rawQuestion['allow_other'] is bool
            ? rawQuestion['allow_other'] as bool
            : defaultAllowOther,
      ),
    );
  }

  final rawTimeout = data['timeout_ms'];
  final timeoutMs =
      rawTimeout is int && rawTimeout >= 60000 && rawTimeout <= 240000
      ? rawTimeout
      : 120000;
  return OpenWebUiComposerPrompt(
    identity: identity,
    kind: OpenWebUiComposerPromptKind.askUser,
    questions: List<OpenWebUiPromptQuestion>.unmodifiable(questions),
    timeout: Duration(milliseconds: timeoutMs),
  );
}

OpenWebUiPendingToolPrompt? findPendingOpenWebUiToolPrompt(
  List<ChatMessage> messages,
) {
  for (final message in messages.reversed) {
    if (message.role != 'assistant' || message.output == null) continue;
    final resultCallIds = <String>{
      for (final item in message.output!)
        if (item['type']?.toString() == 'function_call_output' &&
            (item['call_id']?.toString().isNotEmpty ?? false))
          item['call_id'].toString().trim(),
    };
    for (final item in message.output!) {
      if (item['type']?.toString() != 'function_call') continue;
      final callId =
          item['call_id']?.toString().trim() ??
          item['id']?.toString().trim() ??
          '';
      final status = item['status']?.toString();
      if (callId.isEmpty ||
          resultCallIds.contains(callId) ||
          (status != 'pending' &&
              status != 'queued' &&
              status != 'requires_approval') ||
          (status == 'queued' && item['approved'] == true)) {
        continue;
      }

      final name = boundedOpenWebUiString(item['name'], 80);
      if (name == 'ask_user') {
        final arguments = _decodeArguments(item['arguments']);
        final prompt = parseOpenWebUiAskUserPrompt(
          arguments,
          identity: 'saved:${message.id}:$callId',
        );
        if (prompt == null) continue;
        return OpenWebUiPendingToolPrompt(
          messageId: message.id,
          callId: callId,
          toolName: name,
          prompt: prompt,
        );
      }

      final arguments = formatOpenWebUiToolArguments(item['arguments']);
      return OpenWebUiPendingToolPrompt(
        messageId: message.id,
        callId: callId,
        toolName: name.isEmpty ? 'Tool' : name,
        prompt: OpenWebUiComposerPrompt(
          identity: 'saved:${message.id}:$callId',
          kind: OpenWebUiComposerPromptKind.toolApproval,
          title: name.isEmpty ? 'Tool' : name,
          message: arguments,
        ),
      );
    }
  }
  return null;
}

/// The title and message a socket `confirmation` request shows.
///
/// A tool call awaiting approval in a chat that is not saved (tool approval
/// "ask") carries only `tool_call: {id, name, arguments}` and no text, so it
/// is shown as a saved approval is: the tool's name over its arguments.
///
/// Neither is shortened: the user approves exactly what the server acts on
/// (an outgoing message body, a tool's full arguments), and a cut text would
/// ask for consent to something partly unseen. Question forms keep their
/// bounds ([parseOpenWebUiAskUserPrompt]).
({String title, String message}) openWebUiConfirmationText(
  Map<String, dynamic> data,
) {
  final toolCall = _stringMap(data['tool_call']);
  if (toolCall != null) {
    final name = boundedOpenWebUiString(toolCall['name'], 80);
    return (
      title: name.isEmpty ? 'Tool' : name,
      message: formatOpenWebUiToolArguments(toolCall['arguments']),
    );
  }
  return (
    title: data['title']?.toString().trim() ?? '',
    message: data['message']?.toString().trim() ?? '',
  );
}

/// How long a tool call awaiting approval stays open when the request does
/// not say: the server's own default.
const Duration kOpenWebUiToolApprovalDefaultTimeout = Duration(minutes: 2);

/// The composer prompt for a socket `confirmation` request.
///
/// A plain confirmation (`title` / `message`, optional `confirm_text` /
/// `cancel_text`) has no client deadline. A tool call awaiting approval
/// honours `timeout_ms` clamped to 60–240 s, as the server clamps the time it
/// waits for this client (`socket/main.py` `get_event_call`).
OpenWebUiComposerPrompt parseOpenWebUiConfirmationPrompt(
  Map<String, dynamic> data, {
  required String identity,
}) {
  final text = openWebUiConfirmationText(data);
  final isToolCall = _stringMap(data['tool_call']) != null;
  Duration? timeout;
  if (isToolCall) {
    final rawTimeout = data['timeout_ms'];
    timeout = rawTimeout is int
        ? Duration(milliseconds: rawTimeout.clamp(60000, 240000))
        : kOpenWebUiToolApprovalDefaultTimeout;
  }
  String? label(Object? value) {
    final normalized = boundedOpenWebUiString(value, 80);
    return normalized.isEmpty ? null : normalized;
  }

  return OpenWebUiComposerPrompt(
    identity: identity,
    kind: OpenWebUiComposerPromptKind.confirmation,
    title: text.title,
    message: text.message,
    timeout: timeout,
    confirmText: label(data['confirm_text']),
    cancelText: label(data['cancel_text']),
    messageIsCode: isToolCall,
  );
}

String formatOpenWebUiToolArguments(Object? value) {
  Object? normalized = value;
  if (value is String) {
    try {
      normalized = jsonDecode(value);
    } catch (_) {}
  }
  String text;
  try {
    text = normalized is Map || normalized is List
        ? const JsonEncoder.withIndent('  ').convert(normalized)
        : normalized?.toString() ?? '';
  } catch (_) {
    text = normalized.toString();
  }
  // Not shortened: these are the arguments the user approves.
  return text.trim();
}

List<Map<String, dynamic>> applyOpenWebUiToolCallResolution({
  required List<Map<String, dynamic>> output,
  required String callId,
  required String action,
  Map<String, dynamic>? answers,
}) {
  final normalizedCallId = callId.trim();
  if (normalizedCallId.isEmpty) return output;
  final next = output
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: true);
  final callIndex = next.indexWhere(
    (item) =>
        item['type']?.toString() == 'function_call' &&
        (item['call_id']?.toString().trim() ?? item['id']?.toString().trim()) ==
            normalizedCallId,
  );
  if (callIndex == -1) return output;

  final call = next[callIndex];
  switch (action) {
    case 'approve':
      call['status'] = 'queued';
      call['approved'] = true;
      break;
    case 'reject':
      call['status'] = 'rejected';
      next.add({
        'type': 'function_call_output',
        'id': 'fco_$callId',
        'call_id': callId,
        'output': const [
          {'type': 'input_text', 'text': 'Error: tool call rejected by user.'},
        ],
        'status': 'rejected',
      });
      break;
    case 'answer':
      call['status'] = 'completed';
      next.add({
        'type': 'function_call_output',
        'id': 'fco_$callId',
        'call_id': callId,
        'output': [
          {
            'type': 'input_text',
            'text': jsonEncode({
              'status': 'answered',
              'answers': answers ?? const <String, dynamic>{},
            }),
          },
        ],
        'status': 'completed',
      });
      break;
  }
  return List<Map<String, dynamic>>.unmodifiable(next);
}
