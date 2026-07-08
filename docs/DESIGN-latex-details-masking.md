# Design: LaTeX extraction must skip `<details>` regions

**Fixes:** `docs/INCIDENT-tool-call-details-render-raw.md`
**Branch:** `saas-base` (generic bug), merges into `fadi`.

## Problem (one line)
`LatexPreprocessor.extract()` runs on the whole message before markdown parsing and
rewrites `$$…$$`/`$…$` spans into `\n\n<placeholder>\n\n` — including spans *inside*
`<details>` tool-call/reasoning markup, where the inserted newlines split the
single-line opening tag and break `DetailsBlockSyntax`.

## Change
One choke point: `_compilePreparedMarkdownDocument()` in
`lib/shared/widgets/markdown/markdown_compile_service.dart` (the only `extract()`
call site; sync, async-isolate, and batch paths all funnel here).

Replace the direct `latexPreprocessor.extract(preparedContent)` with a new
module-private helper:

```
String _extractLatexOutsideDetails(LatexPreprocessor pre, String content)
```

Behavior:
1. Fast path: no `<details` substring → `pre.extract(content)` unchanged.
2. Split content on complete details regions
   `RegExp(r'<details\b[^>]*>[\s\S]*?</details>', caseSensitive: false)`;
   run `pre.extract()` **only on the between-segments**, pass region text through
   verbatim. Per-segment calls accumulate into the same preprocessor instance
   (counter + maps), so downstream `splitOnPlaceholders` is unaffected.
3. Streaming tail: in the remainder after the last complete region, if a
   `<details` occurs (an unclosed block mid-stream — possibly with its opening tag
   still incomplete), extract only the text *before* it and pass the tail through
   verbatim. Prevents shredding partial tags during streaming.

## Why masking is lossless for math
The details body is rendered by its **own** compile pass —
`block_renderer.dart` feeds `data.bodyMarkdown` to `StreamingMarkdownWidget`
(streaming) or `compilePreparedMarkdownSync` (done), each with a fresh
`LatexPreprocessor`. So math inside a details body never needed the outer pass.
In fact today the outer pass **breaks** body math: it swaps `$$eq$$` for
placeholder tokens that get baked into `body_markdown`, where the body's fresh
preprocessor can't resolve them (latent bug). Masking fixes that too.

## Masking is depth-balanced (post adversarial-review)
The mask does not use a non-greedy `<details>…</details>` regex (which would
close at the first `</details>` and re-expose the outer tail of a *nested*
block). Instead it scans `</?details\b[^>]*>` tags and depth-counts: an
outermost region spans from a depth-0 open tag to its balancing depth-0 close,
and only spans truly *outside* all regions are handed to `pre.extract`.

## Known edge cases (accepted)
- `[^>]*` in the tag regex assumes no literal `>` inside attribute values —
  guaranteed: both Conduit (`_escapeHtmlAttr`) and OWUI middleware
  (`html.escape`) escape `>` in attributes, and `DetailsBlockSyntax` itself
  already relies on the same assumption.
- Streaming: a complete-but-unclosed open tag → verbatim from the open tag on
  (depth > 0 at end); a still-arriving *partial* open tag (no `>` yet) → verbatim
  from the `<details` on. Neither is shredded.
- A `$$…$$` span straddling a details boundary no longer matches (a `$$` inside a
  region is masked, so the pair can't form across the boundary). That span was
  precisely the corruption vector; not rendering it as math is correct.

## Tests (`test/latex_details_masking_test.dart`)
Fixture: the real 118 KB incident message (user-id hash scrubbed) at
`test/fixtures/isotopes_tool_calls_message.txt`.
1. **Regression:** compile the fixture through the real pipeline → exactly 13
   `details` blocks, zero nodes whose text contains `<details`.
2. **Control:** a `$$`-free tool-call message compiles identically before/after.
3. **Prose math still works:** `$$…$$` outside details still produces a LaTeX
   placeholder/expression.
4. **Streaming tail:** content ending in an unclosed `<details …` (and a
   truncated opening tag) — tail passes through unshredded, prose before it
   still extracts math.
5. **Body math:** `$$…$$` inside a details body survives verbatim into
   `body_markdown` (no placeholder tokens baked in).

## Not changed
`DetailsBlockSyntax`, `LatexPreprocessor` class itself, `markdown_preprocessor`,
streaming strip logic, any rendering widget.
