# Conduit fork on upstream v4.2.0 — architecture

Companion to `PLAN.md`. Customer-agnostic: nothing here names a deployment.
Paths are upstream v4.2.0 (`dda134cd`). `core/` = `packages/conduit_core/lib/`,
`md/` = `packages/conduit_markdown/lib/`. Server references are Open WebUI 0.12.2.

## 0. Rules

1. **Upstream seams first.** Where upstream already has a mechanism (tab registry,
   notification service, prompt surface, structured output, per-model settings), the
   fork plugs into it instead of carrying its own parallel copy.
2. **Core stays Flutter-free.** `tool/check_package_boundaries.dart` bans Flutter
   imports in `core/`; policy, protocol and parsing go in `core/`, widgets and
   platform glue in `lib/`.
3. **New files over edits.** Fork logic lives in new files; edits to upstream files
   are small hooks. Every hook is listed in `docs/FORK-INVENTORY.md` (new, G0) with
   its file, so each upstream sync and the completeness audit check one list.
4. **One place for customer values.** A deployment is described by one Dart file
   (`lib/core/deployment/deployment.dart`) plus native identity files. The base ships
   the stock values; the customer branch overrides only those.
5. **Upstream gates stay green.** platform-UI seam lint, package boundaries,
   markdown web-safety, ARB validators — fork code follows the same rules.

## 1. G1 — Locked deployment (replaces `5b819447`)

Upstream has no preconfigured-server support (no MDM, managed config or
`--dart-define` path). Since the fork was written, it gained multi-account,
multi-address failover, a backend chooser, Hermes, Direct connections, on-device
Apple models and reviewer mode — each an entry point the lock must close.

### 1.1 Seam
```
core/deployment/deployment_policy.dart     (pure Dart)
  class LockedServer { id, name, List<String> urls }      // urls[0] primary, rest failover
  class DeploymentPolicy {
    LockedServer? lockedServer;                            // null = stock Conduit
    bool allowAccountManagement;                           // add/switch accounts, addresses
    Set<PreferredBackend> allowedBackends;                 // {owui} = Open WebUI only
    Set<String> authModes;                                 // subset of credentials|sso|ldap|token
    List<String>? ssoProviders;                            // one entry => direct /oauth/<p>/login
    bool allowOnDeviceWebSearch;                           // conduit_ddgs (decision R-5)
    static const unlocked = …;
  }
  final deploymentPolicyProvider = Provider((_) => DeploymentPolicy.unlocked);

lib/core/deployment/deployment_config.dart  (app layer)
  class BrandConfig { appName, tagline, licenseAppName, callkitAppName,
                      githubUrl?, donationUrls?, storeReviewUrls?, showReleaseNotes }
  class DeploymentConfig { DeploymentPolicy policy; BrandConfig brand;
                           const DeploymentConfig.stock(); }
lib/core/deployment/deployment.dart         (THE customer-owned file)
  const kDeployment = DeploymentConfig.stock();
```
`main.dart` overrides `deploymentPolicyProvider` with `kDeployment.policy`, the same
host-port pattern as `core/providers/host_ports.dart`.

### 1.2 Where the policy is read

