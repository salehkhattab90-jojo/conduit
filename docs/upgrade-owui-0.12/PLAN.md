# Conduit fork × Open WebUI 0.12 — plan

**Status:** proposal, awaiting owner approval. No code written.
**Scope:** what this fork (`main` → `saas-base` → customer layer) needs to keep
working when its Open WebUI server moves from **0.9.2** to **0.12.2**.
**Companion:** `ARCHITECTURE.md` (designs, file list), customer notes live only on
the customer branch.
**Base:** `saas-base` `37f6d355`; upstream Conduit checked at `upstream/main`
`dda134cd` (v4.2.0, 2026-10-13); Open WebUI v0.12.2 source tree.

## 1. Summary

- The current build is **not usable** on a 0.12.2 server: replies don't stream (they
  pop in at the end), and every new reply loses its reasoning and tool-call cards,
  live and after reload. Turns in tool/terminal chats can also stall for seconds to
  minutes on server requests the app never answers.
- Upstream Conduit already supports Open WebUI 0.12.0, but it got there across 611
  commits that restructured the app (core moved into `packages/conduit_core`, Drift
  persistence, Hermes backend) and it now **requires Flutter ≥ 3.47** (this machine
  has 3.44.2). Rebasing our 33 fork commits onto it is a separate project, estimated
  at **13–19 focused days** (§9).
