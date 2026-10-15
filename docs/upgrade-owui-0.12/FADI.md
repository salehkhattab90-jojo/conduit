# Conduit × Open WebUI 0.12 — FADI layer

Customer notes for `PLAN.md` / `ARCHITECTURE.md` (same folder; those stay
customer-agnostic on `saas-base`). This file lives only on `fadi`.
Server-side counterpart: `open-webui` repo, `docs/upgrade-v0.12.2/` (PLAN.md decision
**G-5**, FADI.md).

## 1. Ordering (G-5)
1. Track A ships as a new FADI APK/IPA **before** the server upgrade's step 3.4.
   It is dual-version, so it can go out while fadi.furqaan.ai is still on 0.9.2.
2. Server upgrade deploys. No flag day: if the server rolls back to 0.9.2, the app
   keeps working.
3. Old app builds still in users' hands after the server upgrade get today's
   degraded behaviour (no live text, no cards). Keep the server-side protections
   below until the owner confirms everyone updated.

## 2. Server settings this app build assumes (fadi.furqaan.ai, 0.12.2)

| setting | value | why (plan row) |
|---|---|---|
| Model controls on **vini-1.0**, **vidi-1.0** | key `thinking`, options off / auto / on, default auto (server FADI.md §2) | the app's Model controls sheet shows them (#6) |
| Model controls on **vici-1.0** | same key, GLM params (`extra_body.thinking.type`) (T-3) | with controls present the app stops sending Qwen `chat_template_kwargs` to GLM |
| `meta.capabilities.thinking` | stays `true` on all three | the legacy pill uses it while the server is still 0.9.2 |
| Permissions `chat.controls` + `chat.params` | granted to user groups (T-2) | otherwise the server silently drops the app's choice → default (Auto) |
| User-input builtin (`ask_user`) | off (C-6) — on only if D-2 adds the native sheet | #2 / #13 |
| Tool permissions ("ask") | off (C-5) | old builds can't render approvals |
| Default interface settings | `memory: true` (server ARCHITECTURE §3.8) | reaches the app through `GET /users/user/settings` (#7) |
| Open Terminal context | shared (not per chat) | per-chat context is unsupported (Track B) |
| MFA, enforced temporary chats | off | unsupported (Track B) |
| `WEBSOCKET_EVENT_CALLER_TIMEOUT` | 600 (email release) | send_email confirmations on mobile wait for the human |

The Email tab is unaffected (webview keys on `localStorage.token`; 0.12 frontend
still does). The send_email / email_settings confirmation dialog path is unchanged.

## 3. Test setup (phase 1 + 6)
- `kLockedServerUrl` (`lib/core/constants/locked_server.dart`) is temporarily
  pointed at the local test servers for emulator runs (`http://10.0.2.2:8092` for
  0.9.2, `http://10.0.2.2:8122` for 0.12.2) and **reverted before any commit**.
- Debug build without `android/app/google-services.json` (FCM off), `flutter build apk
  --debug`, `adb install -r`; emulator `Pixel_10_Pro` (adb at
  `~/Library/Android/sdk/platform-tools/adb`, screenshots via `screencap` + `pull`).
- iOS simulator needs the Xcode licence accepted first (`sudo xcodebuild -license`,
  owner).
- Acceptance (D-4): the server runbook's rehearsal (open-webui FADI.md §3.3) runs
  migrations on a copy of the data; booting that copy on a side port (LAN/VPN only,
  pinned `WEBUI_SECRET_KEY`, image by sha tag) gives a 0.12.2 server with the real
  vidi/vini/vici models and real 0.9.2-era chats. Point a debug build's
  `kLockedServerUrl` at it for one pass of the PLAN §4 matrix. Owner-run.

## 4. Post-upgrade smoke test on fadi.furqaan.ai (owner, ~10 min)
Vidi plain reply streams live · Vini with thinking On shows the thinking card ·
a docgen document shows one card with preview + download · an Open Terminal
`display_file` shows an artifact card · delete a message, reopen, still gone ·
sign out, sign back in · Email tab opens and Discuss works · send_email
confirmation dialog appears and both buttons work.
