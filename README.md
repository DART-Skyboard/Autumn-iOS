# Autumn iOS

Native SwiftUI port of [leatr.xyz](https://leatr.xyz). Not a WKWebView of the site.

Bundle id `com.dartmeadow.autumn` · Team `L7AHWS9Q6V` · **build 100 / 1.0.2**.

Linux CI here cannot `xcodebuild`. TestFlight is built by `.github/workflows/testflight.yml` on merge to `main`.

## Build 100 — DIAGNOSTIC: BRPN 3D scene disabled (bisection, not a fix)

Build 99 (LaunchDebug's `.synchronize()` removed) still hit the same
`0x8BADF00D scene-create watchdog` — but this crash log's signature was new and, so far,
the least specific: every single frame is inside SwiftUI/AttributeGraph internals
(`AG::LayoutDescriptor::Compare`, `compare_heap_objects`, recursing four levels deep) —
**zero application-code frames**. That means something is repeatedly asking SwiftUI to
deep-compare a large or structurally complex value, but the crash log has no way to say
which one — that needs a live profiler (Instruments' Time Profiler/SwiftUI template),
which isn't available without a Mac in this workflow.

Rather than guess a fourth time, this build bisects: `BRPNSceneView.body` is replaced
with a static placeholder and `sceneVM.setupScene()` is never called, disabling the
entire BRPN 3D scene — continuous 60fps SceneKit rendering, the 7x7x7 maze-orb state,
icosahedron shell geometry, orbital particles, tool-shape swarm. Everything else (chat,
HUD tools, admin console, theme system) is untouched. The original implementation is
still in the file as `disabledOriginalBody`, unused but intact, so reverting this is a
one-line change once we have an answer.

**This is not a fix.** If build 100 launches clean, we've isolated the hang to the BRPN
scene subsystem and can dig into exactly what there is expensive to diff. If it still
hangs, the cause is elsewhere and this rules out a large, plausible suspect.

## Build 99 — the diagnostic tool was the bug

Build 98's crash log (fully clean rebuild off TF89, `AskAutumnComposer` entirely
removed) hit the identical `0x8BADF00D scene-create watchdog` — and this time, with
thermal state "nominal" (best possible) and no composer subsystem left to blame, the
backtrace was completely unambiguous: `-[NSUserDefaults setObject:forKey:]` blocked on
`xpc_connection_send_message_with_reply_sync`, called *directly from inside a SwiftUI
body evaluation*.

That's `LaunchDebug.mark()` — the TF96 diagnostic tool added to find this exact class of
hang. `mark()` called `UserDefaults.synchronize()` on every invocation, and it was
invoked from the very top of five different views' `body` (`RootView`, `WelcomeView`,
`AppShellView`, `BRPNSceneView`, `HUDToolsPanel`). `.synchronize()` forces a *synchronous*
wait for a reply from another process (`cfprefsd`) — completely different from a plain
`.set()`, which is just an in-memory cache update that iOS flushes to disk on its own
schedule. SwiftUI can (and does, especially during initial layout settling) call `body`
many times in quick succession; each of those calls paying a blocking cross-process IPC
round-trip is more than sufficient, on its own, to trip a 10-20 second watchdog. The tool
built to find the hang had itself become indistinguishable from one.

Fixed: removed `.synchronize()` from `LaunchDebug` entirely, and removed the `mark()`
calls from all five view bodies (kept only the two one-time marks in `AutumnApp.init()`,
which run once per launch, not per render — no hazard there). This doesn't retroactively
prove what builds 90-97's *original* crash was — that investigation (the
`@Published`-during-render / deferred-notification fix from build 97) stands on its own
merits from a real, independently-reasoned crash log — but it does mean build 99 is the
first build since 91 that isn't fighting its own instrumentation.

## Build 98 — clean rebuild off TF89, minus the AskAutumnComposer subsystem

TF90 through TF97 all built forward from TF89 in sequence, and TF90's new UIKit
`AskAutumnComposer` (a custom `UITextView` wrapper written to work around a SwiftUI
keyboard-focus bug) turned into a recurring source of exactly the bugs it was meant to
avoid — a `touchesBegan` override that raced UITextView's own focus handling, an
`intrinsicContentSize` recursion, and it sat directly inside the always-rendered input
bar, which is the same view tree implicated in the `0x8BADF00D` scene-create watchdog
crash that persisted from TF91 through TF97 despite several targeted fixes (BGTaskScheduler
identifier mismatch, deferred NotificationCenter posts, and others — see git history on
`main` for that full investigation, kept there rather than replayed here).

Rather than carrying that subsystem forward again, this build starts fresh from TF89
(confirmed stable, Sign in with Apple included) and re-adds only what TF90+ was actually
for, built directly on TF89's original `TextField` + `@FocusState` input bar instead:

- **Administration Console** — DATA/ASH/MESSAGES tabs, roles, mailbox, ASH grammar
  training; gated purely on iOS GitHub sign-in identity (`dartsolarpunk`), no web-circuit
  dependency. (`Admin/`, `AdminCircuit.swift`, `AdminDataService.swift`)
- **TTS voice quality** — premium/enhanced neural voice preference (Zoe → Nicky →
  Samantha → Allison) with saved rate/pitch.
- **LaTeX Canvas** — dynamic resize between portrait/landscape (`GeometryReader`-driven,
  matches the other studios).
- **ARIEL theme legibility** — HUD Tools submenu labels lightened for ARIEL only so they
  read against the frosted desert-video background.
- **Landscape input bar** — `compact` mode tightens/left-groups the leading buttons so
  the text field gets the reclaimed width; portrait unaffected.
- **BGTaskScheduler identifiers** — matched to `Info.plist`'s
  `BGTaskSchedulerPermittedIdentifiers` (a real, independently-confirmed mismatch bug,
  unrelated to whichever exact cause turns out to be behind the watchdog crash).
- **Deferred NotificationCenter posts** for the two spots that could otherwise cascade a
  `@Published` mutation into a still-in-progress SwiftUI render pass — the strongest
  concrete lead from two real device crash logs, kept here as cheap insurance regardless
  of whether the composer removal alone resolves it.
- **`.scrollDismissesKeyboard(.immediately)`** instead of `.interactively`, applied to
  TF89's original TextField-based chat scroll view — `.interactively` is a known source of
  "keyboard won't reopen" stuck states independent of which text-input implementation
  sits underneath it.
- **`LaunchDebug`** — the persistent, UserDefaults-backed launch tracer added in TF96,
  still here as a safety net. Shows the previous session's trace as a small overlay at
  the top of the screen on next launch; harmless if nothing crashed.
- **dSYM upload** in the TestFlight workflow (CI-only) — so if anything still crashes,
  the next report can finally be symbolicated to an exact line.

Everything from TF90's `AskAutumnComposer` era — the custom UIKit composer, its keyboard
accessory bar — is gone. TF89's original TextField + `.toolbar(.keyboard)` hide-keyboard
button is what ships instead; it's the version that was actually confirmed stable, if not
perfect (see `LaunchDebug`/README history on `main` for the flakiness that motivated the
composer rewrite in the first place — trading a known, non-fatal quirk for eliminating a
whole crash-adjacent subsystem is the point of this rebuild).

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
