# Conduit fork × Open WebUI 0.12 — architecture

Companion to `PLAN.md` (same folder). Customer-agnostic: nothing here names a
deployment. Line numbers are against Open WebUI **v0.12.2** (`backend/open_webui/…`)
and this repo's `saas-base` at `37f6d355` unless a ref is given.

## 0. Hard constraint: one build, two server versions

The new app build ships **before** the server upgrade and must keep working when
the server is upgraded underneath it. So every change below is **additive or
fallback-guarded**: it works against Open WebUI 0.9.2 (today) and 0.12.2 (after),
with no version switch in the app. Concretely:

| concern | 0.9.2 server | 0.12.2 server | app rule |
|---|---|---|---|
| reply stream | `chat:completion` with cumulative `content` | `response:completion` deltas + `chat:completion` `output` snapshots, final `done` has no `content` | handle both; `content` wins when present, else project `output` |
| sign-out | `GET /api/v1/auths/signout` | `POST` only (`routers/auths.py:900`) | `POST`, fall back to `GET` on 404/405 |
| delete message | no per-message route; history rewrite | `DELETE /api/v1/chats/{id}/messages/{mid}` (`routers/chats.py:1557`); chat `POST` **merges** history (`models/chats.py:803-850`) | `DELETE`, fall back to rewrite on 404/405 |
| server→client RPCs | `confirmation`, `input`, `execute` | + `request:user_input`, `request:elicitation`, `request:terminal`, `request:terminal:state`, `request:interaction:done`; `confirmation` may carry only `tool_call` | answer every RPC at the socket layer, even with no chat open |
| thinking | client `params.chat_template_kwargs` + `features.thinking_mode` | same still honoured; **plus** per-model `info.params.model_controls` | send `params.model_controls` when the model advertises controls, else legacy |
| memory | client `features.memory` | same; default comes from `ui.memory ?? config.features.enable_memories` | mirror the web client's default |

## 1. Reply streaming on 0.12 (the blocker)

### 1.1 What the server does now
- Per-token deltas are emitted as socket event `response:completion` carrying
  OpenAI-Responses-style events (`response.output_text.delta`,
  `response.reasoning_text.delta`, `response.output_item.added|done`,
  `response.function_call_arguments.delta`, `response.completed`, …)
  (`utils/middleware.py:5058, 5110, 5984`; payload builder `:614`).
- Structural snapshots still arrive as `chat:completion {output: […]}` (tool rounds,
  code-interpreter continuation, `flush: true` snapshots: `:5626, :5814, :5975, :6049`).
- The final event is `chat:completion {done: true, output, title, usage}` — **no
  `content`** (`:6641-6647`).
- The DB copy gets `content = get_output_text(output)` (`models/chats.py:1331-1334`,
  `utils/misc.py:245`): **plain answer text only**. Reasoning and tool calls live
  only in `output[]`. 0.9.2 instead stored `serialize_output(output)` — text plus
  `<details type="reasoning|tool_calls|code_interpreter">` blocks
  (0.9.2 `utils/middleware.py:457-597`).

### 1.2 What the fork does today
- Handles only `chat:completion` (`lib/core/services/streaming_helper.dart:2503`):
  `content` → visible text; `output` → stored on the message (`:2516-2553`) but
  never rendered as text or cards.
- Reasoning/tool cards are parsed **only** from `<details>` markup inside `content`
  (`lib/core/utils/reasoning_parser.dart`, `lib/shared/widgets/markdown/…`).
- Chat load keeps `output` (`lib/core/services/conversation_parsing.dart:566-587`)
  but never turns it into markup.

Result on 0.12.2: no live text; the reply appears only after `done` via the
empty-content recovery fetch (`streaming_helper.dart:2359`); **every new reply loses
its reasoning and tool cards, live and after reload**. Old replies (stored by 0.9.2
with markup) are unaffected.

### 1.3 Design: reduce → project → render (no renderer change)

```
socket 'events'
  ├─ response:completion ──► OpenWebUIResponseReducer ──► output[] (local, per stream)
  ├─ chat:completion{output} ─────────── snapshot replaces local output[] ──┘
  └─ chat:completion{content} ── (0.9.2) ── visible content as today
                                     │
output[] ──► serializeOpenWebUIOutput() ──► 0.9.2-identical markup ──► existing markdown/details renderer
```

Three new pure units in `lib/core/services/` (no Flutter imports, fully unit-tested):

1. **`openwebui_response_stream.dart`** — port of upstream Conduit's
   `applyOpenWebUIResponseStreamEvent` (`upstream/main:packages/conduit_core/lib/services/openwebui_response_stream.dart`,
   404 lines, written against this same server contract) with its test file
   (`…/test/services/openwebui_response_stream_test.dart`). Folds one event onto
   `List<Map>` output; handles `response.completed` merge, item add/done, text /
   reasoning / summary / function-arguments deltas, code-interpreter deltas, and
   reasoning timing (`started_at`/`ended_at`/`duration`).
