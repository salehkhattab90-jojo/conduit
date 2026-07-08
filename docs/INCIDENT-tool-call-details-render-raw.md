# Incident: tool-call `<details>` blocks render as raw text (LaTeX preprocessor)

**Date investigated:** 2026-07-06
**Surface:** Conduit (Flutter), FADI deployment
**Status:** root cause confirmed; fix not yet applied
**Related:** docgen counterpart `netstat-docgen/docs/INCIDENT-stringified-request-validation-error.md` (the raw-rendered block in the reproducing chat is a *failed* docgen call from that incident)

## Symptom
On Conduit, an assistant message that generated a document (chat *"Make me a book about
radio active isotopes"*, model **vidi**, OWUI chat id `f9f246d6-cfc2-4313-840a-4cf5bbd7f31e`)
showed its tool-call collapsibles **expanded as raw escaped HTML** inline, e.g.
`<details type="tool_calls" done="true" id="chatcmpl-tool-…" name="docgen_write"
arguments="&quot;{\&quot;request…">`. The **reasoning** block in the same message rendered
correctly (`Thought for 5 minutes ▸`), so it is a per-block failure, not a whole-message
fallback. Reproduced live on `emulator-5554`.

## What it is NOT
- **Not** `DetailsBlockSyntax` failing on large input. Replaying
  `DetailsBlockSyntax.parse()` against the *raw stored content* parses all 13
  `<details>` blocks cleanly — including the 34 KB `docgen_write` tag.
- **Not** regex catastrophic backtracking, a size cap, the async/isolate compile
  (it falls back to sync compile on error), or the plainText render tier
  (`_classifyRenderTier` returns `blocks` for a multi-node message).

## Root cause
`markdown_compile_service.dart` runs `LatexPreprocessor.extract()` **before** the
markdown parse (`markdown_compile_service.dart` ~line 579, then
`md.Document(…, encodeHtml: false).parse()` ~line 587). `LatexPreprocessor`
(`renderer/latex_preprocessor.dart`) rewrites every `$$…$$` span (pattern
`_dollarBlockPattern = \$\$([\s\S]+?)\$\$`, non-greedy, matches across newlines)
into `\n\n{placeholder}\n\n` — **inserting newlines**.

Conduit serializes each tool call as a **single-line** `<details type="tool_calls"
… arguments="…" result="…">` where the whole payload lives in HTML attributes
(`core/services/conversation_parsing.dart`, `_synthesizeToolDetails*`). A physics
book's `arguments`/`result` contain `$$…$$` display-math. The extractor matches
those `$$` pairs *inside the attribute values* and inserts newlines there,
**splitting the single-line opening tag across many lines**.

`DetailsBlockSyntax.canParse` requires the opening tag (with its closing `>`) on
one line: `_blockStartPattern = ^\s{0,3}<details(?:\s+[^>]*)?>`
(`renderer/details_block_syntax.dart:15-18,38`). Once the tag spans multiple lines,
its first line has no `>`, `canParse` returns false, the block is never claimed,
and with `encodeHtml: false` the raw HTML is emitted as a text node → rendered
literally.

## Evidence (measured)
Standalone run of the **real `markdown` 7.3.1** package + the actual
`DetailsBlockSyntax` / `MentionInlineSyntax` / `ConduitMarkdownPreprocessor` +
a faithful port of `LatexPreprocessor.extract`, over the exact stored content:

| Chat | `$$` count | Result |
|------|-----------|--------|
| isotopes (vidi) | 26 | 1 real `<details>` (reasoning) + **3 nodes leaking raw `<details>` text** → BUG |
| coffee (vini) | 0 | 0 leaks → clean |
| WW2 (vidi) | 0 | 0 leaks → clean |

- The first `docgen_write` opening tag is one line of **34,103 chars** and contains
  **16 `$$`**. After `$$…$$` extraction it becomes **34 lines**; first line =
  `<details type="tool_calls" … arguments="&quot;{\&quot;` (no `>`).
- The leaked raw text produced by the real parser matches the on-device screenshot
  byte-for-byte at the head.

## Trigger / blast radius
Any tool-call `<details>` whose `arguments` or `result` contains `$$…$$` (or `$…$`,
`\[ \]`, `\( \)`) — i.e. any technical/math/currency-heavy document. Docs without
those markers are unaffected. Correlates with content, not size (WW2 at 29 KB is
clean; a smaller `$$`-bearing doc would break).

## Fix options
1. **Mask `<details>…</details>` before LaTeX extraction, restore after** — mirror
   the existing `_replaceOutsideCode` pattern in `markdown_preprocessor.dart` that
   already skips code spans. Smallest, safest change; keeps math rendering in prose.
2. Make `DetailsBlockSyntax` tolerate an opening tag whose closing `>` is on a later
   line (multi-line tag accumulation before attribute parse). Larger, touches the
   parser's line loop.

Option 1 preferred.

## Reproduction assets (this investigation)
- Exact content pulled from OWUI DB: assistant message of chat `f9f246d6…`.
- Standalone Dart harness: `markdown 7.3.1` + real source files; ISOTOPES → 3 raw
  leaks, COFFEE/WW2 → 0.
