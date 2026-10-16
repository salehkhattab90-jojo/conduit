// Rewrites the product name inside the app's translated strings.
//
//   dart run tool/apply_brand_strings.dart --name "Acme Chat" [--dry-run]
//
// A branded build changes "Conduit" in the user-visible text of every
// `lib/l10n/app_*.arb` file to its own name. Only message values change:
// never a key, never an `@key` description, never a `{placeholder}` name.
// The rest of each file is left byte for byte, so the diff against upstream
// is just the renamed words and an upstream sync merges as usual; run the
// tool again after each sync. Running it twice changes nothing the second
// time. The ARB files are the source; `flutter gen-l10n` (or any build)
// regenerates the Dart localizations from them.
//
// The base branch never runs it: the base keeps upstream's strings.
import 'dart:io';

/// The word the upstream strings use for the product.
const kUpstreamProductName = 'Conduit';

/// [source], the text of one ARB file, with [from] renamed to [to] in its
/// message values. Returns [source] unchanged when there is nothing to do.
String applyBrandToArb(
  String source, {
  required String to,
  String from = kUpstreamProductName,
}) {
  final out = StringBuffer();
  var depth = 0;
  var i = 0;
  // The key whose value comes next at depth 1, once its colon was read.
  String? pendingKey;
  String? lastString;
  while (i < source.length) {
    final char = source[i];
    if (char == '"') {
      final end = _stringEnd(source, i);
      final raw = source.substring(i + 1, end);
      final isValueOfMessage =
          depth == 1 && pendingKey != null && !pendingKey.startsWith('@');
      if (isValueOfMessage) {
        out
          ..write('"')
          ..write(renameInMessage(raw, from: from, to: _jsonEscape(to)))
          ..write('"');
        pendingKey = null;
      } else {
        out.write(source.substring(i, end + 1));
        if (depth == 1 && pendingKey != null) pendingKey = null;
      }
      lastString = raw;
      i = end + 1;
      continue;
    }
    switch (char) {
      case '{' || '[':
        depth++;
        if (depth == 2) pendingKey = null;
      case '}' || ']':
        depth--;
      case ':':
        if (depth == 1) pendingKey = lastString;
      case ',':
        if (depth == 1) pendingKey = null;
    }
    out.write(char);
    i++;
  }
  return out.toString();
}

/// [message], a JSON-escaped ICU message, with each whole word [from]
/// renamed to [to], except where it names a placeholder (`{from}` or
/// `{from, ...}`) and where it is already part of [to].
String renameInMessage(
  String message, {
  required String to,
  String from = kUpstreamProductName,
}) {
  final word = RegExp(
    '(?<![A-Za-z0-9_])${RegExp.escape(from)}(?![A-Za-z0-9_])',
  );
  final inTo = to.indexOf(from);
  return message.replaceAllMapped(word, (match) {
    final start = match.start;
    final end = match.end;
    final opensPlaceholder = start > 0 && message[start - 1] == '{';
    final closesName =
        end < message.length && (message[end] == '}' || message[end] == ',');
    if (opensPlaceholder && closesName) return match[0]!;
    // Already renamed to a name that contains the word: leave it.
    if (inTo >= 0 &&
        start - inTo >= 0 &&
        message.startsWith(to, start - inTo)) {
      return match[0]!;
    }
    return to;
  });
}

/// Index of the quote that closes the JSON string opening at [start].
int _stringEnd(String source, int start) {
  var i = start + 1;
  while (i < source.length) {
    final char = source[i];
    if (char == r'\') {
      i += 2;
      continue;
    }
    if (char == '"') return i;
    i++;
  }
  throw FormatException('Unterminated string', source, start);
}

String _jsonEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

Future<void> main(List<String> args) async {
  String? name;
  var dryRun = false;
  var directory = 'lib/l10n';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--name' when i + 1 < args.length:
        name = args[++i];
      case '--dir' when i + 1 < args.length:
        directory = args[++i];
      case '--dry-run':
        dryRun = true;
      case '-h' || '--help':
        stdout.writeln(
          'Usage: dart run tool/apply_brand_strings.dart --name <product name> '
          '[--dir lib/l10n] [--dry-run]',
        );
        return;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }
  if (name == null || name.trim().isEmpty) {
    stderr.writeln('Missing --name <product name>.');
    exitCode = 64;
    return;
  }

  final files = Directory(directory).listSync().whereType<File>().where((file) {
    final base = file.uri.pathSegments.last;
    return base.startsWith('app_') && base.endsWith('.arb');
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('No app_*.arb files in $directory.');
    exitCode = 66;
    return;
  }

  var changedFiles = 0;
  for (final file in files) {
    final before = file.readAsStringSync();
    final after = applyBrandToArb(before, to: name);
    if (after == before) continue;
    changedFiles++;
    final count =
        RegExp(RegExp.escape(kUpstreamProductName)).allMatches(before).length -
        RegExp(RegExp.escape(kUpstreamProductName)).allMatches(after).length;
    stdout.writeln(
      '${dryRun ? 'would update' : 'updated'} ${file.path} '
      '(${count < 0 ? 0 : count} renamed)',
    );
    if (!dryRun) file.writeAsStringSync(after);
  }
  stdout.writeln(
    changedFiles == 0
        ? 'Nothing to rename: the strings already say "$name".'
        : '${dryRun ? 'Would update' : 'Updated'} $changedFiles file(s). '
              'Regenerate the localizations with `flutter gen-l10n`.',
  );
}
