import 'dart:io';

import 'package:conduit/shared/widgets/markdown/compiled_markdown_document.dart';
import 'package:conduit/shared/widgets/markdown/markdown_compile_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the LaTeX-vs-`<details>` interaction.
///
/// A tool call serializes its whole payload into a single-line `<details …>`
/// tag. When that payload carries `$$` display math, a LaTeX pass that rewrites
/// `$$…$$` into placeholder blocks can split the opening tag across lines, so
/// the details block no longer parses and its raw HTML leaks as text. The
/// fixture is a real tool-call message (26 `$$` inside two tool-call tags) that
/// rendered 1 collapsible and 3 raw leaks before the fix.
void main() {
  setUp(debugResetCompiledMarkdownCache);
  tearDown(debugResetCompiledMarkdownCache);

  int countDetailsElements(Iterable<CompiledMarkdownNode> nodes) {
    var count = 0;
    for (final node in nodes) {
      if (node is CompiledMarkdownElement) {
        if (node.tag == 'details') count++;
        count += countDetailsElements(node.children);
      }
    }
    return count;
  }

  bool anyRawDetailsLeak(Iterable<CompiledMarkdownNode> nodes) {
    for (final node in nodes) {
      if (node is CompiledMarkdownText && node.text.contains('<details')) {
        return true;
      }
      if (node is CompiledMarkdownElement) {
        // A real details element carries detailsData; only flag literal
        // `<details` that leaked into rendered text, not a parsed element.
        if (node.tag != 'details' &&
            node.detailsData == null &&
            node.textContent.contains('<details')) {
          return true;
        }
        if (anyRawDetailsLeak(node.children)) return true;
      }
    }
    return false;
  }

  group('regression: isotopes tool-call message renders collapsibles', () {
    final fixture = File(
      'test/fixtures/isotopes_tool_calls_message.txt',
    ).readAsStringSync();

    test('every <details> survives; no raw <details> text leaks', () {
      expect('\$\$'.allMatches(fixture).length, 26); // the trigger is present
      final prepared = prepareMarkdownContent(fixture, streaming: false);
      final document = compilePreparedMarkdownSync(prepared);

      expect(document.renderTier, MarkdownRenderTier.blocks);
      expect(countDetailsElements(document.nodes), 13);
      expect(anyRawDetailsLeak(document.nodes), isFalse);
    });
  });
}