| seam (upstream file:line) | locked behaviour |
|---|---|
| bootstrap, new `core/deployment/ensure_locked_server.dart`, called from `main.dart` after storage is ready (≈279-330) and after any sign-out | idempotent: save one `ServerConfig` with the fixed id, its URLs as `OpenWebUiServer.endpoints` (`core/models/openwebui_registry.dart:191-202`), `setActiveServerId` (`core/services/optimized_storage_service.dart:3449`), `PreferredBackend.owui`. A seeded server looks like the normal "signed out, server kept" state, so the redirect lands on sign-in |
| redirect policy `core/navigation/route_redirect.dart` | no active server → splash (not `backendChooser`, :281-294); `backendChooser`, `serverConnection`, `addServer`, `login`, `accounts`, `serverAddresses*`, `hermes*`, `direct*` → `/authentication` or `/chat`; remove them from `isLocalBackendSetup` (:122) and the accountless list (:47-67). Unit-tested in core like the existing policy |
| `lib/core/router/app_router.dart` | optional: skip registering the locked-out routes; the redirect stays the real guard |
| backend gating | `appleOnDeviceEnabledProvider` / `applePccEnabledProvider` (`core/features/direct_connections/providers/direct_connection_providers.dart:219,232`, **default true**, merged into the model list by `core/providers/app_providers_models.dart:5-24`) forced false; Direct profiles empty; `hermesEnabledProvider` false; `PreferredBackend` writes outside `allowedBackends` ignored (`core/providers/backend_mode_providers.dart:21`) |
| sign-in `lib/features/auth/views/authentication_page.dart` | modes filtered by `policy.authModes` (:162-168); back button to server setup hidden (:410-414); header shows `brand.tagline` (:615-624); SSO availability from `backendConfigProvider`, never the "no config ⇒ SSO on" fallback (:147-168); two-step sign-in (`openwebui_two_step_form.dart`) untouched |
| SSO `lib/features/auth/views/sso_auth_page.dart:241` | new `initialPath`; `/oauth/<provider>/login` when exactly one provider is allowed, else upstream's `/auth` page |
| sign-out (`shared/widgets/sign_out_options_dialog.dart` + 3 callers) | always keep the server (no "remove server" choice) |
| account surfaces: `profile_page.dart:266-330`, `manage_accounts_page.dart`, `server_addresses_page.dart`, `account_actions.dart`, `account_sheet.dart:410-435`, iOS native sheet (`core/utils/native_sheet_utils.dart:164-452`) and its action handlers (`main.dart:618-660, 761, 767, 950`), `sidebar_user_pill.dart` Hermes/Direct rows | hidden when `!allowAccountManagement` |
| navigation helpers `shared/services/navigation_service.dart:192-201`, `user_friendly_error_handler.dart:392` | go to `/authentication` instead of server setup |
| reviewer mode (`route_redirect.dart:98`, toggled from the server page) | unreachable once the server page is gone |

### 1.3 Brand surfaces (read `BrandConfig`, show only when a value is set)
Support/GitHub/donation links (`native_sheet_utils.dart:86-90, 317-320, 610-623`;
`profile_page.dart:195-230`; `about_page.dart:23, 136-143`;
`core/features/support/support_links.dart`), release notes and store-review links
(`main.dart:1583`, `chat_page.dart:3744`, `release_notes_presenter.dart:36,60`,
`release_links.dart:3-6`), license page name (`main.dart:863`, `about_page.dart:186`),
CallKit `appName` (`core/services/callkit_service.dart:206`), App Intents strings
(`platform/app_intents_service.dart:868-996`), `brand_service.dart:263`.

**Localised product name:** 14 ARB locales carry ~28 user-visible values with
"Conduit". Templating them with `{appName}` would rewrite every locale against
upstream (a permanent merge cost). Instead the base adds
`tool/apply_brand_strings.dart`: it rewrites "Conduit" in ARB *values* (never keys)
from `BrandConfig.appName` and is re-run by the customer branch after each upstream
sync (decision R-10). Native identity (Android `applicationId`, labels, iOS bundle
ids ×12 / 7 distinct, app group, display names in `Info.plist` and 13 `.lproj`
folders, icons, splash) stays a customer-layer edit; platform channel names
(`app.cogwheel.conduit/...`) and the Android `namespace` stay unchanged.

## 2. G2 — Small behaviour

