import 'dart:convert';

/// A workspace file Open Terminal's `display_file` tool showed, as Open WebUI
/// records it in the chat.
///
/// Open WebUI 0.12 rewrites a `display_file` result
/// (`build_terminal_file_tool_result`) to
/// `{type: 'file', source: 'open_terminal', path, full_path, name, mime_type,
/// content_type, terminal_selector, terminal_id | terminal_url, session_id,
/// displayed?, page?}` and stores it as the JSON text of the call's
/// `function_call_output`. This record survives a reload, and it is the only
/// trace of `display_file(inline: true)`, which sends no socket event.
final class OpenTerminalFileRecord {
  const OpenTerminalFileRecord({
    required this.path,
    required this.name,
    required this.terminalSelector,
    this.fullPath,
    this.mimeType,
    this.terminalId,
    this.terminalUrl,
    this.sessionId,
    this.page,
    this.displayed = false,
    this.callId,
  });

  /// The path Open Terminal resolved against the session's working directory.
  final String path;
  final String name;

  /// `terminal_id` or `terminal_url`, whichever identifies the terminal.
  final String terminalSelector;
  final String? fullPath;
  final String? mimeType;

  /// Id of a system terminal (`/api/v1/terminals/{id}`).
  final String? terminalId;

  /// Base URL of a direct terminal server.
  final String? terminalUrl;
  final String? sessionId;
  final int? page;

  /// Whether the model asked for the file to be shown inline.
  final bool displayed;
  final String? callId;
}

/// Files shown by `display_file` calls in an Open WebUI `output` list, in
/// order.
///
/// Mirrors the web client's `getInlineFileFromToolOutput`
/// (`structuredOutput.ts`): the call must be `display_file`, and its result
/// must be a `file` from `open_terminal` with a `path` and a
/// `terminal_selector`. A result reporting `exists: false` is skipped.
List<OpenTerminalFileRecord> openTerminalFilesFromOutput(
  List<dynamic>? output,
) {
  if (output == null || output.isEmpty) return const [];

  final callsById = <String, Map<dynamic, dynamic>>{};
  for (final item in output) {
    if (item is! Map || item['type'] != 'function_call') continue;
    final id = (item['call_id'] ?? item['id'])?.toString();
    if (id != null && id.isNotEmpty) callsById[id] = item;
  }
  if (callsById.isEmpty) return const [];

  final records = <OpenTerminalFileRecord>[];
  for (final item in output) {
    if (item is! Map || item['type'] != 'function_call_output') continue;
    final callId = item['call_id']?.toString();
    final call = callId == null ? null : callsById[callId];
    if (call == null || call['name'] != 'display_file') continue;

    final args = _decodeJsonValue(call['arguments']);
    if (args is! Map) continue;
    final result = _decodeJsonValue(_toolResultText(item['output']));
    if (result is! Map ||
        result['type'] != 'file' ||
        result['source'] != 'open_terminal' ||
        result['exists'] == false) {
      continue;
    }
    final path = _nonEmptyString(result['path']);
    final selector = _nonEmptyString(result['terminal_selector']);
    if (path == null || selector == null) continue;

    records.add(
      OpenTerminalFileRecord(
        path: path,
        name: _nonEmptyString(result['name']) ?? _basename(path),
        terminalSelector: selector,
        fullPath: _nonEmptyString(result['full_path']),
        mimeType:
            _nonEmptyString(result['mime_type']) ??
            _nonEmptyString(result['content_type']),
        terminalId: _nonEmptyString(result['terminal_id']),
        terminalUrl: _nonEmptyString(result['terminal_url']),
        sessionId: _nonEmptyString(result['session_id']),
        page: _positiveInt(result['page']) ?? _positiveInt(args['page']),
        displayed: result['displayed'] == true,
        callId: callId,
      ),
    );
  }
  return List<OpenTerminalFileRecord>.unmodifiable(records);
}

/// The text of a tool result's output parts, without its images: what the
/// web client parses as the result.
String _toolResultText(Object? output) {
  if (output is String) return output;
  if (output is! List) return '';
  final buffer = StringBuffer();
  for (final part in output) {
    if (part is! Map || part['type'] == 'input_image') continue;
    final text = part['text'];
    if (text != null) buffer.write(text is String ? text : text.toString());
  }
  return buffer.toString();
}

/// Decodes JSON text until it is no longer a string, as the web client does
/// (tool arguments can arrive double-encoded).
Object? _decodeJsonValue(Object? value) {
  if (value is! String) return value;
  Object? decoded = value.trim();
  while (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      break;
    }
  }
  return decoded;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _positiveInt(Object? value) {
  final parsed = value is int
      ? value
      : value is num
      ? value.toInt()
      : int.tryParse('${value ?? ''}');
  return parsed != null && parsed > 0 ? parsed : null;
}

String _basename(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}
