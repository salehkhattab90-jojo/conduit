# Fork inventory

Every place this fork changes an **upstream** file, grouped by feature. On each
upstream sync, re-check each row: the hook still applies, still compiles, and the
behaviour it guards still holds. New files are listed per feature without detail;
they carry no merge risk. Base: upstream Conduit v4.2.0 (`dda134cd`).
`core/` = `packages/conduit_core/lib/`, `md/` = `packages/conduit_markdown/lib/`.
Design: `docs/upgrade-owui-0.12/ARCHITECTURE.md`.

## Build
| file | hook |
|---|---|
| `.gitignore` | `*.code-workspace` |
| `pubspec.yaml`, `pubspec.lock` | dev `flutter_launcher_icons` (pulls `cli_util` 0.4.2); `firebase_core`, `firebase_messaging` |
| `openwebui-src` (gitlink) | Open WebUI v0.12.2 (`6a18585f`) |

## Small behaviour
| file | hook |
|---|---|
| `core/services/settings_service.dart` | STT/TTS default to the server engine (constructor defaults + parser fallbacks) |
| `lib/core/providers/app_startup_providers.dart` | `_refreshServerCatalogOnResume`: models + tools refresh on resume |
| `core/providers/app_providers_feature_availability.dart` | image generation honours the model's `image_generation` capability; on-device web search follows the deployment policy |
| `core/sync/sync_triggers.dart` | deletion reconcile on app start and resume (5-min spacing on the sync clock) |
| `core/sync/deletion_reconcile.dart`, `core/sync/note_deletion_reconcile.dart` | candidate-fraction valve removed (server delete-all propagates) |

## Locked deployment
New: `core/deployment/{deployment_policy,ensure_locked_server}.dart`,
`lib/core/deployment/{deployment_config,deployment,deployment_providers,native_sheet_deployment,active_deployment}.dart`,
`tool/apply_brand_strings.dart`. **`lib/core/deployment/deployment.dart` is the one
file a customer branch overrides.** Code reads the deployment through
`activeDeployment`, never `kDeployment`, so tests can pin the stock one.

| file | hook |
|---|---|
| `core/navigation/route_redirect.dart` | locations the policy closes resolve as `/chat`; reviewer mode off when locked; no server while locked holds the splash |
| `core/providers/backend_mode_providers.dart` | preferred backend coerced to the policy's allowed set |
| `core/features/direct_connections/providers/direct_connection_providers.dart` | Apple on-device/PCC forced off and Direct profiles empty when Direct isn't allowed |
| `core/features/hermes/providers/hermes_providers.dart` | Hermes config empty and enable ignored when Hermes isn't allowed |
| `core/providers/app_providers_user_settings.dart` | reviewer mode stays off when locked |
| `core/providers/app_providers_sign_out.dart` | locked sign-out keeps the server |
| `core/features/web_search/services/direct_web_search_mode.dart`, `core/features/chat/providers/chat_direct_turns.dart` | `allowOnDevice` parameter |
| `core/providers/app_providers.dart`, `core/features/chat/providers/chat_providers.dart` | imports |
| `lib/main.dart` | policy override; locked seeding before `runApp` (5 s cap); guard; native sign-out/actions; license name; release-notes coordinator only when shown |
| `lib/core/router/app_router.dart` | `SsoAuthPage(initialPath: policy.ssoInitialPath)` |
| `lib/features/auth/views/authentication_page.dart` | sign-in modes filtered by policy; no back button and brand tagline when locked; SSO only from server config when locked |
| `lib/features/auth/views/sso_auth_page.dart` | `initialPath` (direct `/oauth/<provider>/login`) |
| `lib/shared/widgets/sign_out_options_dialog.dart` | no keep-server choice when locked |
| `lib/features/profile/views/profile_page.dart`, `…/about_page.dart`, `…/widgets/account_sheet.dart` | account management hidden; donation/GitHub/release-notes rows from the brand |
| `lib/core/utils/native_sheet_utils.dart` | same for the iOS native sheets; Hermes/Direct cards dropped |
| `lib/shared/services/navigation_service.dart` | login/server-connection/clear-stack go to `/authentication` when locked |
| `lib/features/release_notes/release_notes_presenter.dart` | review/support URLs from the brand |
| `lib/features/direct_connections/views/direct_connections_page.dart` | on-device web search settings only when allowed |
| `lib/core/services/callkit_service.dart`, `lib/platform/app_intents_service.dart`, `lib/shared/services/brand_service.dart` | product name from the brand |
| `test/flutter_test_config.dart` | pins the stock deployment for the whole suite (`debugDeploymentOverride`) |
| `test/features/chat/widgets/composer_overflow_items_test.dart`, `test/features/release_notes/release_notes_sheet_test.dart` | product name in expected strings taken from the English `appTitle` |

## Email section and push
New: `core/features/email/**`, `lib/features/email/**`,
`lib/features/notifications/services/email_push_service.dart`.