| change | seam |
|---|---|
| STT/TTS default to the server engine | `core/services/settings_service.dart:436-459, 924, 931` (cherry-pick `cb5061c3`) |
| refresh models + tools on resume | `lib/core/providers/app_startup_providers.dart` resume branch (cherry-pick `8c6378bb`, verify imports) |
| image generation only when the model has the capability | `core/providers/app_providers_feature_availability.dart:208-235`, reuse `_modelSupportsFeature` (:189-206) |
| deletion reconcile on resume / cold start, 5-min debounce | `core/sync/sync_triggers.dart:91-96, 112-115` → `syncEngine.reconcileNow()` |
| reconcile fraction valve (R-4) | `core/sync/deletion_reconcile.dart:30-45, 168-195`, `note_deletion_reconcile.dart:15-17, 121-140`; keep the session-liveness preflight |
| LaTeX inside `<details>` | upstream's tag masking (`lib/shared/widgets/markdown/markdown_compile_service.dart:935-960`) covers the incident; port only the incident fixture regression test, drop the fork's region masker |

## 3. G3 — Email section

### 3.1 Placement
- `core/features/navigation/models/sidebar_navigation_model.dart:4`: append `email`
  to `SidebarTabId` (persisted by name); add `emailEnabled` to
  `SidebarTabAvailability` (:8-24), wired in
  `lib/features/navigation/providers/sidebar_providers.dart:27-34`.
- New `core/features/email/email_app_config.dart`: `EMAIL_APP_URL` define,
  `resolveEmailAppUri(serverUrl)` (default `<server>/email/app`), message-type
  constants, pure builders for the token/theme/open scripts with a fixed target
  origin and escaping, `isAllowedEmailOrigin` — unit-tested.
- Availability: the server's `/api/config` carries `features.enable_email` (this fork
  family's Open WebUI, where the web client gates its Email nav on the same flag);
  it is parsed into `BackendConfig` and drives `SidebarTabAvailability.emailEnabled`,
  so a server without the email service never shows the tab.
- New `lib/features/email/views/email_tab.dart` + a descriptor in
  `lib/features/navigation/widgets/sidebar_tab_registry.dart:133-198`
  (icons `mail`/`envelope`, `isVisible: hasOpenWebUi && emailEnabled`, search hint
  string). Tab bodies stay mounted (`sidebar_page.dart:77-121`), so the WebView is
  created on the first `active == true`, keyed on `(accountId, emailUri)`, with the
  sidebar paddings (`sidebar_layout_contract.dart:118,134`).

### 3.2 Security (fixes over the fork's version)
The fork injected the session token on every page load whatever the origin, used
`postMessage(…, '*')`, trusted messages from any frame, downloaded any URL with the
bearer via a raw `Dio()`, and launched any URL. New rules:
- token seeded by an `AT_DOCUMENT_START` user script restricted with
  `allowedOriginRules` to the email origin (pattern:
  `lib/features/direct_connections/widgets/direct_mcp_app_view.dart:110-143`), and the
  `email-token` message sent only after `onLoadStop` confirms that origin, with an
  explicit target origin;
- the `emailHost` handler accepts only main-frame messages from the email origin;
- downloads go through `ApiService.dio` (`core/services/api_service_base.dart:127`), so
  TLS / self-signed / mTLS settings apply and `ApiAuthInterceptor` attaches the bearer
  only for the server's own origin (`core/auth/api_auth_interceptor.dart:145-195`);
  per-request `Options(responseType: bytes, receiveTimeout: 2 min)`;
- `email-open-url` launches externally only for `https` URLs;
- logout and account switch clear WebView storage
  (`lib/platform/webview_cookie_helper.dart`), because SSO reads `localStorage.token`
  as a fallback (`sso_auth_page.dart:496-513`).
The JS handler signature moves to upstream's `JavaScriptHandlerFunctionData`
(flutter_inappwebview 6.2 beta).

