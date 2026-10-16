# Conduit fork → rebuild on upstream Conduit v4.2.0 — plan

**Status:** proposal, awaiting owner approval. No code written.
**Replaces** the earlier in-place patch plan (Track A, `a13f04b7`), which assumed
the app had to keep working on Open WebUI 0.9.2. The owner confirmed (2026-10-16)
that nobody uses the app yet, so backward compatibility is not a requirement and
the app does not gate the server upgrade.
**Companion:** `ARCHITECTURE.md` (seams and designs per feature). Customer values
live only on the customer branch.
**Refs:** fork `main` `d81619b2` (stale upstream, 2026-06-19), `saas-base` `a13f04b7`;
upstream `cogwheel0/conduit` `main` = tag **v4.2.0** `dda134cd` (2026-10-13, supports
Open WebUI ≤ 0.12.0); target server **Open WebUI 0.12.2** (`6a18585f`).

## 1. Summary

- Rebuild the fork on upstream v4.2.0 and re-apply our features on top, as one
  commit per feature group. Upstream already carries the work for Open WebUI
  0.10 → 0.12: Responses-style streaming and `output[]` rendering, answers to the
  server's socket requests, per-message delete, POST sign-out, two-step sign-in,
  enforced temporary chats, chat "running" state, per-chat Stop, 409 recovery,
  knowledge API moves. Most of the old breakage list disappears.
- A trial cherry-pick of every fork commit onto v4.2.0 (§2) shows that only **3 of
  33** apply cleanly and usefully. Upstream moved the core into
  `packages/conduit_core` (Flutter-free), split `api_service.dart`, and rewrote the
  chat UI, so the rest is a **hand port** onto the new files — our diffs on top of
  latest upstream, re-expressed against upstream's seams.
- History: **rebuild + join commit**, the same scheme as the server upgrade
  (decision G-1 there): no force-push, old history kept, and future upstream syncs
  become normal merges.
- Effort ≈ **13–19 focused days** including device QA.

## 2. Trial cherry-pick (each commit alone onto `upstream/main` v4.2.0)

Run in a throwaway detached worktree (script and raw output kept with the session
notes). `DU` = upstream deleted or moved the file we changed; `UU` = both changed.

