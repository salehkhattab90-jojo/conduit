# Conduit rebuild on upstream v4.2.0 — FADI layer

Customer notes for `PLAN.md` / `ARCHITECTURE.md` (same folder; those stay
customer-agnostic on `saas-base`). This file lives only on `fadi`.
Server counterpart: `open-webui` repo, `docs/upgrade-v0.12.2/`.

## 1. Ordering
Nobody uses the app yet (owner, 2026-10-16), so the app no longer gates the server
upgrade (server plan decision **G-5** resolves to "deploy the server; the app
follows"). The rebuilt app is tested against a local Open WebUI 0.12.2 first, then
against fadi.furqaan.ai once that server is upgraded.

## 2. Customer layer on the rebuilt base (`fadi-v4`, then joined into `fadi`)

| piece | value |
|---|---|
| `lib/core/deployment/deployment.dart` → `DeploymentPolicy` | locked server `id: 'locked-server'`, name `fadi.furqaan.ai`, urls `['https://fadi.furqaan.ai']`; `allowedBackends: {owui}`; `allowAccountManagement: false`; `authModes: {credentials, sso}`; `ssoProviders: ['google']` (straight to `/oauth/google/login`, as today); on-device web search off |
| `BrandConfig` | appName `FADI`; tagline `FADI (Furqaan AI Data & Intelligence)`; no GitHub / donation / store-review links; release notes off; CallKit and license name `FADI` |
| ARB product name (R-10) | run `tool/apply_brand_strings.dart` with `FADI` (today's branch localises "FADI" in all locales; upstream now has 14) |
| Android | `applicationId "app.furqaan.fadi"` (+ upstream's debug suffix), labels `FADI` / `Ask FADI`, widget name; `namespace` unchanged |
| iOS | bundle ids `app.furqaan.fadi`, `.debug`, `.ShareExtension`, `.ConduitWidget`, `.RunnerTests` (and debug variants) across the 12 pbxproj entries; app group to match `home_widget_service.dart`; `CFBundleDisplayName FADI` + 13 `InfoPlist.strings`; Share extension "Ask FADI" |
| icons, splash, sign-in mark | the faceted-gem kit (`/Users/smk/Dev/logo`): Android adaptive + legacy mipmaps (debug variant too), iOS AppIcon (+ AppIcon-Debug), splash, `assets/icons/brand_mark.png`; generated with `flutter_launcher_icons` (G0) |
| Email | default `<server>/email/app`; no `EMAIL_APP_URL` define needed |
| Firebase (push) | `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` from the FADI Firebase project — **gitignored**, supplied at build time; APNs key uploaded to that project for iOS (R-12, owner) |

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