### 3.3 Open request
`EmailOpenRequest` + `PendingEmailMessage` notifiers in
`core/features/email/providers/`. An `EmailOpenRequestListener` wraps
`DrawerShellPage.layoutBuilder` (`lib/features/navigation/widgets/drawer_shell_page.dart:76`,
inside the scope where `SidebarDrawerControllerScope.maybeOf` works): set
`SidebarTabId.email` (through `selectSidebarTab` so tab callbacks fire), open the
drawer, consume. The tab sends `email-open {id}` once loaded.

## 4. G4 — Email push

- `pubspec.yaml`: `firebase_core`, `firebase_messaging`.
- `main.dart` (≈334-365, before `runApp`): `Firebase.initializeApp()` guarded — no
  platform config file ⇒ push is off, the app runs normally;
  `FirebaseMessaging.onBackgroundMessage` with a top-level entry point.
- New `lib/features/notifications/services/email_push_service.dart`: permission,
  token + refresh → registry, foreground messages → `LocalNotificationService`,
  `onMessageOpenedApp` / `getInitialMessage` → the email open path. It **never**
  initialises the notifications plugin itself (the plugin has one tap callback;
  `VoiceCallNotificationService` already competes for it).
- `lib/features/notifications/services/local_notification_service.dart`: second
  Android channel `email_significant` (the server names it); `NotificationTap`
  gains an `email(messageId)` variant decoded in `_onResponse` / `launchTap`; core
  `NotificationKind` is left alone. `notification_socket_listener.dart:_handleTap`
  routes it to the open request (§3.3).
- New `core/features/email/services/email_device_registry.dart`:
  `POST /email/devices/register {device_id, platform, fcm_token}` and
  `DELETE /email/devices/{device_id}` on `ApiService.dio` with
  `suppressAuthFailureNotification`; unregister after logout uses
  `candidateAuthTokenExtraKey` with the last bearer instead of a raw client.
  `device_id` (uuid) persisted per account. Start after post-auth startup
  (`app_startup_providers.dart:1187`); unregister on sign-out (:1243) and account
  switch (:133).
- Android: `com.google.gms.google-services` declared `apply false` in
  `settings.gradle.kts`, applied in `app/build.gradle.kts` only when
  `google-services.json` exists (gitignored); verify the plugin against AGP 9.2.
- iOS (new — the fork's push was Android-only): `aps-environment` in the Runner
  entitlements, `GoogleService-Info.plist` (gitignored) in the Runner target via
  SPM-resolved FlutterFire, `remote-notification` background mode; needs an APNs key
  in Firebase (owner, decision R-12).

## 5. G5 — Terminal artifacts

What 0.12.2 records: `display_file` results are rewritten by
`build_terminal_file_tool_result` (server `utils/middleware.py:297-337`) to
`{type:'file', source:'open_terminal', path, full_path, name, mime_type,
terminal_selector, terminal_id|terminal_url, displayed?, page?}` and stored as the
JSON **text** of the `function_call_output` (not in `files[]`). With
`inline=true` no `terminal:display_file` event is sent (`:1343-1345`). The web
client reads the text JSON (`structuredOutput.ts:168-194`).

- Core: `openTerminalFilesFromOutput(List output)` beside
  `core/services/structured_output.dart:109-134`, mirroring the web's parser
  (requires `type`, `source`, `path`, `terminal_selector`; skips `exists:false`).
  This replaces the fork's argument/`exists` heuristic and yields the resolved path.
- Live cache: `onTerminalEvent` (`core/services/streaming_helper.dart:625, 3533-3542`)
  also passes the resolved target message id; the per-message path store becomes a
  core Riverpod notifier written in `chat_transport_dispatch.dart:521`.
- Card: in `lib/features/chat/widgets/assistant_message_widget.dart` beside the
  files/embeds block (:1348-1360), union of the live store and the durable record,
  de-duplicated by resolved path. Tap opens the viewer.
- Viewer: the fork's full-screen artifact page (sandboxed `WebContentEmbed`, Preview /
  Source, Download via `TerminalService.downloadFile`) moves to
  `lib/features/terminal/widgets/terminal_artifact_page.dart`; upstream's
  `showTerminalFilePreview` (`terminal_files_section.dart:390-400`) gains an HTML/SVG
  branch that pushes it, so the Files panel benefits too.