| commit | result | conflicted | disposition |
|---|---|---|---|
| `5b819447` white-label foundation | conflict | 21 of 23 files (2 DU, 1 UD, 18 UU) | **redesign** — locked deployment (§4 G1) |
| `cb5061c3` STT/TTS default to server | **clean** (lands in `packages/conduit_core/lib/services/settings_service.dart` via rename) | — | **cherry-pick** |
| `7cb530ef` Email section | conflict | 2 of 3 (1 DU, 1 UU) | port (G3) |
| `c4ec13a8` email-* protocol rename | conflict | 1 DU | fold into G3 |
| `45e840cc` Discuss chat auth | conflict | 1 DU | fold into G3 |
| `ab897bb7` deletion reconcile on resume | conflict | 2 DU | port (G2) |
| `e864e3cb` per-chat thinking toggle | conflict | 12 of 13 | **replace** by Model controls (G8) |
| `9ac412ae` image-gen gated on capability | conflict | 2 (1 DU, 1 UU) | port (G2) |
| `8c6378bb` refresh models + tools on resume | **clean** | — | **cherry-pick** (verify it compiles) |
| `5131209c` overflow icon gating | conflict | 1 UU | **drop** — upstream's composer already gates its pills |
| `aeda9289` gitignore `*.code-workspace` | **clean** | — | **cherry-pick** |
| `6eb92672` remove reconcile fraction valve | conflict | 3 of 4 | port (G2), decision R-4 |
| `a5941903` terminal HTML/SVG live render | conflict | 1 UU | port (G5) |
| `1c776a2c` full-screen artifact viewer | conflict | 1 UU | port (G5) |
| `ec58aafb` Firebase scaffold | conflict | 3 UU (gradle, pubspec) | port (G4) |
| `b4a76fe0` FCM service | conflict | 3 of 5 | port (G4) |
| `1190c29d` tap opens Email | conflict | 2 DU | port (G4) |
| `ee95d7a2` deep-link to the email | conflict | 3 DU | port (G4) |
| `dbc279af` / `d4668cb3` | conflict | — | **drop** (change + its revert) |
| `6c80d681` / `3e549a41` | conflict | — | **drop** (change + its revert) |
| `e08ff559` display_file → chat card | conflict | 1 of 3 | port (G5) |
| `92d476c8` fused doc card + preview page | conflict | 1 of 2 | port (G6) |
| `aefeb0fd` artifact store survives re-sync | conflict | 2 of 3 | port (G5) |
| `4237ee1c` docs from the output trace | conflict | 1 UU | port (G6) |
| `89cbb983` keep `output` on chat load | clean, **but redundant** | — | **drop** — upstream already maps `output`; the pick would duplicate the key |
| `9f08774e` artifact card across restart | conflict | 1 UU | port (G5) |
| `6dcdd14d` email attachment download | conflict | 1 DU | fold into G3 |
| `a9dc4b2b` send-confirmation dialog | conflict | 1 of 3 | **re-express** on upstream's prompt (G7) |
| `8ce73b97` launcher-icons dev tooling | conflict | 2 UU (pubspec) | re-add (G0) |
| `0e360243` preview contract (structured embeds) | conflict | 5 of 9 (4 DU) | port (G6) — **mandatory** |
| `37f6d355` LaTeX masking of `<details>` | conflict | 2 of 5 (upstream added the **same incident fixture**) | **drop code**, keep our fixture test as proof (G2) |
| customer `71839495` brand | conflict | 16 of 129 | re-apply on new files (customer layer) |
| customer `9a537fa2` bundle id | conflict | 1 of 2 | re-apply (customer layer) |
| customer `0fe7c88d`, `bf90b44a` | — | — | **drop** (duplicates of base commits) |

Totals: 3 cherry-picks · 4 dropped as reverts · 4 dropped as covered/obsolete
(`5131209c`, `89cbb983`, `37f6d355` code, `e864e3cb` replaced) · ~22 ported into 9
feature groups · customer layer re-applied.

## 3. Branches and history

```
upstream v4.2.0 ──► main                (fast-forward; main is an ancestor of v4.2.0)
        │
        └──► saas-base-v4  (scratch branch, one commit per feature group G0…G9)
                  │
   join commit: tree = saas-base-v4, parents = old saas-base + saas-base-v4
                  │   → saas-base fast-forwards: NO force-push, old history kept,
                  │     merge-base with upstream becomes v4.2.0 (future syncs = merges)
                  ▼
   <customer>-v4 = new saas-base + customer commits (brand, bundle id, values)
   join commit: tree = <customer>-v4, parents = old <customer> + <customer>-v4 → <customer> fast-forwards
```

- Before anything moves, tag the then-current tips as rollback anchors:
  `saas-base-pre-v4` and `<customer>-pre-v4`. Tags are named so they never match
  upstream's release trigger (`v*`).
- Upstream tags are never pushed to our origin.
- All work happens in separate worktrees off the owner's checkout. The owner's
  checkout (on the customer branch, with an uncommitted `ios/Podfile.lock`) is
  only touched at hand-over, as the owner decides (R-8).
- Completeness check before the join: every hunk of `git diff main saas-base-v4`
  maps to a feature-group row, and every behaviour of the old
  `git diff d81619b2 saas-base` maps to a row or an explicit drop in §2.

## 4. Feature groups (one commit each, in this order)