2. **`openwebui_output_serializer.dart`** — Dart port of 0.9.2's server-side
   `serialize_output` (+ `_render_openai_tool_call_handler`): `message` text,
   `function_call`+`function_call_output` → `<details type="tool_calls" …>`
   (with `files`/`embeds` attributes), `reasoning` (`summary` or `content`) →
   `<details type="reasoning" done duration>`, `open_webui:code_interpreter` →
   `<details type="code_interpreter" …>`, OpenAI built-in tool items
   (web/file search, computer use…). New 0.12 type `open_webui:context_compaction`
   is skipped. Escaping matches Python's `html.escape` + `json.dumps` byte for byte,
   so the fork's details parser sees exactly what it parsed on 0.9.2 (golden tests
   generated from the 0.9.2 Python function).
3. **`assistant_output_projection.dart`** — one rule used by both streaming and
   load: *if `content` already holds `<details` markup or `output` has no
   non-message items → `content`; else `serializeOpenWebUIOutput(output)`.*

Wiring (all in existing files):
- `streaming_helper.dart`: new `response:completion` branch beside `chat:completion`.
  Reducer state lives on the stream (`latestResponseOutputItems`); each event
  updates it, re-projects, and calls the existing `replaceVisibleAssistantContent`
  (already throttled by the streaming buffer). Structural events (`*.done`,
  `output_item.*`, `response.completed`) also patch `message.output`, so the
  existing terminal-artifact and doc-preview cards (which read `output`) appear
  live. A `chat:completion` that carries `output` and no `content` replaces the
  local list (snapshot wins) and re-projects. `done` with `output` and empty
  `content` projects immediately instead of waiting on recovery.
- `conversation_parsing.dart` (load path): no change to `content`; the projection is
  applied where the widget picks its text (`assistant_message_widget.dart:503-505`,
  incl. `versions`).

**Invariant: `content` keeps the server's value; markup is a display projection.**
The fork pushes whole chat blobs from local rows (`lib/core/sync/push_sync.dart:187-192`)
and 0.12 merges them into history; writing projected markup into `content` would
put `<details>` into the server copy that 0.12 keeps plain (copy, export, search,
title generation read it). During a live 0.12 stream the visible buffer holds the
projection, and the message's persisted `content` is set to
`get_output_text(output)` at `done` (the same value the server stores). Phase 1
traces the streaming buffer → Drift → push path to prove this holds; if a path
persists the visible buffer, the guard goes in `ChatBlobMapper.rowsToBlob` (strip to
`get_output_text(output)` for messages whose `output` has non-message items **and**
whose server copy was plain).

Why not upstream's renderer? Upstream renders `output` through a separate
structured-output pipeline (`openwebui_stream_parser.dart` →
`replaceVisibleAssistantStructuredOutput`) introduced with its 0.10 support and
interleaved with its restructured chat UI. Porting it means porting much of that UI.
Projecting to the markup the fork already renders keeps every existing card
(reasoning, tool calls, code interpreter, LaTeX-in-details masking, terminal and
doc-preview cards) unchanged and identical for 0.9.2 and 0.12.2 replies.

## 2. Server→client RPCs (`sio.call`)

0.12 waits on the client for (`socket/main.py:1500-1550`):

| event | server wait | today in fork | new behaviour |
|---|---|---|---|
| `request:terminal` (AGENTS.md read) | ≤ 5 s per turn (`utils/terminals.py:197`, `asyncio.timeout(5)`) | unanswered → full wait | ack `{}` |
| `request:terminal:state` | ≤ 2 s per turn (`utils/middleware.py:3275`) | unanswered → full wait | ack `{connected: false}` |
| `request:elicitation` (MCP) | 60–240 s, capped by `WEBSOCKET_EVENT_CALLER_TIMEOUT` | unanswered | ack `{action: 'cancel'}` (server treats as decline; tool goes on) |
| `request:user_input` (`ask_user` builtin, `tools/builtin.py:607`) | 60–240 s | unanswered → model blocked | phase A: ack `{error: "This app can't show question forms. Ask the question in your reply instead."}` → the tool returns that error text to the model (`builtin.py:617-618`) and it asks in prose. Phase C (optional): native question sheet |
| `confirmation` with `data.tool_call` (tool approval, unsaved chats) | 60–240 s | blank dialog (expects `title`/`message`) | render tool name + pretty-printed arguments in the existing `ConfirmationCoordinator` dialog |
| `request:interaction:done` | — | ignored | ignored (coordinator closes its own dialog on stream teardown already) |

