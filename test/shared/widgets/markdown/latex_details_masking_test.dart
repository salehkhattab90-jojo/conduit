import 'dart:io';

import 'package:conduit/shared/widgets/markdown/compiled_markdown_document.dart';
import 'package:conduit/shared/widgets/markdown/markdown_compile_service.dart';
import 'package:conduit/shared/widgets/markdown/renderer/latex_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression + unit coverage for the LaTeX-vs-`<details>` interaction.
///
/// Root cause (FADI, 2026-07-05): `LatexPreprocessor.extract` rewrites `$$…$$`
/// into `\n\n<placeholder>\n\n`. A tool call serializes its whole payload into a
/// single-line `<details …>` tag; when that payload carries `$$` display-math
/// (the isotopes physics book had 16 in one tag), the inserted newlines split
/// the opening tag across lines and `DetailsBlockSyntax` can no longer parse it —
/// the raw HTML leaked as text. The fix masks `<details>` regions from the
/// LaTeX pass.
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
        // `<details` that leaked into rendered *text*, not a parsed element.
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

  group('extractLatexOutsideDetails', () {
    test('masks \$\$ math inside a tool-call <details> tag (no tag splitting)', () {
      final pre = LatexPreprocessor();
      const content =
          '<details type="tool_calls" name="x" done="true" '
          'arguments="a \$\$E=mc^2\$\$ b"><summary>Tool Executed</summary></details>';
      final out = extractLatexOutsideDetails(pre, content);
      expect(out, content); // untouched — no placeholder newlines injected
      expect(pre.hasLatex, isFalse);
    });

    test('still extracts \$\$ math in prose OUTSIDE details', () {
      final pre = LatexPreprocessor();
      final out = extractLatexOutsideDetails(pre, r'Before $$x^2$$ after.');
      expect(pre.hasLatex, isTrue);
      expect(pre.blockExpressions.values, contains('x^2'));
      expect(out, isNot(contains(r'$$'))); // replaced by a placeholder token
    });

    test('extracts prose math but passes an unclosed trailing <details> verbatim '
        '(streaming)', () {
      final pre = LatexPreprocessor();
      const content =
          'Prose \$\$a\$\$ then\n<details type="tool_calls" arguments="x \$\$b\$\$';
      final out = extractLatexOutsideDetails(pre, content);
      expect(pre.blockExpressions.values, contains('a')); // prose math extracted
      // the partial tag and its $$ survive intact — never shredded mid-stream
      expect(out, contains('<details type="tool_calls" arguments="x \$\$b\$\$'));
    });

    test('leaves \$\$ math inside a details BODY for the body compile pass', () {
      final pre = LatexPreprocessor();
      const content =
          '<details type="reasoning"><summary>T</summary>\n'
          'Body \$\$m\$\$ here\n</details>';
      final out = extractLatexOutsideDetails(pre, content);
      expect(out, content);
      expect(pre.hasLatex, isFalse);
    });

    test('content with no <details> is a plain pass-through', () {
      final pre = LatexPreprocessor();
      final out = extractLatexOutsideDetails(pre, r'Just $$k$$ and text.');
      expect(pre.blockExpressions.values, contains('k'));
      expect(out, isNot(contains(r'$$')));
    });

    test('depth-aware mask covers a NESTED <details> (outer tail \$\$ not shredded)',
        () {
      // A non-greedy match would close at the inner </details> and re-expose
      // the outer tail; the depth-balanced scan masks the whole outer region.
      final pre = LatexPreprocessor();
      const content =
          '<details type="tool_calls"><summary>S</summary>'
          '<details type="reasoning"><summary>inner</summary>x</details>'
          ' tail \$\$q\$\$ still inside</details>';
      final out = extractLatexOutsideDetails(pre, content);
      expect(out, content); // entire outer region verbatim, including the $$
      expect(pre.hasLatex, isFalse);
    });

    test('math between two sibling details regions is still extracted', () {
      final pre = LatexPreprocessor();
      const content =
          '<details type="reasoning"><summary>a</summary>x</details>'
          ' mid \$\$s\$\$ gap '
          '<details type="reasoning"><summary>b</summary>y</details>';
      final out = extractLatexOutsideDetails(pre, content);
      expect(pre.blockExpressions.values, contains('s')); // the gap math extracts
      expect(out, startsWith('<details type="reasoning"><summary>a</summary>'));
      expect(out, endsWith('</details>')); // both regions intact
    });
  });

  group('regression: isotopes tool-call message renders collapsibles', () {
    final fixture = File(
      'test/fixtures/isotopes_tool_calls_message.txt',
    ).readAsStringSync();

    test('every <details> survives; no raw <details> text leaks', () {
      expect('\$\$'.allMatches(fixture).length, 26); // the trigger is present
      final prepared = prepareMarkdownContent(fixture, streaming: false);
      final document = compilePreparedMarkdownSync(prepared);

      expect(document.renderTier, MarkdownRenderTier.blocks);
      // All 13 reasoning/tool_call blocks parse as real details elements
      // (was 1 survivor + 3 raw leaks before the fix).
      expect(countDetailsElements(document.nodes), 13);
      expect(anyRawDetailsLeak(document.nodes), isFalse);
    });
  });
}
