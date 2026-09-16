# Autumn iOS

Native SwiftUI port of [leatr.xyz](https://leatr.xyz). Not a WKWebView of the site.

Bundle id `com.dartmeadow.autumn` · Team `L7AHWS9Q6V` · **build 114 / 1.0.2**.

Linux CI here cannot `xcodebuild`. TestFlight is built by `.github/workflows/testflight.yml` on merge to `main`.

## Build 114 — device-flow auth survives the app being killed during the Safari round-trip

Confirmed by the reported symptom: code generated fine (build 113's fix worked),
Safari showed "Congratulations, you're all set!", but back in the app it was still
"waiting for a connection" and eventually reset to the very first "Start GitHub
Authorization" screen — as if nothing had happened. A plain in-memory polling loop
(`Task.sleep` in a cycle) does not survive the app being fully **terminated** by iOS
while backgrounded — not just suspended, actually killed, which does happen under
memory pressure or after enough time away during the Safari hand-off. That wipes
`deviceFlowCode` and the poll task entirely; on relaunch the sheet saw a nil code and
started an entirely new device flow, silently orphaning the one already approved in
Safari — a real bug, not just something to "simplify."

Now persists the pending device code (UserDefaults) the moment it's generated, and
clears it on success, cancel, or its own 10-minute timeout. On relaunch — from
`restoreSession()` or whenever the connect sheet appears — if a still-valid pending
code exists (younger than GitHub's own ~15 minute validity window), it resumes
polling that exact code instead of starting over. Reinstalling worked because it
reset the account to a clean state before the same underlying race could recur — not
a coincidence, the actual bug just wasn't there yet to trip.

## Build 113 — real GitHub reconnect flow + found the missing MESSAGES

**Reconnect GitHub jumped straight to a code-entry page with no code shown:** both
Ash Shard's and Admin's "Reconnect GitHub" buttons called `startGitHubAuth()` with its
default `openVerification: true`, which opens Safari immediately — skipping the step
that actually requests and displays the device code. `GitHubDeviceFlowSheet` (already
used correctly by Profile's own connect flow) is what should have been shown instead:
it displays the code prominently, **auto-copies it to the clipboard the instant it's
generated**, and deep-links to `github.com/login/device?user_code=...` — GitHub's own
page pre-fills the code from that URL parameter, so the only thing left to do is tap
Continue. That's exactly the copy-then-continue flow described — it already existed,
it just wasn't wired up on these two reconnect buttons. Fixed both to present the same
sheet instead of skipping straight to Safari.

**MESSAGES showing "0 entries" despite real messages existing:** found by comparing
directly against the web app's own admin console source. The ANALYSIS folder has been
renamed more than once over this app's history, and the web app's `_admFbLegacyPaths`
already accounts for that — it tries `feedback/analysis.json`, then
`feedback/archive.json`, `feedback/inbox-archive.json`, and
`feedback/inbox_archive.json`, and uses whichever one actually has entries. iOS only
ever checked the current filename, so any account whose existing analysis messages are
still stored under one of the older names saw a genuinely empty result — the data was
never missing, just unreachable at the one path iOS knew about. Ported the same
fallback logic; INBOX/READ/TRASH are unaffected since the web app doesn't apply this
fallback to those either — there's only ever been one settled name for those.

## Build 112 — CI compile fix: builds 110 and 111 never actually reached TestFlight

Both builds 110 (MusicKit) and 111 (Admin/Ash Shard) **failed CI** — a genuine miss on
my part, they were never caught before being reported as shipped. Root cause: my own
`MusicItem` struct in `AutumnMusic.swift` collides by name with a type the real
`MusicKit` framework itself defines — `'MusicItem' is ambiguous for type lookup`.
Since 111 built forward from 110's already-broken source, it hit the identical error
and also never reached TestFlight; none of build 111's own admin/Ash Shard changes
were at fault. Fixed by fully qualifying the two usages as `AutumnServices.MusicItem`
in `MusicPanel.swift` — no logic changes, everything from 110 and 111 (MusicKit HUD
tool, admin tab consolidation + draggable panel, Ash Shard reconnect-GitHub flow,
contacts list height) is included here and should actually build this time.

## Build 111 — Admin polish + the real Ash Shard bug (invalid token, not a UI bug)

**Profile:** removed the redundant "OPEN ADMIN DRAWER" button — the left HUD ADMIN tab
already does this whenever admin is enabled, so it was just clutter.

**Admin panel:** consolidated from 4 tabs to 3 (DATA / ASH / MESSAGES) — dropped the
inbox-only MSG tab since MESSAGES (the full mailbox: folders, select-all, move,
delete) already covers everything it did and more. Also converted the panel from a
fixed slide-in-from-edge drawer to a floating, translucent (`.ultraThinMaterial`),
draggable panel (drag by the title bar) — matching the other HUD overlay panels
instead of a one-off drawer style. The mailbox's move/delete logic itself was already
correct — moving an entry already removes it from the source folder and writes it to
the destination — but the empty-state view was showing a misleading "NO ENTRIES" even
when a load had genuinely failed, with the real error only visible in a small status
line at the bottom; fixed to surface the actual error with a Retry action.

**Ash Shard "COULDN'T LOAD: Bad credentials"**: this is GitHub's own literal 401
response — confirmed by reading `GitHubClient`'s error handling, which surfaces the
API's real `message` field verbatim. This means the stored OAuth token for whichever
account is active has actually gone invalid (expired or been revoked on GitHub's
side) — not a timing bug my last two builds' retry logic could ever fix, since
retrying a genuinely bad token just fails the same way every time. Both Ash Shard and
the Admin mailbox now detect this specific error and offer a "Reconnect GitHub"
action instead of a Retry that was never going to succeed.

**Contacts list height:** increased its share of the panel (`contactsFloor` 260→340,
the 3D textile canvas shrinks to compensate) so more contacts are visible per screen
and there's less scrolling needed to reach the end of the list.

## Build 110 — MusicKit: play Apple Music inside Autumn

**Checked App Store Connect first, as asked.** The entitlement was NOT actually set
up — confirmed directly via the API (`GET /bundleIds/{id}/bundleIdCapabilities`)
that only `IN_APP_PURCHASE`, `PUSH_NOTIFICATIONS`, `APPLE_ID_AUTH`, and `ICLOUD` were
enabled; no music-related capability. Turns out that's fine, though: native MusicKit
(`import MusicKit`, iOS 15+ — what `AutumnMusic.swift` already used) doesn't need an
App ID capability at all — that requirement only applies to *MusicKit JS* tokens for
web, a completely different feature. All native MusicKit actually needs is the
`NSAppleMusicUsageDescription` Info.plist key, which actually was missing (added to
both `Info.plist` and `project.yml`'s inline properties, which build the actual
generated plist). No ASC-side capability change was needed after all.

**New MUSIC HUD tool**, alongside CALC/ARC EDGE/etc. in the Tools panel — built on
top of the `AutumnMusic` actor that was already there but completely unwired (no
view referenced it anywhere): auth request flow (with a clear denied-state fallback
to Settings), search across songs/albums/artists, tap a song to play, a now-playing
bar with pause/resume. Albums/artists are browse-only for now — playing a full
album needs queueing its track list, which is a reasonable next step, not required
for a first working version.

Not done: background audio (needs `UIBackgroundModes: audio`, so playback would stop
when the app backgrounds) — a deliberate scope cut for a first pass, not an oversight.

## Build 109 — Admin fully independent of the web app (by request, not a bug fix)

Build 108 correctly identified that the admin drawer required an active leatr.xyz
browser session heartbeating `admin/circuit.json` — that was working as originally
designed, but on confirming with Justin, that was never actually the intent: the
goal is sign in on any device, get full admin access right there, with the web app
doing its own thing independently. Not tied together.

Removed the circuit/heartbeat requirement from `AdminCircuitGate.allows()` — the
only gate now is GitHub connected as `dartsolarpunk` + the Enable Admin toggle.
Every existing call site (`LeftHUDView`'s ADMIN tab, `AppShellView`'s drawer
presentation, `AdminDataConsole`/`SYSOverlay`'s write guards) reads through this
one function, so simplifying it there was enough — no per-call-site changes
needed. Updated Profile's admin section text and the ADMIN tab's help text to
stop describing a web-tab requirement that no longer exists.

## Build 108 — Ash Shard contacts reload fix; admin tab explained (not a bug)

**Ash Shard contacts still empty even for an account that does follow people
(`dartsolarpunk`):** real bug this time, not an empty-following false alarm. Two
likely causes, both fixed: (1) `.task` only fires once per view identity, so
switching GitHub accounts while Ash Shard was already open, or right before
opening it, left contacts stuck on stale/no data — now reloads via
`.onChange(of: authVM.githubUsername)`. (2) `switchGitHubAccount()` swaps the
`GitHubClient` token in a separately-launched `Task`; if Ash Shard's own load ran
before that finished, `fetchFollowing()` could silently return empty against a
stale/missing token — added one short-delay retry when the first attempt comes
back empty. Also surfaced a dedicated error state with a Retry button, instead of
errors only ever reaching a shared status line that the very next unrelated action
(e.g. tapping CYCLE) would silently overwrite.

**Admin tab not appearing despite "DISABLE ADMIN" showing (i.e. admin enabled):**
working as designed, confirmed by reading `AdminCircuitGate.allows()` — the iOS
admin drawer requires ALL of: GitHub connected as `dartsolarpunk`, the Enable Admin
toggle on, AND `admin/circuit.json` in `leatr-ash` reporting `live:true` with a
timestamp from the last ~90 seconds. That last part means an active leatr.xyz
admin-tab session heartbeating in a browser at the same time — Profile's own
"Admin waits for web circuit · CIRCUIT OPEN" text already describes this
accurately, it's just easy to miss that a browser tab is genuinely required
alongside the app, not just the toggle.

## Build 107 — username claim was always "taken", Profile scroll, GitHub/Apple identity priority

**Username claim always failing:** confirmed by reading the web app's own `ashread`
response contract (`_admUsable`/`_admIsNotFound`) — a *missing* file comes back from
GAS as a **non-empty dict with an `error` key**, never as `nil`. My check treated any
non-empty dict as "taken," so literally every name — including ones nobody could have
possibly claimed — read as unavailable. Fixed to match the real contract: only a
present `payload` or non-empty `content` means something's actually there; an
`error`-only response (or `nil`) means available.

**Profile unreachable below a certain point:** the card had no scroll and no height
cap — once the USERNAME section was added, total content height exceeded the screen
with nothing to reach it (Admin toggle included). Everything below the header now
scrolls, capped to a sane fraction of screen height.

**"User" showing despite an active GitHub account:** found two spots — Apple Sign In's
completion handler, and `restoreSession()`'s Apple credential-state check — that
unconditionally overwrote `username` with the saved Apple display name (which can
legitimately be the bare "User" fallback) regardless of whether GitHub was already
connected and active. Since Profile's header, Apple ID row, and GitHub row all read
the same `username`, this made every one of them show "User" once Apple's restore
logic ran after GitHub's. GitHub, once connected, now takes priority for display.

**Admin tab not visible:** working as designed, not a bug — Admin access is gated to
one specific GitHub username (matches web), and the account that was actively
signed-in (`radicaldeepscale`) isn't it. Switching the active account back to the
authorized one in Profile → ACCOUNTS restores it; the fix above should also make it
clearer which account is actually active, since the display name will stop reading
"User" for both identity rows.

## Build 106 — Ash Shard: searchable contacts + scroll-to-bottom fix

`ShardOverlay`'s GitHub-following contact picker had two issues: no way to filter a
long following list (matches the web app's contact search), and the last row or two
could feel unreachable — the list technically scrolled, but the final item sat flush
against the ScrollView's own bottom edge with no clearance, reading as cut off.

Added a search field (filters by login, case-insensitive) above the list, and a small
bottom content padding inside the ScrollView so the last row actually clears the
edge — a content change, not a frame change, so it doesn't affect the list's overall
height budget.

Also this session (web app, same session as build 105 — see the `Autumn` repo, not
this one): ported the LIVE FEED toggle (hide/show remote users' presence in the 3D
scene) to the web app, which never had one despite iOS already having it; restyled
the header's FROST/theme pills from a dark fill to the lighter frosted look iOS uses.

Not done in this build (deferred — genuinely separate, larger features): full iOS
Admin Console parity with the web's "USER DATA SHARING" category filter/table, which
depends on a per-user privacy-preferences feature (`data-prefs.json` in each user's
own vault repo) that doesn't exist on iOS at all yet — that's new feature work, not
a resize/parity fix like the rest of this build.

## Build 105 — custom username system + Apple ID email fallback

**Apple ID showing "User":** `applyAppleAuthorization` only ever captured
`fullName`, and Apple only sends that (and `email`) on the account's *very first*
authorization with this app — every subsequent sign-in legitimately returns nil for
both, which isn't a bug on its own, but the fallback chain only ever led to a
hardcoded `"User"`. Now also captures and persists `email` on that first
authorization, and falls back through: this sign-in's name → previously saved name
→ this/previously saved email → `"User"` as the true last resort.

**Custom profile username.** GitHub already gives every connected user a globally
unique handle; Apple-only sign-in doesn't have an equivalent, hence "User" showing
identically for everyone. Added a username system:
- New "USERNAME" section in Profile — set, change, or turn off a custom handle
  (3-20 chars, letters/numbers/underscore).
- Uniqueness enforced against `ashtree/users/<name>/profile.json` in the `leatr-ash`
  repo via the existing no-token `ashread`/`ashwrite` GAS proxy — **this is the same
  directory `AdminDataService.loadUsers()` already reads as the Admin Console's user
  roster**, not a new registry. Claiming a name here is what populates it, so
  registered usernames now show up in Admin Console data automatically.
- Once claimed, the name is what displays for the Apple ID row, the GitHub row, and
  the main profile header — a pure display-layer override; the real
  `githubUsername`/`appleUserId` used for auth and backend calls are untouched.
  Persisted locally (Keychain), so it's restored exactly as left on next launch.

Not done in this build: `AdminUserRow`/Admin Console's user list still shows just
the directory name, not the richer profile.json fields (claimed date, linked GitHub/
email) written alongside it — parsing those into the admin UI is a reasonable
follow-up, not required for the registry/uniqueness/display behavior itself to work.

## Build 104 — input bar height fix + SKYBOARD theme

**Input bar too tall:** after bringing the UIKit composer back in build 103, its
height was left to whatever SwiftUI's generic `UIViewRepresentable` sizing guessed
within the `.frame(minHeight: 40, maxHeight: 96)` range — in practice it settled much
closer to the 96pt max than the ~40pt a single line actually needs, making the whole
bar visibly bloated (confirmed in a screenshot — lots of empty space above/below the
buttons). Fixed properly: the composer now measures its own real content height via
`sizeThatFits` and reports it back through a binding, so `InputBar` applies an exact
`.frame(height:)` instead of a guessed range — short by default, grows only when text
actually wraps to more lines. Also trimmed the bar's outer vertical padding slightly.

**New theme: SKYBOARD.** Added from a supplied video (a figure on a hoverboard amid
holographic HUD panels in the desert — matches the DART-Skyboard branding well).
Re-encoded to H.264 (4.9MB, in line with the other theme videos) and added as a full
`AutumnTheme` case: accent color, base/surface, wash tint, and void-gradient fallback,
using an icy HUD-cyan (`#5fd4ff`) to distinguish it from ARIEL's desert-gold. Same
video and theme also added to the web app (`leatr.xyz`) in the same session.

## Build 103 — UIKit composer back (fixed from the start), Math Solver resize

**Keyboard:** confirmed on-device that build 102's `NavigationStack` wrap — the
documented fix for `TextField` + `@FocusState` + keyboard toolbar without one —
wasn't enough on its own, most likely because of how this app's specific iOS 27 beta
target behaves rather than something a pure-SwiftUI workaround can route around.

Reintroduced `AskAutumnComposer` (the UIKit `UITextView`-backed composer from TF90),
which takes first-responder control directly instead of going through
`@FocusState`/`.toolbar(.keyboard)` at all — bypassing that whole SwiftUI layer
rather than trying to work around it again. Brought back with both of its original
bugs fixed **from the start** this time, not re-broken and re-fixed:
- No `touchesBegan` override (that raced UITextView's own native tap-to-edit gesture
  recognizer — the actual cause of "works once, dead after")
- `intrinsicContentSize` returns a fixed value instead of calling `sizeThatFits`
  (that recursion was the TF91 black-screen bug)

Separately confirmed via the build 91-99 crash-log investigation: neither of those
bugs, nor this composer at all, had anything to do with the `0x8BADF00D` scene-create
watchdog crash — that was `LaunchDebug`'s `UserDefaults.synchronize()` call and a
synchronous `NotificationCenter` post, both already fixed and unrelated to this file.
Safe to bring back on its own merits.

**Math Solver overlay:** only `LatexCanvasOverlay` got the GeometryReader-based
resize fix in build 101/102 — `MathSolverOverlay` was never touched and had the
exact same fixed-`maxWidth`-only, no-height-awareness bug. Same fix applied: sized
off `GeometryReader` on both axes, body scrolls internally below the header when it
doesn't fit either orientation.

## Build 102 — real keyboard fix + landscape overflow fixes

Build 101's `.scrollDismissesKeyboard(.immediately)` change didn't fix the keyboard —
confirmed still reproducing on pure TF89 source (no `AskAutumnComposer` involved at all),
so the cause was never that composer's `touchesBegan` override; it's more fundamental.

**Root cause found:** `TextField` + `@FocusState` + `ToolbarItemGroup(placement:
.keyboard)` **without a `NavigationStack`** anywhere in the view hierarchy is a
documented SwiftUI reliability issue — the keyboard toolbar/focus machinery can
silently stop calling `becomeFirstResponder` after the first dismiss. That's exactly
the reported symptom: focuses and shows the keyboard once, then stops responding until
the view is torn down and rebuilt (e.g. by rotating, which swaps `portraitChrome` /
`landscapeChrome` and forces a fresh `InputBar`). `RootView` never had a
`NavigationStack` anywhere. Wrapped it in one (nav bar hidden, no visual change) —
this gives SwiftUI's focus/toolbar code the context it expects.

**LaTeX Canvas landscape overflow:** build 101's width fix didn't address height — the
card's content (title field + glyph canvas + source editor + buttons, each with fixed
minimum heights) could still exceed the available landscape height, running the bottom
of the card off-screen with no way to reach it. Now sizes height off `GeometryReader`
too, and the body below the header scrolls internally when it doesn't fit.

**Ash Canvas landscape overflow:** in `landscapeChrome`'s middle column, both the 3D
scene and `AshCanvasView` asked for `maxHeight: .infinity` in the same `VStack` with
nothing capping either — when Ash Canvas opened it overflowed past the bottom of the
screen, and since nothing bounded the column's actual height, the whole `HStack` row
grew taller than the real geometry too, which is what was also pushing the right
pane's chat input/footer off-screen. Ash Canvas now gets an explicit bounded height
(matching portrait's already-correct `belowSceneStack` pattern) and the scene shrinks
to share the remaining space instead of both competing for the same infinite height;
added explicit height clamps on the row and both columns as a backstop.

## Build 101 — minimal reset: pure TF89 + only the keyboard and LaTeX fixes

Builds 90 through 100 chased a `0x8BADF00D scene-create watchdog` crash through several
real, confirmed bugs (an `AskAutumnComposer` keyboard race, a `LaunchDebug.synchronize()`
hang, a `@Published`-during-render notification cascade) without ever reaching a clean
launch — each fix was individually justified by real crash-log evidence, but something
kept surviving all of them, and the last crash log (build 99) showed a signature with no
application-code frames at all, past the point where crash logs alone can localize it
without a live profiler.

Rather than keep layering fixes on an increasingly hard-to-verify base, this build goes
back to **exactly TF89's source** — the last version Justin confirmed stable end-to-end,
including Sign in with Apple — and changes only two things, both isolated, low-risk, and
requested directly:

1. **Keyboard:** `ChatView`'s `.scrollDismissesKeyboard` changed from `.interactively` to
   `.immediately`. `.interactively` is a known source of the keyboard getting stuck and
   refusing to reopen until the view is torn down and rebuilt (e.g. by rotating) —
   matches the original reported symptom on this exact TextField/`.focused()` setup.
   Nothing else about the input bar changed.
2. **LaTeX Canvas resize:** `LatexCanvasOverlay` was a fixed `.frame(maxWidth: 620)` card
   with no orientation awareness, so in landscape the header squeezed "LATEX CANVAS" into
   a column too narrow to lay out normally. Now sized off `GeometryReader` (matching how
   the other HUD studios size themselves) with a squeeze-resistant title.

Everything else — admin console independence, TTS voice quality, the BGTaskScheduler
identifier fix, the notification-defer fix, `LaunchDebug`, dSYM capture, the Ariel theme
fix, landscape input-bar layout — is deliberately **not** in this build. Once this is
confirmed stable on-device, those go back in one at a time so any regression is
immediately attributable instead of stacking blind again.

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