- Upstream also auto-switches the sidebar to Terminal → Files on every
  `display_file` (`chat_transport_dispatch.dart:521-531`); keep or replace with
  card-only (decision R-11).

## 6. G6 — Document previews (mandatory)

The server's document tool returns, per delivery, a real file in `files[]` and,
optionally, a preview embed: an HTML string (legacy) or an object
`{type:'preview', url, name, content_type}` (current contract; comes from this
fork family's server, not stock Open WebUI).

Upstream today **corrupts** both shapes on save:
- `md/src/embed_utils.dart:47-59` `sanitizeEmbedsForWebUi` flattens every embed to a
  string (an object becomes its bare URL) — used by `createConversation`
  (`core/services/api_service_chats.dart:50,77,119` → `api_service_base.dart:576`);
- the local-echo / outbox row (`core/features/chat/providers/chat_messages_notifier.dart:5589-5590`)
  writes the normalised list verbatim, so string embeds go back as `{src: "<html>"}`
  objects the web client can't render (an upstream bug, independent of previews).

Changes: `isPreviewEmbed` + a shape-preserving `sanitizeEmbedsForWebUi`
(`List<Object>`: strings stay strings, preview objects keep
`type/url/name/content_type`) in `md/` (pure, dart2js-safe); used in both save paths;
guards so preview objects never reach `WebContentEmbed` as a URL
(`assistant_message_widget.dart:1898-1912`, `markdown_compile_service.dart:1386-1390`).
Pairing (preview object + its file / legacy HTML + file / HTML-only artifact), the
fused card with extension identity, and the preview page (`PdfInlineView` for PDF
previews, sandboxed `WebContentEmbed` for HTML; download of the real file through
`getFileContent`) are ported as new files in `lib/features/chat/widgets/`, collecting
from the message and every `output[]` item. Contract tests move to `md/` and
`core/` test folders.

## 7. G7 — Confirmations

Upstream shows server `confirmation` requests in a composer prompt
(`core/models/openwebui_chat_prompt.dart`, `…/openwebui_chat_prompt_provider.dart`,
`lib/features/chat/widgets/openwebui_prompt_overlay.dart`). The fork's guarantees,
re-expressed on it:

| guarantee | change |
|---|---|
| full text | drop the 120 / 2000 caps for confirmations (`openwebui_chat_prompt.dart:245-246, 265`); keep them for question forms |
| readable | overlay body up to ~60 % height, scrollable; inert renderer (bold + blockquote only, no links/HTML) replaces plain `Text` (`openwebui_prompt_overlay.dart:326-341`); `confirm_text` / `cancel_text` carried through the prompt model and used for the buttons |
| one at a time, nothing dropped | FIFO queue in the provider instead of cancel-then-replace (`openwebui_chat_prompt_provider.dart:46`); entries cancelled while queued are skipped |
| answered exactly once | already true (`_settle`, :127-134); kept per queue entry |
| `false` on teardown | stream teardown (`streaming_helper.dart` `disposeSocketSubscriptions`) notifies dispatch, which cancels that conversation's prompts |
| no silent auto-deny | plain confirmations: no 2-minute client timeout (the server waits per `WEBSOCKET_EVENT_CALLER_TIMEOUT`); tool-call approvals: honour `timeout_ms`, clamped 60–240 s like the server |

The fork's own coordinator is deleted (decision R-3).

## 8. G8 — Model controls (replaces the thinking toggle)

Server: `info.params.model_controls = {key: {label, description?, default?, display?,
options: {opt: {label}}}}` (server `utils/models.py:35-53`); request
`params.model_controls = {modelId: {key: opt}}` (`main.py:1212-1225`), applied server
side (`utils/payload.py:20-34`); unknown option ⇒ 400; dropped for non-admins
without `chat.controls` + `chat.params`. The web stores the choice **per user, per
model** in `ui.params.model_controls` and sends it after chat params
(`ModelControls.svelte:21, 50-73`; `Chat.svelte:4192-4197`).

- `core/models/model.dart`: typed `modelControls` accessor over
  `metadata['info']['params']['model_controls']` (already parsed, :279-285).
- `core/features/chat/providers/model_controls_provider.dart` (new, modelled on
  `reasoning_effort_provider.dart:154-200`): read/write `ui.params.model_controls`
  through a new `updateUserModelControls` beside `updateUserReasoningEffort`
  (`core/services/api_service_user_settings.dart:81-107`), so the choice is shared
  with the web client.
- Payload (`core/services/api_service_base.dart:1537…1723`): after chat params are
  merged, set `params.model_controls = {model: choice}` with options no longer offered
  by the model dropped (avoids the 400).
- UI: a controls section in `lib/features/chat/widgets/model_selector_sheet.dart`
  beside reasoning effort, hidden for pipe/direct models and when the user lacks the
  two permissions.
- The fork's thinking toggle, `chat_template_kwargs` injection and
  `features.thinking_mode` are not ported; a deployment that wants a thinking switch
  configures it as a model control on the server.

## 9. G9 — Open WebUI 0.12.2

- Drift audit of the 208 server commits from upstream's vendored pin (`f8ae8a6c`,
  0.12.0) to `v0.12.2` (`6a18585f`), limited to routes, socket events and payloads the
  app consumes; findings become fixes in this group.