| file | hook |
|---|---|
| `core/features/navigation/models/sidebar_navigation_model.dart` | `SidebarTabId.email`; `SidebarTabAvailability.emailEnabled` |
| `core/models/backend_config.dart` | `enableEmail` from `features.enable_email` |
| `lib/features/navigation/providers/sidebar_providers.dart` | wires `emailEnabled` |
| `lib/features/navigation/widgets/sidebar_tab_registry.dart` | Email tab descriptor (second, after Chats) |
| `lib/features/navigation/widgets/drawer_shell_page.dart` | `EmailOpenRequestListener` around the layout |
| `lib/features/notifications/services/local_notification_service.dart` | `email_significant` channel; email tap variant; `showEmail()` |
| `lib/features/notifications/providers/notification_socket_listener.dart` | email taps open the Email tab |
| `lib/core/providers/app_startup_providers.dart` | starts `EmailPushService` after post-auth startup |
| `lib/main.dart` | guarded Firebase init before `runApp` |
| `android/settings.gradle.kts`, `android/app/build.gradle.kts` | google-services plugin, applied only when `google-services.json` exists |
| `lib/l10n/app_*.arb` | 7 Email keys |

## Terminal artifacts and document previews
New: `core/services/terminal_file_output.dart`,
`core/features/terminal/providers/terminal_artifact_providers.dart`,
`core/features/chat/utils/document_deliveries.dart`,
`lib/features/chat/widgets/{delivery_cards,document_preview_page}.dart`,
`lib/features/terminal/widgets/{terminal_artifact_page,terminal_artifact_opener}.dart`.

| file | hook |
|---|---|
| `md/src/embed_utils.dart` | `isPreviewEmbed`; shape-preserving `sanitizeEmbedsForWebUi` (strings stay strings, preview objects stay objects) |
| `core/services/api_service_base.dart` | `_sanitizeEmbedsForWebUI` returns `List<Object>?` |
| `core/features/chat/providers/chat_messages_notifier.dart` | local-echo/outbox row writes sanitized embeds |
| `core/services/streaming_helper.dart` | `onTerminalEvent(type, data, messageId)` |
| `core/features/chat/services/chat_transport_dispatch.dart` | records live `terminal:display_file` per message (upstream's auto-switch kept) |
| `lib/features/chat/widgets/assistant_message_widget.dart` | document cards + terminal artifact cards; preview-object guard in embeds |
| `lib/shared/widgets/markdown/markdown_compile_service.dart` | preview objects filtered from tool-call detail embeds |
| `lib/features/terminal/widgets/terminal_files_section.dart` | HTML/SVG opens the artifact page |
| `lib/l10n/app_*.arb` | `artifact`, `artifactCardHint`, `documentCardHint` |

## Confirmations, model controls, Open WebUI 0.12.2
New: `core/models/model_controls.dart`,
`core/features/chat/providers/model_controls_provider.dart`,
`core/providers/{server_memories_default_provider,socket_access_refresh_provider}.dart`,
`lib/features/chat/widgets/{confirmation_message_body,model_control_picker}.dart`.

| file | hook |
|---|---|
| `core/models/openwebui_chat_prompt.dart` | confirmations not truncated; `confirmText`/`cancelText`; tool-call `timeout_ms` clamp; no client timeout for plain confirmations |
| `core/features/chat/providers/openwebui_chat_prompt_provider.dart` | FIFO queue, exactly-once ack, `dismiss`, `cancelForOwner` |
| `core/features/chat/services/chat_transport_dispatch.dart` | prompt owner per dispatch; teardown declines its prompts |
| `core/services/streaming_helper.dart` | `onInteractivePromptsAbandoned` from `disposeSocketSubscriptions` |
| `lib/features/chat/widgets/openwebui_prompt_overlay.dart` | ~60 % scrollable body, inert renderer, custom button labels |
| `lib/features/chat/views/chat_page.dart` | question-form Cancel dismisses only that prompt |
| `core/models/model.dart` | `modelControls` |
| `core/models/server_user_settings.dart` | `modelControls`; `memoryEnabled` nullable + `effectiveMemoryEnabled` |
| `core/services/api_service_user_settings.dart` | `updateUserModelControls` |
| `core/providers/app_providers_user_settings.dart` | `setModelControls` |
| `core/services/api_service.dart` | import |
| `core/services/api_service_base.dart` | `params.model_controls` (stale options dropped); memory = `ui.memory ?? enable_memories ?? false` |
| `core/services/api_service_chat_completions.dart` | `targetModelItems`, `memoriesDefault` parameters |
| `core/features/chat/providers/{chat_send_message,chat_regeneration,chat_headless_completion,chat_comparison_controller}.dart` | pass the memory default / target model items |
| `core/models/backend_config.dart` | `enableMemories` from `features.enable_memories` |
| `lib/features/chat/widgets/model_selector_sheet.dart` | model-control cards after reasoning effort |
| `lib/features/profile/views/personalization_page.dart`, `lib/core/services/native_sheet_hydration_service.dart` | show the effective memory setting |
| `core/services/socket_service.dart` | reconnect after `io server disconnect`; `access:updated` refresh; `voice:play_animation` answered `{status: 'unavailable'}` |
| `lib/core/providers/app_startup_providers.dart` | `socketAccessRefreshProvider` |
| `core/utils/server_version_compat.dart` | max supported 0.12.2 |

## Tests changed in upstream files
Defaults now server STT/TTS (`settings_service_test`, `native_sheet_utils_test`,
`tts_voice_utils_test`); reconcile valve tests became delete-all tests; version
strings 0.12.2; `sendMessageSession` fakes gained the new parameters; one prompt
provider test (no plain-confirmation timeout); sync-trigger, streaming-transport,
socket, API and local-echo tests extended.