- **Recommendation: Track A** — patch the fork in place on `saas-base` with ~10
  targeted, fallback-guarded changes, borrowing upstream's code where it is
  self-contained (stream reducer, request acks, delete fallback). One build works on
  **both** 0.9.2 and 0.12.2, so it can ship **before** the server upgrade (the server
  plan's decision G-5). **Track B** (rebase onto upstream) is proposed as its own
  project after the server upgrade lands.

## 2. Breakages and chosen fixes

Severity is for a typical deployment that uses socket streaming, tools and a
terminal. "Fallback" = how the same build keeps working on 0.9.2.

| # | Breakage on 0.12.2 (verified) | Symptom | Fix (Track A) | Fallback on 0.9.2 | Source of the fix |
|---|---|---|---|---|---|
| 1 | Reply deltas arrive as `response:completion` (`utils/middleware.py:5058,5110,5984`); final `done` has no `content` (`:6641-6647`); DB `content` is plain text, traces only in `output[]` (`models/chats.py:1331`) | No live text; reply appears at the end; **reasoning, tool-call and code-interpreter cards lost on every new reply** (live and reload) | Reduce events → `output[]` → project to the same `<details>` markup 0.9.2 produced → existing renderer (ARCH §1) | 0.9.2 still sends `content`; projection only runs when `content` lacks markup and `output` has non-message items | Reducer: port of upstream `openwebui_response_stream.dart` (+tests). Serializer: port of 0.9.2 `serialize_output` |
| 2 | Server→client RPCs the app never answers: `request:terminal` (≤5 s), `request:terminal:state` (≤2 s), `request:elicitation` / `request:user_input` (60–240 s); tool-approval `confirmation` carries only `tool_call` | Turns stall; `ask_user` blocks the model for minutes; approval dialog is blank | Answer at the socket layer before fan-out: `{}`, `{connected:false}`, `{action:'cancel'}`, `user_input` → error text telling the model to ask in prose; render tool name + args in the approval dialog (ARCH §2) | Events never arrive on 0.9.2 | Upstream `socket_service.dart:1490-1527` (4cb3c48f) |
| 3 | Chat `POST` merges history (`models/chats.py:803-850`); new `DELETE /api/v1/chats/{id}/messages/{mid}` (`routers/chats.py:1557`) | Deleting a message reappears after sync | `DELETE` per removed id, parent-first, then refresh (ARCH §3) | 404/405 → today's history rewrite | Upstream `api_service_chats.dart:183-207` |
| 4 | `GET /api/v1/auths/signout` removed, `POST` only (`routers/auths.py:900`) | Local sign-out still works (error swallowed) but the **server never revokes the token** | `POST`, fall back to `GET` | 405/404 → `GET` | Upstream `api_service_auth.dart:57` |
| 5 | Native function calling default + `ask_user` builtin (`utils/tools.py:697`) | see #2 | covered by #2; recommend the server keeps the user-input builtin off until #13 ships | — | — |
| 6 | Per-model "Model controls" (`info.params.model_controls`, `params.model_controls`; `utils/payload.py:20-34`, `main.py:1212-1225`) | Nothing breaks: today's `chat_template_kwargs` + `features.thinking_mode` still pass through. But the app can't drive controls the admin configures | Generic Model controls sheet; send `params.model_controls` when the model advertises them, legacy fields otherwise (ARCH §5) | No `model_controls` in the model list → legacy pill as today | New (upstream Conduit has none) |
| 7 | Memory: app sends `features.memory` only when `ui.memory == true` (`api_service.dart:4883-4892`) | Memory silently off for users who never toggled it, unless the server seeds a default | Mirror web: `ui.memory ?? config.features.enable_memories ?? false` (ARCH §6). Server default via `ui.default_interface_settings` already reaches the app (`routers/users.py:459-474`) | Same rule is correct on 0.9.2 | Web client `Chat.svelte:4013` |
| 8 | Terminal `display_file(inline=true)` suppresses `terminal:display_file` (`utils/middleware.py:1344`) | Mostly covered already: the fork rebuilds cards from `output[]` on reload; with #1 they appear live too | Also read the normalised `files[]` entry (`source:'open_terminal'`), de-dupe by path (ARCH §7) | Unchanged | — |
| 9 | `ui` settings are per-key patches since 0.11.4 (`models/users.py:836-844`) | Clearing the default model or system prompt in the app does nothing (`api_service.dart:2340, 2345, 2362` use `remove`) | Send explicit `null` | 0.9.2 stores `null`; reader treats it as unset (verify) | Upstream d82087fc |
| 10 | Completion failure without a socket now returns the provider's status (was JSON `null`) and a retry gets 409 | Only on the no-socket path (app backgrounded / socket down): saved error never shows; queued retry loops on 409 | Reproduce in phase 3; if confirmed, port upstream's "read the saved reply once the server has finished it" recovery | 0.9.2 path unchanged | Upstream 4cb3c48f `_recoverSavedReplyOrThrow` |
| 11 | Provider 401/403 passed through on non-socket sends | Send error containing 401/403 reloads auth (`chat_providers.dart:5322-5329`) — non-socket path only | Mark the reply with the error; probe `GET /api/v1/auths/` once and let the interceptor decide | Same | Upstream 4cb3c48f |
| 12 | New socket events: `terminal:write_file`, `terminal:replace_file_content`, `terminal:run_command`, `chat:message:tasks`, `context_compaction` | Terminal file browser doesn't refresh after the agent writes; no task list/compaction notice. No errors | Refresh the terminal browser on `terminal:*`; show `context_compaction` as a status line. Task list: deferred | n/a | Upstream 6e9e8668 |
| 13 | (optional) `ask_user` question forms | Without it the model asks in prose (via #2) | Native question sheet for `request:user_input` (single/multi choice + "other" + free text), answers `{answers}` / `{status:'cancelled'}` | n/a | Upstream `openwebui_chat_prompt*.dart` (f80f7935) — port, ~900 lines |

**Not breaking, recorded so nobody re-checks them:** the Email tab's `localStorage.token`
injection (0.12 frontend still keys on it); the send-confirmation dialog for a
Tool's own `confirmation` event (title/message payload, unchanged); doc-preview cards
(`function_call_output` still carries `files`/`embeds`, `utils/middleware.py:3651-3657`
— but the object-embed preview contract comes from this fork's server patches, so it
holds only if the server upgrade ports them, as its plan says); `/api/chat/completed`, `/api/tasks/*`,
`/api/models`, chat CRUD, folders, files, notes, memories, terminals proxy routes
(present in both versions); direct SSE (non-socket) streaming is still provider
chat-completion chunks. Removed-but-unused: `POST /api/v1/tasks/active/chats` (the fork
calls a non-`v1` path that never existed; pre-existing, see §7).

**Opt-in server features the app does not support (keep them off until it does):**
two-step sign-in (MFA; password/LDAP sign-in answers with a step object), enforced
temporary chats for non-admins, per-chat Open Terminal context, tool-approval "ask"
mode for saved chats beyond what #2 renders, folder sharing (shared folders are
invisible, nothing breaks). Each is a row for Track B or a later Track A item.

## 3. Phases (after approval)

All work on a branch off `saas-base` in a separate worktree; the owner's checkout is
untouched until hand-over. Each phase ends with `flutter analyze` clean and the
full `flutter test` run diffed against the pre-change failure set.

1. **Test rig** — two local Open WebUI servers via `uv` (0.9.2 on :8092, 0.12.2 on
   :8122, separate data dirs) and a small scripted OpenAI-compatible mock model that
   streams reasoning, text, one tool call (`display_file`-shaped and a plain one)
   and a code block, deterministically. Golden fixtures for the serializer are
   generated by running 0.9.2's `serialize_output` on recorded 0.12.2 `output[]`
   payloads. Capture real socket traffic from both servers as test fixtures.
2. **Streaming (#1)** — reducer + tests (port), serializer + golden tests,
   projection rule, wiring in `streaming_helper` and the message widget. Trace the
   buffer → Drift → push path and add the `content` guard if needed (ARCH §1.3).
3. **Protocol fixes (#2, #3, #4, #7, #8, #9, #10, #11, #12)** — each with a unit test
   for both server behaviours (fake Dio adapter: 0.9.2 answer, 0.12.2 answer).
4. **Model controls (#6)** — model parsing, per-chat choice store, sheet, request
   shape, stale-choice 400 retry.
5. **(optional) `ask_user` sheet (#13).**
6. **Device E2E** on the Android emulator against both local servers (matrix in §4),
   then hand-over: merge into `saas-base`, merge `saas-base` into the customer branch,
   push, build.

Rough size: phases 1–4 ≈ 3–4 focused days; phase 5 ≈ 1 day; phase 6 ≈ 1 day.
Track B ≈ 13–19 focused days (§9).

## 4. Test plan

**Unit / widget (CI-less, run locally):**
- Reducer: upstream's test file ported as-is, plus recorded 0.12.2 event sequences
  (text only; reasoning → text; text → tool call → tool output → text; code
  interpreter continuation; `response.completed` merge; out-of-order `output_index`).
- Serializer: golden equality with 0.9.2 Python output for each fixture (escaping of
  quotes/ampersands/non-ASCII, `files`/`embeds` attributes, reasoning `summary` vs
  `content`, done/in-progress inference).
- Projection: 0.9.2 message (markup in `content`) unchanged; 0.12.2 message (plain
  `content` + `output`) → markup; message with only `message` items → `content`.
- Socket: each RPC acked exactly once, with no chat open, and never twice after
  replay; `confirmation{tool_call}` renders name + args.
- API: sign-out POST→GET fallback; delete DELETE→rewrite fallback and parent-first
  order; settings clear sends `null`; memory default precedence; model-controls
  request shape and 400 retry.
- Regression: existing suites (streaming transport, conversation parsing, embeds,
  LaTeX-details masking, confirmation coordinator, deletion reconcile) stay green.

**Device E2E (Android emulator; iOS simulator once the Xcode licence is accepted),
each against 0.9.2 and 0.12.2:**

| scenario | pass when |
|---|---|
| plain reply | text streams token-by-token; final text matches the web client |
| reasoning model | "Thinking…" card streams, then "Thought for N s"; same after reload and app restart |
| tool call (native FC) | tool card shows Executing → Executed with arguments/result; same after reload |
| terminal `display_file` (inline and not) | one artifact card per file, live and after reload; opens the viewer |
| generated document (doc-generator tool) | one doc card, preview + download as today |
| `ask_user` builtin on | model continues within seconds and asks in prose (or the sheet, if #13) |
| MCP elicitation | tool continues within seconds |
| tool approval "ask" | dialog shows tool name + args; approve/deny both work |
| delete a message, pull-to-refresh, reopen | stays deleted on app and web |
| sign out | server token revoked (old token gets 401 on `/api/v1/auths/`) |
| memory | with the server default on, a fact from chat A is recalled in chat B |
| thinking / model controls | Off/Auto/On reach the request (server log) and change behaviour |
| clear default model / system prompt | cleared on the web too |
| socket killed mid-reply (airplane mode toggle) | reply resumes or shows the saved result; no 409 loop |
| upgrade-in-place | app open on 0.9.2, server swapped to 0.12.2, app keeps working after reconnect |
| old chats | 0.9.2-era replies render exactly as before |

## 5. Rollout

1. Owner approves this plan (and §6 decisions).
2. Phases 1–6; build from the customer branch; distribute to users.
3. Server upgrade deploys afterwards (server plan G-5). Because the build is
   dual-version, there is no flag day and no rollback coupling: if the server rolls
   back to 0.9.2, the app keeps working.
4. Server-side settings that protect older app builds still in users' hands (until
   adoption is confirmed): user-input builtin off, tool permissions off, no MFA, no
   per-chat terminal context, no enforced temporary chats.

## 6. Decisions for the owner

- **D-1 Track:** Track A now, Track B (rebase onto upstream) as a separate project
  after the server upgrade (rec) · Track B now (blocks the server upgrade for longer,
  needs Flutter 3.47+) · Track A only.
- **D-2 `ask_user`:** answer with an error so the model asks in prose, keep the
  builtin off server-side (rec) · also build the native question sheet (#13, ~1 day).
- **D-3 Model controls:** generic sheet + keep the legacy pill for servers without
  controls (rec) · keep only the pill and map it onto a control named `thinking`
  (smaller, but bakes a key name into the base).
- **D-4 Test servers:** local `uv` servers + mock model for development (rec), **plus**
  one acceptance pass against the server upgrade's rehearsal copy booted on a side
  port (real models, real migrated chats — the best check that old replies still
  render) (rec, owner-run) · local servers only.
- **D-5 Optional rows:** include #10–#12 in this release (rec) · defer to Track B.

## 7. Pre-existing gaps found on the way (not caused by the upgrade)

Routes the fork calls that exist in **neither** 0.9.2 nor 0.12.2 (failing today):
chat tag delete/filter, `/api/v1/configs/suggestions`, knowledge create/update/delete/
items/search, chat duplicate, message search, file metadata update, prompt/tool/
function create, several channel writes, `HEAD /api/health`, and the active-chats
check (`/api/tasks/active/chats`). Upstream Conduit has fixed most of these. They are
listed for Track B, not fixed here.

## 8. Risks

- Projection drift: if a future server changes `output[]` item shapes, the projection
  can lag; mitigated by golden tests from real payloads and by `content` always
  holding the server's text.
- Two writers of the visible buffer during a 0.12 stream (`response:completion`
  deltas and `chat:completion` snapshots): snapshots always replace the reducer
  state; covered by recorded-sequence tests.
- The ported reducer is upstream code written for the same server contract; it is
  ported verbatim with its tests to keep future Track B diffs small.
- Track A widens the gap to upstream by ~2–3k lines; Track B absorbs that.

## 9. Track B (rebase onto upstream) — for the record

What it would bring: upstream's own 0.10–0.12 compatibility work (structured
output, request acks, two-step sign-in, enforced temporary chats, shared folders,
`active` chat state, knowledge API moves, the 409 recovery) and much cheaper future
syncs. What it costs, from a commit-by-commit map of the 33 fork commits onto
`upstream/main` v4.2.0:

- 4 commits cancel out (two reverts), 3 are already covered upstream (output kept on
  load, LaTeX-in-details masking by a different mechanism, overflow icon), ~26 need
  porting plus the customer layer.
- Hardest item: the white-label server lock. Upstream now routes through multiple
  accounts, server addresses with failover, a backend chooser (Open WebUI / Hermes /
  Direct / Apple) and reviewer mode; the lock must close all of them, and the fork's
  deletion of the server-connection page is no longer possible (it holds the
  connection hand-off). ≈ 3–4 days.
- Core is now a Flutter-free package (`packages/conduit_core`, enforced by a
  boundary check): fork code that mixed Flutter into core (sync triggers, push
  service, confirmation dialog) must be split.
- Native: Android AGP 8 → 9, Gradle 8 → 9, iOS Swift Package Manager — Firebase/FCM
  compatibility to re-verify; upstream's notification service owns the single tap
  callback the email push needs.
- Upstream's embed sanitiser still flattens object embeds on chat save — porting
  the preview contract is mandatory or document cards get corrupted server-side.
- Toolchain: Flutter ≥ 3.47 (machine has 3.44.2, shared by other checkouts → install
  a second SDK, e.g. fvm).
- Estimate ≈ 13–19 focused days including device QA; upstream keeps moving fast
  (611 commits in ~4 months).

Recommended timing: after the server upgrade, as its own plan, starting from this
Track A branch so its tests become the acceptance suite for the rebase.
