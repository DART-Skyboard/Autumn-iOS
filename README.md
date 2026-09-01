# Autumn iOS

Native SwiftUI port of [leatr.xyz](https://leatr.xyz) (DART-Skyboard/Autumn `main` @ c9e6512 + admin mailbox PR #29 / 52a42bc).

Not a WKWebView of the site. Bundle id `com.dartmeadow.autumn` · Team `L7AHWS9Q6V` · build 53 / 1.0.2.

This pass lands **architecture + core loop**, not full web parity. Linux CI here cannot compile Xcode.

## What landed

1. **App shell** matching web layout: BRPN SceneKit on top, chat bottom, left GEO/MAR/AERO + gated ADMIN, right MIST/STAR/SHARD/SYS.
2. **GitHub OAuth** via `ASWebAuthenticationSession` + device flow, same public client id `Ov23li2K0njEqO1WTSdD`. GAS `?action=exchange&code=` supported if `autumn://oauth?code=` lands. **No PAT paste. OAuth tokens in Keychain only.**
3. **Chat + grammar engine** — local port of `js/autumn-grammar-engine.js` `processForChat` (tokenize, FRP, Core Cognition frozen True, reflex never loop, per-user memory). Replies locally; no side LLM required.
4. **GAS journal write** — live `AUTUMN_GAS_URL` from Autumn `index.html`; `ashwrite` with `Content-Type: text/plain`, same body as `_ashFlushNow`.
5. **Feedback submit** — GAS ashwrite path **`feedback/inbox.json`** append `{id,ts,cat,msg,user}`. Other apps depend on this path; it is unchanged.
6. **Admin MSG mailbox** (web PR #29) — one mailbox for all types. Tabs **DATA / ASH / MSG** only. MSG folders **inbox / analysis / read / trash** (`feedback/inbox.json`, `feedback/analysis.json`, …). GAS `ashread` then GitHub Contents fallback. Move/delete via GAS replace-write. No FEED tab, no separate MSG overlay.
7. **Theme + scrim** — VOID DAY NIGHT STEALTH DEPARTURE ASH TREE ARIEL AUTO; overlays FROST STEAM CLEAR HAZE DUSK DEEP VOID. Chrome implemented for VOID / DAY / ARIEL (and the rest as colorways). No 236MB theme videos in this pass.
8. **Admin enable** — profile toggle gated to GitHub user `dartsolarpunk`, persisted as `_aut_admin_enabled` like the web flag.
9. **Math OOO builtin** — parentheses/geometry first, then exponents, `*/`, `+-`.
10. **Ash Star 3D** — SceneKit spawn on the BRPN scene, never a chat card. Full plasma-curve animation is TODO.
11. **TTS** — existing `AVSpeechSynthesizer` path kept.

## Remaining (honest)

| Module | Web source | Status |
|---|---|---|
| MIST multiplayer overlay | `js/mist-module.js` | GameKit scaffold; GAS presence + maze overlay TODO |
| Ash Star plasma curves | `js/ash-star-archive.js` | SceneKit spawn stub only |
| Ash Shard | `js/ash-shard-module.js` | Stub sheet |
| SYS broadcast compose | `index.html` SYSTEM BROADCAST + `system-broadcast.json` | Stub sheet |
| ArcLake | `js/arclake_studio.js` | Legacy ToolsView panel unused in new shell |
| Mantis / Radar | `index.html` MANTIS + `MantisNavigationView.swift` | Existing view unused in new shell |
| Grammar Study train | `js/autumn-grammar-engine.js` Grammar Study | ASH tab stub + live admin chat |
| WordNet buckets | `js/wordnet_loader.js` | `WordNetStore.swift` exists; no bundled JSON |
| Theme videos | `assets/*.mp4` | Not bundled |
| DATA console (users/ACL) | `index.html` `_admRenderData` | Contract readout only |
| Full 337k grammar engine | `js/autumn-grammar-engine.js` | Enough of `processForChat` to reply; research/WordNet/habitat compile is partial |
| Arc Forge / World Studio / Nate | `arc-forge.html` `worldstudio.html` `nate.html` | Not ported |

## LEATR

- Core Cognition always True (frozen).
- Reflex never loops.
- Never mix users (per-owner memory + journal uid).
- No secrets in the client. Journal via GAS into `leatr-ash`.

## Auth

Guest-first (same as web). Connect GitHub from the profile chip. Device flow opens `github.com/login/device` in `ASWebAuthenticationSession`. Admin chrome only after Enable Admin as `dartsolarpunk`.

## Layout

```
Sources/
  LEATRCore/           CoreCognition, GrammarEngine, MathOOO, existing LEATR/BRPN
  AutumnServices/      GAS ashwrite/ashread, OAuth, mailbox, Keychain
  AutumnApp/
    Shell/             AppShell, Left HUD, Right rail, Profile
    Admin/             DATA / ASH / MSG mailbox
    Modules/           MIST STAR SHARD SYS stubs
```
