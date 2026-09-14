# Autumn iOS

Native SwiftUI port of [leatr.xyz](https://leatr.xyz). Not a WKWebView of the site.

Bundle id `com.dartmeadow.autumn` · Team `L7AHWS9Q6V` · **build 94 / 1.0.2**.

Linux CI here cannot `xcodebuild`. TestFlight is built by `.github/workflows/testflight.yml` on merge to `main`.

## Build 94

TF89 was the last build Justin tested as stable; TF90 added the iOS admin console +
UIKit `AskAutumnComposer` keyboard rework, TF91/92 chased a black-screen + keyboard bug
introduced by that rework. This build finishes that fix (root cause found, not just
patched around) and does the four follow-on items from testing TF89/91/92 on-device.

1. **Keyboard (root cause, not just TF92's symptom patch):** `AskAutumnTextView` had a
   `touchesBegan` override manually calling `becomeFirstResponder()`. That raced UITextView's
   own internal tap-to-edit gesture recognizer — the first tap after mount won the race, but
   any resign after that (send, the accessory hide button, or an interactive scroll dismiss)
   left the manual call silently losing the race on the next tap, reproducing exactly as
   reported: works once, then dead until the view is torn down and rebuilt by rotating.
   Removed the override — UITextView already becomes first responder on tap natively.
   Also switched `ChatView`'s `.scrollDismissesKeyboard` from `.interactively` to
   `.immediately`; the interactive drag-to-dismiss can leave its own tracking state stuck
   for the same class of reason. TF92's zero-keyboard-frame and composer-recursion fixes
   are kept — they were correct fixes for real bugs, just not the one causing this symptom.
2. **LaTeX Canvas dynamic resize:** was a fixed `.frame(maxWidth: 620)` card with no
   orientation awareness, unlike the other studios. Alongside Math Solver in landscape it
   squeezed the "LATEX CANVAS" title into a column too narrow to lay out, wrapping it
   letter-by-letter. Now sized off `GeometryReader` (matches the `StudioHostView` pattern)
   with a squeeze-resistant title.
3. **Landscape prompt bar:** `InputBar` takes a `compact` flag (set by `AppShellView` for
   its landscape pane only). Mic/attach/fx shrink slightly and sit tighter together on the
   left, composer gets the reclaimed width, send stays pinned right. Same icons, same
   shapes — just tighter. Portrait is untouched and unaffected by rotation back.
4. **ARIEL theme HUD Tools submenu legibility:** submenu row labels used the raw theme
   accent (`#c4a36a`, sand) which nearly matches the ARIEL desert video behind the frosted
   panel. Added `AutumnTheme.overlayLabelAccent` — lightened for ARIEL only (`#e9dcc6`),
   identical to `.accent` for every other theme — and pointed `HUDToolsPanel` row labels at
   it. The HUD Tools tab button itself (cyan) was already fine and is untouched.
5. **Admin console:** already substantially built in TF90 (DATA/ASH/MESSAGES tabs, roles,
   mailbox, ASH grammar training) and already gated purely off iOS GitHub sign-in identity
   (`dartsolarpunk`) with no web-circuit dependency — reviewed for stubs, found none.
6. **TTS voice quality:** TF91's `Self.qualityRank` static-call fix confirmed correct and
   unchanged — `bestVoice()` prefers premium/enhanced neural voices (Zoe → Nicky → Samantha
   → Allison) and falls back gracefully.

## Build 59

1. **Keyboard:** Ask Autumn lifts the whole bottom (mic / field / send) onto the system keyboard. Removed `AppShellView.ignoresSafeArea(.keyboard)`. Swipe down on the transcript dismisses; keyboard toolbar chevron stays.
2. **Ash Canvas** when OPEN is unclipped: tools, SAVE/SEND, 200px canvas, G/M/A sockets, APPLY/LINK/DEL/RESET. `acConnectSocket` + `acApplyToNetwork` (TOOL_WEIGHTS, GEO/MAR/AERO influence, BRPN pulse, APPLIED status, journal, close drawer).
3. **Side HUD frost** on GEO/MAR/AERO/RADAR/ALC/TOOLS and MIST/STAR/SHARD/SYS drawers — ultraThinMaterial glass, not opaque slabs.
4. **Mantis Radar** explicit **2D / 3D** toggle. 2D = MapKit + live ADS-B. 3D = SceneKit globe (rotating earth, ADS-B, CelesTrak TLE). RADAR opens this studio, not MIST.
5. **Afterlife Crossing** full web port: ALC + NAMO tabs, harpmaker quote, age calculator, NYC namography, export to Ash.
6. **Profile** is a frosted card only — no full-screen dim. Tint from GitHub avatar.
7. **Header logo** circular (`AutumnLogoMark`). Maze 57 math unchanged.

## Build 58


1. **Ash Canvas drawer** matches web: scene → EmoHUD → `#ash-canvas-trigger` (always visible, padding 3×12, ~0.45rem) → drawer expands DOWN over chat (max-height 0→520, cubic-bezier). Trigger is the collapse control. Scene stays put. Themed chrome + `#a78bfa` ac accents. No overlay covering the 3D stage.
2. **GitHub avatar** in the header chip, profile sheet, and account list. Single `GET /user` decodes `login` + `avatar_url` + `name`. Refresh on `applyOAuthToken`, `restoreSession`, and `switchGitHubAccount`. Persist URL in Keychain. `?s=128`. User-Agent on API calls. Letter fallback only if unsigned / fetch failed. No PAT.
3. **Mantis Radar** native 2D MapKit + 3D globe (not WKWebView). Live ADS-B from adsb.lol / adsb.fi / OpenSky at device lat/lon. CelesTrak TLE on the globe. Dark tiles (CARTO when keyed, else ESRI World Dark Gray).
4. **Theme videos** mute + autoplay + loop forever (`AVPlayerLooper` + end-of-item seek). New clip loops on theme change. VOID overlay hides; CLEAR still loops.
5. **Header logo** is circular (`clipShape(Circle())`) in portrait topBar and landscape drawer.

## Build 57


Native BRPN scene matches live leatr.xyz Three.js — same variables, math, logic.

1. **Shells** `IcosahedronGeometry(r, 1)` GEO/MAR/AERO — `shellColors=[0x00ffcc,0x0088ff,0xff4466]` `shellRadii=[1.9,1.4,0.9]` opacity `0.18+i*0.08`. Core `SphereGeometry(0.18,12,12)`. Camera FOV 50 at `(0,1.5,5)`.
2. **Core orb maze** is `mazeOrbState` 7×7×7, `orbGenMaze` recursive backtracker `grid[z][y][x]` cell `{top,bottom,left,right,front,back,visited}`, `orbSolveMaze` BFS (0,0,0)→(w-1,h-1,d-1), `buildOrbMazeGeometry` `u=0.065` LineSegments of left/bottom/back quad outlines only, path `SphereGeometry(u*0.22,4,4)`, start `0x00ffcc` / end `0xff4466` `u*0.35`.
3. **MIST 2D** `generateMaze`/`solveMaze` 1:1 from `js/mist-module.js` (n/s/e/w, carve(0,0), LOS reject, `sol.length<(w+h)/1.4`).
4. **SIGMA SOLVE** on the Ash/MIST studio cube is `LEMAC_ENGINE_ASH.solveCubic` degree-map sigma prune — not generic BFS. BRPN cube button still reveals the orb BFS path (`solveOrbMazeCube`).
5. **CLEAR overlay:** SCNView is transparent (`alpha` renderer). No extra `Color(0.01,0.02,0.05)` wash. Only `#vid-scrim` sits between theme video and chrome.
6. **Node cap** HUD 10 / 50 / 100 / 300 / 1.2K / 2M (`_mantisNodeMax`). Remote sessions are 0.28× icosahedron clusters. Aircraft tetrahedrons / satellite octahedrons.
7. Admin circuit unchanged. Core Cognition True. Arc Lake remains a HUD module.

## Build 55

1. **Theme videos** bundled under `Sources/AutumnApp/Resources/Themes/` (loop muted AVPlayer, aspect-fill).
2. **Z-order** matches web: video/solid → `#vid-scrim` (hit-testing off) → chrome / scene / chat / sheets.
3. **Portrait / landscape** match web. Portrait = scene top, chat bottom. Landscape = top bar becomes a left drawer; scene + chat stay on the right, tall. GEO/MAR/AERO exist only as the left stack (not also a top row).
4. **Right rail** MIST / STAR / SHARD / SYS are live overlays, not stub sheets.
5. **HUD TOOLS** wires Mantis NAV, Radar, Ash Canvas (on the BRPN scene), ArcLake, Arc Edge, CALC (MathOOO), Emo Map, Arc Forge, World Studio, NATE, Movement, Help.
6. **3D** buoyancy orbs, cubic maze, plasma splines between the local node and session peers. Presence via GAS + public `presence.json`.
7. **Admin tab** `MESSAGES` (was MSG). Compose SYS via GAS ashwrite. No PAT in the client.

## Theme videos

| Theme | File | Notes |
|---|---|---|
| VOID | none | solid / gradient only |
| DAY | `autumnanimation.mp4` | |
| NIGHT | `autumnnight.mp4` | |
| STEALTH | `dartalley.mp4` | local copy of the web remote |
| DEPARTURE | `autumndeparture.mp4` | |
| ASH TREE | `ashtree.mp4` | |
| ARIEL | `ariel.mp4` | |
| AUTO | day or night | from system appearance |

VOID **overlay** hides video and shows the per-theme dark gradient (web `VOID_GRAD`). CLEAR: no wash, no blur, video on. FROST / STEAM / HAZE / DUSK / DEEP: theme-tinted wash + blur on the video only.

## Layout

- **Portrait:** top bar → BRPN stage (left GEO/MAR/AERO+ADMIN, right MIST/STAR/SHARD/SYS) → EmoHUD → Ash Canvas trigger → chat (drawer overlays chat when open).
- **Landscape (`width > height`):** left drawer is the old top bar; scene + chat stack on the right, tall. Same idea as `css/desktop-layout.js` (`header` → nav column).

## Modules (honest)

| Surface | Web | Native |
|---|---|---|
| MIST | `js/mist-module.js` | Overlay + maze solve on the orb + GAS presence |
| Ash Star | `js/ash-star-archive.js` | 3D spawn on the orb + archive drawer (never a chat card) |
| Ash Shard | `js/ash-shard-module.js` | Textile + GitHub following (OAuth) + spline send |
| SYS | `system-broadcast.json` | Public read; dartsolarpunk compose via GAS |
| Mantis NAV | `mn.html` | Existing `MantisNavigationView` from HUD |
| Mantis Radar | `mr.html` | MapKit + `MantisViewModel` ADS-B/orbit counts |
| Ash Canvas | `#ash-canvas-drawer` | Trigger bar under EmoHUD; drawer expands down over chat |
| ArcLake | `js/arclake_studio.js` | First-pass studio (atom + CFD sliders). **Not** a standalone App Store app. |
| Arc Forge | `arc-forge.html` | Native first-pass gate sandbox |
| World Studio | `worldstudio.html` | Native first-pass viewport HUD |
| NATE | `nate.html` | Frequency HUD + TTS |
| Movement | `movement-conjecture.html` | DOC / Arc Edge reading room |
| Help / Privacy | `autumn-help.html` / `autumn-privacy.html` | Native scroll views |
| Grammar / TTS | `js/autumn-grammar-engine.js` `js/autumn-tts.js` | `GrammarEngine` + `AutumnTTS` |
| Desktop layout | `js/desktop-layout.js` | SwiftUI rotation, not a WKWebView |

## Auth / GAS

Guest-first. GitHub via device flow + `ASWebAuthenticationSession`. OAuth in Keychain only. **No PAT.** Journal, mist events, shards, SYS compose, and presence ping go through `AutumnGASClient` (`AutumnConfig.gasURL`).

## LEATR

- Core Cognition always True (frozen).
- Reflex never loops.
- Never mix users (per-owner memory + journal uid).