- `core/utils/server_version_compat.dart:20,23` → `0.12.2`; tests
  `core/test/utils/server_version_compat_test.dart`,
  `test/shared/widgets/server_version_warning_card_test.dart:84`; `openwebui-src`
  gitlink → `6a18585f`.
- Memory default: parse `features.enable_memories` into `BackendConfig`
  (`core/models/backend_config.dart`); `ServerUserSettings.memoryEnabled` becomes
  nullable; payload uses `ui.memory ?? enable_memories ?? false`
  (`api_service_base.dart:1735-1744`), as the web client does.
- Server-initiated socket disconnect (0.12 drops sockets on password, MFA, role and
  group changes): `core/services/socket_service.dart:1410-1436` `_handleDisconnect`
  reconnects with backoff when `reason == 'io server disconnect'` and the transport
  should stay up; `access:updated` refreshes permissions and models.
- `voice:play_animation` (0.12.1 builtin tool for voice avatars) is a socket call the
  server waits up to 3 s on; the app answers `{status: 'unavailable'}` at once, since
  it draws no avatar.
- Already correct upstream, no change: final `done` after a mid-turn error
  (`streaming_helper.dart:3961-4013`).
- Drift audit result (0.12.0 → 0.12.2, 208 commits): nothing breaks the app. Parity
  gaps left for later, not in this rebase: realtime voice no longer cancels on
  background noise (server sends `interrupt_response: false`; client should pause,
  then cancel only on a real transcript); channel mute (`is_channel_muted`,
  `channel:mute`); channel apps (`data.app` cards); a regenerate in a multi-model turn
  should resend the stored `models` list.

## 10. Already covered by upstream (not re-implemented)

Responses-style streaming and `output[]` rendering; socket request acks
(`request:terminal`, `:state`, `request:elicitation`, `request:interaction:done`);
`ask_user` question prompts; tool-call confirmation text; per-message delete with
legacy fallback; POST sign-out; two-step sign-in; pending accounts; enforced
temporary chats; chat `active` state; per-chat Stop for non-admins; saved-reply
recovery on 409 / non-2xx; provider 401/403 vs session expiry; knowledge API moves;
`ui` settings explicit-null clears; password change → sign out; `output` kept on chat
load; LaTeX inside `<details>`; composer pill gating.