| group | content | from |
|---|---|---|
| **G0 build** | `.gitignore`; `flutter_launcher_icons` dev dependency; docs folder carried over; `docs/FORK-INVENTORY.md` listing every fork hook in an upstream file | `aeda9289`, `8ce73b97`, `docs/` |
| **G1 locked deployment** | generic build-time lock (`DeploymentPolicy` in core + one customer-owned `deployment.dart`): one Open WebUI server seeded before the first redirect, Open WebUI backend only; hides server/address/account management, backend chooser, Hermes, Direct connections, reviewer mode; **forces the on-device Apple models off** (upstream defaults them on and merges them into the model list); sign-out always keeps the server; sign-in modes from the policy (two-step kept); brand links/names from `BrandConfig`; ARB product-name rewrite tool (R-10) | `5b819447` (redesigned) |
| **G2 small behaviour** | STT/TTS default to server; refresh models + tools on resume; image generation gated on the model capability; deletion reconcile on resume/cold start (throttled); reconcile valve per R-4; LaTeX fixture test | `cb5061c3`, `8c6378bb`, `9ac412ae`, `ab897bb7`, `6eb92672`, `37f6d355` test |
| **G3 Email section** | Email tab in upstream's sidebar tab registry, shown only when the server has the email service; lazy webview; `email-*` protocol; **security fixes** over the fork's version (token only to the email origin, messages only from it, downloads through the app's authenticated client, external links https-only, storage cleared on logout) | `7cb530ef`, `c4ec13a8`, `45e840cc`, `6dcdd14d` |
| **G4 Email push** | Firebase messaging (off when the config file is absent); device registration; foreground notifications through upstream's notification service (no second plugin init); tap → Email tab → that message; **iOS push added** (the fork's was Android-only) | `ec58aafb`, `b4a76fe0`, `1190c29d`, `ee95d7a2` |
| **G5 terminal artifacts** | in-chat artifact card from `terminal:display_file` and from the durable record 0.12.2 writes as the `function_call_output` text JSON (`type:file, source:open_terminal`), so `display_file(inline=true)` is covered; HTML/SVG live render; full-screen viewer with download, also used by upstream's Files panel | `a5941903`, `1c776a2c`, `e08ff559`, `aefeb0fd`, `9f08774e` |
| **G6 document previews** | object-embed preview contract preserved on save (upstream's sanitiser flattens it — data-corrupting); one fused card per document; PDF/HTML preview page; download of the real file | `0e360243`, `92d476c8`, `4237ee1c` |
| **G7 confirmations** | upstream's prompt surface, patched to the fork's guarantees: full text (no 2000-char cut), scrollable, one at a time, answered exactly once, `false` on stream teardown | `a9dc4b2b` (re-expressed) |
| **G8 Model controls** | generic per-model controls from `info.params.model_controls`; choice stored per user per model in `ui.params.model_controls` (shared with the web client); sent as `params.model_controls` with stale options dropped; picker in the model selector; replaces the thinking toggle | new (replaces `e864e3cb`) |
| **G9 Open WebUI 0.12.2** | drift audit of the 208 server commits 0.12.0 → 0.12.2; bump `maxSupportedVersion` + its tests and the `openwebui-src` pin; memory default (`ui.memory ?? features.enable_memories`); reconnect after a server-initiated socket disconnect + refresh on `access:updated` (the one upstream gap the audit confirmed) | new |

## 5. Toolchain

| need | have | action |
|---|---|---|
| Flutter ≥ 3.47 / Dart ≥ 3.13 (upstream `pubspec.yaml:6-8`) | 3.44.2 / 3.12.2 at `/Users/smk/Dev/SDK/flutter`, shared with other checkouts | install **3.47.7** (current stable, Dart 3.13.5) as a **second** SDK next to it (R-7); use it by absolute path in the rebuild worktree |
| submodules `third_party/katex`, `third_party/mermaid` (required by `pub get`) | not initialised | `git submodule update --init --depth 1` in the worktree; `openwebui-src`, `hermes-src` stay reference-only |
| Android: AGP 9.2.1, Gradle 9.4.1, Kotlin 2.4.0, compileSdk 37, NDK 29.0.14206865, JDK 17+ | NDK 29.0.14206865 ✓, JDK 17.0.19 ✓, platforms up to 36.1 | install platform `android-37` |
| iOS: Xcode with SPM enabled, iOS 16+ | Xcode licence not accepted | owner runs `sudo xcodebuild -license` once |
| Node (markdown web-safety check) | v22.23.1 ✓ | — |

## 6. Phases (after approval)

1. **Prep** — rollback tags; second SDK; Android platform 37; submodules; baseline:
   run all upstream gates on pristine v4.2.0 and record the failure set.
2. **`main` → v4.2.0** (fast-forward, pushed). Upstream's CI runs on our public repo
   for pushes to `main` (R-6).
3. **G0–G9** on `saas-base-v4`, one commit each; after each: gates (§7.1) green or
   identical to baseline.
4. **Completeness audit** (§3), then the **join** → `saas-base`, push.
5. **Customer layer** on `<customer>-v4` → join → customer branch, push.
6. **Device E2E** (§7.2) on Android emulator and iOS simulator against a local
   Open WebUI 0.12.2; final pass against the real server once it is upgraded.
7. **Hand-over** — owner's checkout per R-8; remove worktrees; verify local ==
   remote for every branch and tag touched.

Estimate per group: G1 3–4 d · G3+G4 2–3 d · G5 1.5–2 d · G6 1.5–2 d · G7 0.5 d ·
G8 1–1.5 d · G0+G2+G9 1–1.5 d · prep/toolchain 1–1.5 d · customer layer 1 d ·
device QA 2–3 d → **≈ 13–19 focused days**.

## 7. Test plan

### 7.1 Gates (every group commit)
Upstream's CI, run locally with Flutter 3.47.7:
`flutter pub get` → `dart run build_runner build` (app and `packages/conduit_core`)
→ `dart tool/platform_ui_lint.dart` → `flutter analyze --no-fatal-warnings
--no-fatal-infos` → `dart run tool/run_test_shards.dart` → per package `dart test`
and `dart analyze --fatal-infos` → `dart run tool/check_package_boundaries.dart` →
markdown web-safety (`dart compile js` + node) → `dart run
tool/verify_arb_descriptions.dart` + `tool/validate_arb_locales.dart`.
Failure sets are diffed against the pristine-v4.2.0 baseline; a new failure blocks
the group.

### 7.2 Tests carried or added per group
- G1: router tests — a locked build never reaches server setup, backend chooser,
  account switcher, Hermes/Direct/Apple routes; sign-in shows only the allowed
  modes; two-step sign-in still completes.
- G2: image-generation availability test (ours, re-pathed); reconcile-on-resume
  throttle; reconcile valve per R-4; LaTeX-in-details incident fixture renders.
- G3/G4: protocol message tests for the Email webview bridge; notification payload →
  route; device-registration request shape.
- G5: artifact paths from `terminal:display_file` and from the durable record
  (`function_call_output` text JSON with `type: file, source: open_terminal`, inline
  or not; `exists: false` skipped); de-duplication by resolved path.
- G6: our contract tests (parsing / transport / embed utils) moved to the right
  packages: object embeds survive a save round-trip; one card per delivery; legacy
  string previews still render.
- G7: long confirmation text is shown in full; exactly one ack; `false` on teardown
  and on chat switch.
- G8: model-controls parsing; choice round-trips through `ui.params.model_controls`;
  request shape `params.model_controls`; options the model no longer offers are
  dropped before sending.
- G9: version gate accepts 0.12.2; memory default precedence; socket reconnects after
  an `io server disconnect`; `access:updated` refreshes permissions and models.
- G3 security: token script and messages restricted to the email origin; a message
  from another frame/origin is ignored; download requests carry the bearer only to
  the server's origin.

### 7.3 Device E2E matrix (Android emulator + iOS simulator, Open WebUI 0.12.2)

| scenario | pass when |
|---|---|
| first launch | goes straight to sign-in for the locked server; no server/backend/account UI anywhere |
| sign-in | password and SSO work; a two-step account completes its step |
| plain reply | streams token by token |
| reasoning model | thinking block streams, then collapses; same after reload |
| tool call (native FC) | tool tile runs → done with args/result; same after reload |
| terminal `display_file` (inline and not) | one artifact card per file live and after reload; HTML/SVG renders; full-screen + download |
| generated document | one card; preview (PDF/HTML) and download of the real file; card still right on the web client after the app saved the chat |
| long send-confirmation | full text scrolls; approve and deny both reach the server; leaving the chat denies |
| Email tab | opens, Discuss works, attachment download works |
| push | notification arrives; tap opens the Email tab on that message (device with real Firebase config) |
| model controls | options from the server; the choice changes the request and behaviour |
| memory | a fact from chat A is recalled in chat B with the server default on |
| delete message / sign out / Stop (non-admin) | stays deleted; token revoked; server generation stops |
| password change | app signs out cleanly |

## 8. Decisions for the owner

- **R-1 History:** rebuild + join commit, no force-push (rec) · merge v4.2.0 into
  `saas-base` (silently loses fork behaviour where upstream moved files) ·
  force-push fresh branches.
- **R-2 Thinking:** drop the thinking pill; Model controls sheet driven by the
  server (rec) · keep a pill mapped onto a control named `thinking`.
- **R-3 Confirmations:** adopt upstream's prompt surface and patch it to our
  guarantees; delete our coordinator (rec) · port our coordinator as-is.
- **R-4 Reconcile valve:** remove it as before, so a server-side "delete all"
  propagates (rec) · keep upstream's valve (upstream kept it deliberately).
- **R-5 Features a locked build hides:** server/address/account management,
  backend chooser, Hermes, Direct connections, on-device Apple backend, reviewer
  mode (rec, all hidden) · and also on-device web search (`conduit_ddgs`, sends
  queries from the phone to DuckDuckGo) (rec: hidden) · keep any of them.
- **R-6 Upstream CI on our GitHub:** let it run on pushes to `main` and on PRs
  (rec — public repo, free, a useful signal) · disable Actions for the fork.
- **R-7 Toolchain:** second Flutter SDK 3.47.7 beside the shared one (rec) ·
  upgrade the shared SDK in place (breaks other checkouts on 3.44.2).
- **R-8 Your uncommitted `ios/Podfile.lock`:** upstream builds iOS with Swift
  Package Manager, so it becomes obsolete — you commit or discard it before the
  checkout moves (rec) · leave it and I stop before touching that checkout.
- **R-9 Test server:** local Open WebUI 0.12.2 (via `uv`) with a scripted mock model
  for development, then one pass against the real server once upgraded (rec).
- **R-10 Localised product name:** a base tool rewrites "Conduit" in ARB values from
  the brand config, re-run by the customer branch after each sync (rec — keeps
  upstream's ARB files mergeable) · template all locales with `{appName}` in the base
  (large permanent diff against upstream).
- **R-11 Terminal `display_file`:** in-chat card **and** upstream's automatic switch
  to the Terminal → Files panel (rec — both are useful, the card survives reload) ·
  card only, as the fork had.
- **R-12 iOS push:** add it in G4 (rec; needs an APNs key uploaded to the Firebase
  project and the iOS `GoogleService-Info.plist` — owner) · Android-only as before.

## 9. Risks

- **Locked-deployment completeness:** upstream keeps adding entry points (accounts,
  backends, reviewer mode, on-device models). Mitigation: router-level guard plus
  tests that walk every route and assert the model list has only server models;
  re-run on each upstream sync.
- **Email webview token handling** was unsafe in the fork (any origin, any frame);
  G3 fixes it, and no build ships the old behaviour.
- **Document cards corrupted on save** if G6 lands late or partially: upstream's
  sanitiser flattens object embeds. G6 is one commit; no build ships without it.
- **Native platform jumps** (AGP 9, Gradle 9, iOS SPM) for Firebase/FCM — verify G4
  on a real device early in the group.
- **Upstream velocity** (611 commits in ~4 months): the join leaves `saas-base` one
  merge away from upstream; plan regular syncs rather than another rebuild.
- **Server-side dependencies:** document previews rely on the server keeping the
  fork's preview contract (server plan §3.3); Model controls rely on the admin
  configuring them and granting `chat.controls` + `chat.params`.
