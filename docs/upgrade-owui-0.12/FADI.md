# Conduit rebuild on upstream v4.2.0 — FADI layer

Customer notes for `PLAN.md` / `ARCHITECTURE.md` (same folder; those stay
customer-agnostic on `saas-base`). This file lives only on `fadi`.
Server counterpart: `open-webui` repo, `docs/upgrade-v0.12.2/`.

## 1. Ordering
Nobody uses the app yet (owner, 2026-10-16), so the app no longer gates the server
upgrade (server plan decision **G-5** resolves to "deploy the server; the app
follows"). The rebuilt app is tested against a local Open WebUI 0.12.2 first, then
against fadi.furqaan.ai once that server is upgraded.

## 2. Customer layer on the rebuilt base (built as `fadi-v4`, joined into `fadi`)

| piece | value |
|---|---|
| `lib/core/deployment/deployment.dart` → `DeploymentPolicy` | locked server `id: 'locked-server'`, name `fadi.furqaan.ai`, urls `['https://fadi.furqaan.ai']`; `allowedBackends: {owui}`; `allowAccountManagement: false`; `authModes: {credentials, sso}`; `ssoProviders: ['google']` (straight to `/oauth/google/login`, as today); on-device web search off |
| `BrandConfig` | appName `FADI`; tagline `FADI (Furqaan AI Data & Intelligence)`; no GitHub / donation / store-review links; release notes off; CallKit and license name `FADI` |
| ARB product name (R-10) | `dart run tool/apply_brand_strings.dart --name FADI` over all 14 locales (whole-word only: inflected forms such as cs/sk/pl "Conduitu" stay); then `flutter gen-l10n` |
| Android | `applicationId "app.furqaan.fadi"` (+ upstream's `.debug` suffix), manifest labels `FADI` / `Ask FADI`, `strings.xml` values, assistant overlay label; `namespace`, Kotlin package and channel names unchanged |
| iOS | bundle ids `app.furqaan.fadi`, `.debug`, `.ShareExtension`, `.ConduitWidget`, `.RunnerTests` (12 pbxproj entries); `Info.plist` and every `*.lproj/*.strings` **value** says FADI (keys untouched: App Intents uses them); Share extension "Ask FADI". **App group is still upstream's** `group.app.cogwheel.conduit` (as in the earlier fork): an iOS release needs FADI's own app group on its Apple team, changed in the pbxproj (`APP_GROUP_ID`, 4 entries) and `lib/platform/home_widget_service.dart` together |
| icons, splash | Faceted Gem sources in `assets/icons/` (`icon.png`, `icon_foreground.png`, `splash.png`, `splash_dark.png`; masters in `/Users/smk/Dev/logo`); `flutter_launcher_icons` + `flutter_native_splash` config in `pubspec.yaml`, regenerate with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`. Debug builds show the FADI icon too (Android debug mipmaps removed; iOS `AppIcon-Debug` holds the FADI icons). The sign-in page has no logo upstream, so the old sign-in mark is gone (optional follow-up: a `BrandConfig` sign-in image) |
| Email | default `<server>/email/app`; no `EMAIL_APP_URL` define needed |
| Firebase (push) | `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` from the FADI Firebase project — **gitignored**, supplied at build time. Android: dropping the file in is enough. iOS (owner, once): add the iOS app with bundle id `app.furqaan.fadi` in Firebase; upload an APNs Auth Key (.p8, Key ID + Team ID) under Cloud Messaging; in Xcode add Push Notifications (writes `aps-environment`) and Background Modes → Remote notifications; App ID/profile with Push; `pod install`; on a device check token, foreground notification, tap → Email message, and that sign-out stops pushes. Don't set foreground presentation options in the AppDelegate (pushes would show twice) |

## 3. Server settings the app expects (fadi.furqaan.ai on 0.12.2)

| setting | value | why |
|---|---|---|
| Model controls on vini-1.0, vidi-1.0, vici-1.0 | key `thinking`, options off / auto / on (server FADI.md §2, T-3) | replaces the app's thinking toggle (G8) |
| `chat.controls` + `chat.params` for user groups | granted (T-2) | otherwise the server drops the app's choice |
| Default interface settings | `memory: true` | memory default (G9) |
| Email service | reachable at `/email/app` and `/email/devices/*` through the same origin | Email tab + push (G3/G4) |
| `WEBSOCKET_EVENT_CALLER_TIMEOUT` | 600 | send_email confirmations wait for the human (G7) |
| Tool permissions / `ask_user` / MFA / enforced temporary chats | any — the rebuilt app supports them (upstream) | no longer restricted for the app's sake |

## 4. Test setup
- Development: local Open WebUI 0.12.2 via `uv` with a mock model; a debug build
  with `deployment.dart` pointed at `http://10.0.2.2:<port>` — **never committed**.
- Android emulator `Pixel_10_Pro` (adb `~/Library/Android/sdk/platform-tools/adb`,
  screenshots via `screencap` + `pull`); iOS simulator after the Xcode licence.
- Push is only testable with the real Firebase config on a device or emulator with
  Google Play services.
- Final pass: release build against the upgraded fadi.furqaan.ai, PLAN §7.3 matrix.

## 5. Smoke test after the server upgrade (owner, ~10 min)
Sign in with Google · Vidi reply streams live · Vini with thinking On shows the
thinking block · a generated document shows one card, preview and download · an
Open Terminal `display_file` shows an artifact card · Email tab opens, Discuss
works, an attachment downloads · a send_email confirmation shows the whole draft
and both buttons work · a push notification opens the right email.