Placement: in `SocketService._handleChatEvent` **before** fan-out
(`lib/core/services/socket_service.dart:919`), as upstream does
(`upstream/main:…/services/socket_service.dart:1490-1527`): the server blocks on the
session whichever chat is open, and fan-out/replay must not ack twice. Only
`confirmation` and `input` stay in the stream handler (they need UI and the
coordinator's one-dialog rule).

## 3. Message delete

0.12 `POST /api/v1/chats/{id}` merges history (`models/chats.py:803-850`), so the
fork's delete-by-rewrite (`lib/core/services/api_service.dart:2059-2116`) silently
does nothing. New: `DELETE /api/v1/chats/{id}/messages/{mid}` first; on 404/405 fall
back to the rewrite (0.9.2). Server semantics differ from the local delete: the
server removes the message and its **direct children** and re-parents grandchildren
(`models/chats.py` `delete_message_from_history`), while the local delete removes
all descendants. So the caller deletes each id in the locally-removed set in
parent-first order (as upstream: `upstream/main:…/chat_message_actions.dart:117`),
skips ids the server already removed (404 on a later id is success), and refreshes
the snapshot afterwards so local and server trees agree.

## 4. Sign-out
`ApiService.logout()` (`api_service.dart:701-703`): `POST`, fall back to `GET` on
404/405. Today the 405 is swallowed (`auth_state_manager.dart:1993-2000`), local
sign-out still happens, but the server never revokes the token — fixing this
restores server-side revocation (0.12 `invalidate_token`, `routers/auths.py:918`).

## 5. Model controls (thinking) — generic

0.12 exposes per-model controls to clients as
`info.params.model_controls = {key: {label, description?, default, display?, options: {optKey: {label}}}}`
(`utils/models.py:35-53`) and applies a request's
`params.model_controls = {modelId: {key: optKey}}` (`main.py:1212-1225, 1655-1660`,
`utils/payload.py:20-34`); non-admins need `chat.controls` **and** `chat.params`,
otherwise the choice is dropped silently and the control's default applies.

- Parse `model_controls` from the model list into `Model` (generic: any key).
- Per-chat choice store generalises today's `ThinkingMode` store
  (`lib/core/models/thinking_mode.dart`): `Map<controlKey, optionKey>` per chat.
- UI: a "Model controls" sheet in the composer overflow listing every control with
  the server's labels; the existing thinking pill stays only for servers/models
  without controls (legacy).
- Request: when the selected model advertises controls, send
  `params.model_controls` and **stop** sending `chat_template_kwargs.enable_thinking`
  and `features.thinking_mode` for that model (avoids two sources of truth);
  otherwise keep today's legacy path unchanged (still honoured by 0.12:
  request params merge at `main.py:1213, 1226`).
- 400 "selected option is no longer available" (`payload.py:25-28`) → drop the stale
  choice, retry once with defaults.

## 6. Memory default
`features.memory` is sent only when `ui.memory == true`
(`api_service.dart:4883-4892`). The web client uses
`$settings.memory ?? $config.features.enable_memories ?? false`
(0.12 `src/lib/components/chat/Chat.svelte:4013`). Mirror it. Note 0.12 already
folds admin `ui.default_interface_settings` into `GET /api/v1/users/user/settings`
(`routers/users.py:459-474`), so a server-side default reaches the app with no change;
the fallback covers servers that only set the global flag. Server-side the flag is
still permission- and config-gated (`utils/middleware.py:2720-2731`).

## 7. Terminal `display_file` inline
`display_file(inline=true)` suppresses `terminal:display_file`
(`utils/middleware.py:1344`). The fork already rebuilds artifact cards from the
durable `function_call(display_file)` + `function_call_output` pair in `output`
(`lib/features/chat/widgets/assistant_message_widget.dart:266-310`), which 0.12 still
writes (`utils/middleware.py:3621-3650`; the result is normalised to
`{type:'file', source:'open_terminal', path, …, displayed?}` by
`build_terminal_file_tool_result`, `:297-337`). With §1 the `output` arrives live, so
inline files get a card too. Change: also read the normalised `files[]` entry
(`source == 'open_terminal'`) and the JSON text's `exists`, and de-duplicate with the
event store by path.

## 8. Files touched (expected)

| file | change |
|---|---|
| `lib/core/services/openwebui_response_stream.dart` | **new** — reducer (port) |
| `lib/core/services/openwebui_output_serializer.dart` | **new** — 0.9.2 `serialize_output` port |
| `lib/core/services/assistant_output_projection.dart` | **new** — projection rule |
| `lib/core/services/streaming_helper.dart` | `response:completion` branch; snapshot/done projection |
| `lib/features/chat/widgets/assistant_message_widget.dart` | render via projection; artifact paths from `files[]` |
| `lib/core/services/socket_service.dart` | RPC auto-acks before fan-out |
| `lib/core/services/confirmation_coordinator.dart` | `tool_call` confirmation body |
| `lib/core/services/api_service.dart` | sign-out POST; per-message DELETE; memory default; model controls in request |
| `lib/features/chat/…/chat_message_actions` (wherever delete is driven) | ordered per-id delete + refresh |
| `lib/core/models/model.dart` (+ generated) | `modelControls` |
| `lib/core/models/thinking_mode.dart` / providers | generic per-chat control choices |
| `lib/features/chat/widgets/composer_overflow_menu.dart` | Model controls sheet |
| `lib/l10n/app_en.arb` (+ others by fallback) | new strings |
| `test/core/services/…` | reducer, serializer (golden), projection, RPC acks, delete fallback, sign-out fallback |
