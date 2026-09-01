# Autumn iOS

Native SwiftUI port of [leatr.xyz](https://leatr.xyz). Not a WKWebView of the site.

Bundle id `com.dartmeadow.autumn` · Team `L7AHWS9Q6V` · **build 57 / 1.0.2**.

Linux CI here cannot `xcodebuild`. TestFlight is built by `.github/workflows/testflight.yml` on merge to `main`.


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

- **Portrait:** top bar (theme / scrim / wordmark / profile) → BRPN stage (left GEO/MAR/AERO+ADMIN, right MIST/STAR/SHARD/SYS) → chat.
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
| Ash Canvas | `#ash-canvas-drawer` | Existing `AshCanvasView` on the BRPN stage |
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
