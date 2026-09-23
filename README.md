# Autumn iOS

Native SwiftUI port of [leatr.xyz](https://leatr.xyz). Not a WKWebView of the site.

Bundle id `com.dartmeadow.autumn` · Team `L7AHWS9Q6V` · **build 132 / 1.0.2**.

Linux CI here cannot `xcodebuild`. TestFlight is built by `.github/workflows/testflight.yml` on merge to `main`.

## Build 132 — the solid yellow screen: two compounding bugs, both fixed

With the relay live and returning up to 2000 real vessels, two bugs stacked into a
completely covered screen: **(1) no count cap at all** — aircraft already cap at
`.prefix(80)`, vessels had nothing, so up to 2000 individual boat nodes were being
created every sync. **(2) the per-node scale (0.014) was roughly 10x too large** —
satellites use an explicit radius of 0.018–0.026 in the same units as the globe's own
radius (1.0); a boat's longest raw dimension (~24 units) needed a scale near 0.0012 to
land in that same visual range, not 0.014. Thousands of oversized boats fully
overlapping is exactly a solid color fill.

**Found and fixed a third, related bug while in there:** existing vessels that
received a position update (not newly created) were having their scale *reset to
1.0* — full, completely un-scaled geometry — because the update path set scale as if
it were a multiplier on top of the creation scale, when the creation path was setting
an absolute value. Any vessel that had been alive for more than one sync cycle would
balloon back to full size. Fixed by using the same consistent absolute scale in both
the creation and update paths.

Capped vessel rendering to 250 (a bit above aircraft's 80, since a sparse ocean view
reads well with more markers than a sky view needs) and corrected the scale to
actually match how every other marker on this globe is sized.

## Build 131 — the maritime relay is live: real global vessel tracking, on for every user

The relay deployed successfully to `https://leatr-ash.onrender.com`. Verified directly
before wiring it in — a brief `429` right after first connecting (AISStream rate-
limiting the initial handshake) cleared itself via the relay's own backoff exactly as
designed; querying `/vessels` now returns `"status":"live"` with 1,067+ real tracked
vessels spanning multiple continents, real ship names and positions. This is genuine
live data, not a demo.

`AutumnConfig.maritimeRelayURL` now points at the real deployed relay instead of the
placeholder. No further setup needed on any device — every app user gets real-time
global vessel tracking in Mantis Radar's 3D Maritime tab with zero configuration,
finishing what build 130 set out to do.

## Build 130 — maritime tracking is now genuinely public: no user needs a key, matching the other radar modules

AISStream's own terms say direct client connections aren't permitted ("connect from
your own server and proxy only the information your clients need"), which meant a
shared personal key baked into every app instance would have violated their terms and
gotten rate-limited fast under real multi-user load. Fixed properly: added
`leatr-ash/services/ais-relay`, a small always-on relay server — holds the one
AISStream connection using the API key as a server-side environment variable (never
in the app, never in any client, never in a public repo in plain text), and re-serves
global vessel positions over a plain public REST endpoint that needs no key at all.

**iOS side:** `MaritimeFeed` no longer touches AISStream or asks for a personal key —
removed that Settings field entirely. It now just polls the relay's `/vessels`
endpoint every 5 seconds, the same way any other public radar data source works in
this app. Once the relay is actually deployed (see its README — needs a small
always-on host like Render/Fly.io's free tier, since neither GitHub nor Google Apps
Script can hold a persistent connection) and `AutumnConfig.maritimeRelayURL` is
updated to point at it, every single app user gets real global vessel tracking with
zero setup, exactly like the satellite and aircraft tabs already work.

**Not done yet, stated plainly:** the relay's code is written and pushed, but it
isn't running anywhere yet — that's a real deployment step (creating a free account
on a host, connecting the repo, setting one environment variable) that needs doing
once, by whoever holds the AISStream key. Until then, the Maritime tab will show "AIS
relay not deployed yet" instead of silently failing.

## Build 129 — found it: real aircraft data was leaking into the 3D Maritime view

Confirmed the exact bug behind "looks the same as air traffic tracking": in build
128's `updateUIView`, satellites were correctly hidden in maritime mode
(`showVessels ? [] : feed.satellites`) but aircraft were passed unconditionally —
`aircraft: feed.aircraft`, no gate at all. Real ADS-B aircraft positions were
rendering on the maritime globe the whole time, which is exactly why it looked like
the aviation tab — because part of it genuinely was. This also explains the dot
cluster near your own location in the earlier screenshot: not a calibration issue,
not ships on land, actual nearby aircraft rendering where they shouldn't have been.
Fixed: aircraft are now gated by `showVessels` exactly like satellites are.

Also removed the range slider for maritime specifically — it never actually filtered
vessel data (the AIS subscription was already a global bounding box from the start),
so showing it implied a limit that didn't exist. Maritime now shows only what it's
meant to: every tracked vessel, everywhere there's water, full stop.

Global coverage itself needs no further change — `MaritimeFeed`'s subscription
already requests the whole planet in one bounding box. This build fixes what was
incorrectly showing alongside it, not the vessel data itself, which still needs a
real AISStream API key in Settings to actually populate.

## Build 128 — Mantis Radar's third tab: real-time 3D maritime vessel tracking

New "3D MARITIME" tab alongside 2D Aerial and 3D Orbital, same globe framework
(SceneKit + lat/lon→3D math shared with satellites/aircraft) rather than a separate
scene. Real data: `MaritimeFeed` connects to AISStream.io's free global AIS WebSocket
(genuine real-time vessel positions, self-serve free signup — there's no keyless tier
for this kind of service, flagged clearly in Settings with a link to get one), decodes
PositionReport messages (lat/lon/speed/course/MMSI), auto-reconnects with backoff, and
caps at 300 rendered vessels so a global feed doesn't overwhelm the scene or the
screen.

Each vessel renders as a small boat silhouette (bow point, flat stern, extruded via
SCNShape — a primitive shape, not an imported 3D model; there's no asset pipeline here
for that) that rotates to its heading and glides to each new position over ~4 seconds
rather than snapping, since real AIS reports arrive periodically rather than
continuously — the honest approximation of "watch it move" a real-world feed supports.
Tapping a vessel shows an info card (name, MMSI, speed, heading, position, last
update), same visual style as the existing satellite card.

**Scope, stated plainly:** this is the iOS piece, as asked for first. The web port
(leatr.xyz's Mantis Radar module) is a deliberate, separate next step, not done here.
Also worth knowing: this is new, sizable SceneKit/WebSocket code that hasn't been
verified on a real device yet — please try all three tabs once this lands in
TestFlight and let me know if anything about the maritime view looks or behaves
wrong.

## Build 127 — training catalog now shows the real reconnect flow instead of a raw error

Build 126 fixed the anonymous-fetch 404s and correctly moved to an authenticated
request — which then surfaced "Bad credentials," GitHub's actual 401 response,
meaning the stored token itself is invalid or expired right now. This is not a new
bug: it's the identical symptom the Ash Shard's contact list already handles (build
111/113) — a plain retry fails the same way every time, reconnecting is what actually
fixes it. `AdminTrainingCatalogPanel` didn't have that handling yet, so it just showed
the raw error with no path forward.

Applied the same, already-established fix: detecting "bad credentials" now shows a
"↻ Reconnect GitHub" button that presents the real device-flow sheet (code shown,
auto-copied, deep-linked so GitHub's page pre-fills it), and automatically retries the
category that failed once reconnection succeeds.

## Build 126 — root cause of "HTTP 404 for advertising": leatr-ash is a private repo, and it broke my own build 122 too

Confirmed the actual cause, not just this one category: `leatr-ash` is a **private**
GitHub repository. Every training-catalog category 404s identically (tested
aerospace, agility, architecture, art — all 404) because the training-catalog panel
fetched anonymously from `raw.githubusercontent.com`, and GitHub deliberately returns
404 (not 401/403) for unauthenticated requests to a private repo's raw content, to
avoid confirming the repo even exists. The file was never missing.

**Also found this broke my own build 122 fix**, and I want to be direct about that:
`WordNetStore`'s remote fallback used the identical anonymous-fetch pattern, so it
could never have actually worked, only the bundle-local path could. Fixed both,
properly this time: `AdminTrainingCatalogPanel` now uses the authenticated GitHub
Contents API via `GitHubClient` (which already holds the admin's token from sign-in),
with an explicit `ref=training` since this data lives on the training branch, not
`leatr-ash`'s default. `WordNetStore` can't hold a token or depend on `GitHubClient`
itself (same LEATRCore/AutumnServices boundary as everywhere else in this system), so
a new `WordNetRemoteSync` fetches authenticated at launch and hands the decoded
buckets down, the same hand-down pattern as `GrammarReferenceSync`.

## Build 125 — open-topic buffer: a thought split across messages doesn't reset each turn

The real, scoped piece of "hold a pattern as a placeholder and refine it as more data
arrives instead of classifying from one message in isolation." Every message was
previously classified completely independently — no way to say "this is the second
half of what they were just describing." Added `OpenTopic`: a per-user buffer that
holds recent tokens when a message looks like an unfinished fragment (starts with a
continuation cue — "and," "also," "then" — or leans on a referential pronoun without
introducing its own subject), and merges it with the next message before topic
matching, WordNet lookup, and study-gap detection run. A thought split across two
short messages ("the constraint is buoyancy drift" / "and it shows up after the third
cycle") now has a real chance to resolve as one topic instead of two separate,
under-informative fragments.

Bounded on purpose: caps at 3 turns held open and 60 tokens merged, and closes as soon
as a real answer is found or the fragment signal stops appearing, so an unresolved
thread can't grow without limit or silently outlive the conversation it belonged to.
Only the topic/dictionary/gap-detection lookups use the merged context — the actual
reply's wording, emotion, and tool routing still reflect what was just said in this
specific message.

**Scope, stated as plainly as every build before it:** this is real, incremental
progress on multi-turn context — it is not the full multi-level reflexive parser
described (character → pattern → sequence-of-patterns → topic, each independently
revisable at every level). That's a much larger architecture change; this is the
single most valuable, containable piece of it, built and verified rather than
attempted whole and unverified.

## Build 124 — the study queue: she records what she doesn't know, without any training

The honest, buildable version of "she educates herself" without wiring an LLM and
without training an actual model: she can't generate new knowledge from nothing, but
she can genuinely notice and record specific gaps in what she knows, growing a real,
reviewable to-do list over time.

Mechanism: `GrammarTurn` now carries an optional `studyGap` — set when a message looks
like a genuine definitional question ("what is X") that matched neither a curated
topic (build 121) nor the WordNet dictionary (build 122). When that happens,
`ChatViewModel` writes it to a new `ashtree/sentient/study-queue.json` on `leatr-ash`
— the word asked about, the surrounding message for context, timestamp, which
platform. This is a real, structured, growing record of exactly what reference
content is missing, not vague self-improvement — every entry names a specific thing
to go add real content for.

Added a **STUDY QUEUE** panel to Admin's ASH tab so this is actually visible and
actionable — the 15 most recent gaps, word and context, load-on-demand. Deliberately
read-only: filling a gap means writing real content to `ashtree/reference/`, the same
way every topic and definition already there got added — this panel shows what's
missing, it doesn't try to fill it automatically (nothing here could, honestly).

**What this is not, stated as plainly as the last several builds:** she is not
learning to converse more fluently from this, and she is not synthesizing new
knowledge. This is a todo list she keeps for herself and for whoever's adding
reference content — a real, useful piece of self-directed operation within what a
rule-based system can actually do, not a step toward what only training does.

## Build 123 — CI compile fix: build 122 never actually shipped

Build 122 **failed CI** — caught this time before reporting it as shipped. A closure
syntax error in `LexicalAnalyzer.swift`'s fix (nested closures both trying to use
implicit `$0`, which Swift doesn't allow once the inner one has an explicit parameter
name). Fixed by naming both closures' parameters explicitly. No logic changes —
everything from 122 (the real WordNet dictionary wiring, the schema fix) is included
here and actually builds this time.

## Build 122 — real dictionary lookup for the "unknown topic" case (~66K words, found already built, wired wrong)

The concrete answer to "she should be able to look up what a word means for anything
unknown": `WordNetStore.swift` already existed — a full Princeton WordNet dictionary,
~66K real word definitions, split into three real data files already sitting on
`leatr-ash` (`wordnet_a_h/i_r/s_z.json`, ~23MB total, verified as real content, not
stubs). It was only ever wired into `LexicalAnalyzer`, a second analysis pipeline that
was already known to be unused (`ChatViewModel.send()` calls `GrammarEngine`
directly) — same disconnected-capability pattern as MusicKit and Weather before it.

**Also found a real bug while connecting it:** the Swift struct expected one
definition object per word; the actual data has an *array* of sense objects per word
(a word can have multiple parts of speech/meanings — "volcano" has two noun senses).
That mismatch meant every single lookup would have silently failed to decode, even
once wired up. Fixed the struct to match the real schema, verified against actual
entries (`volcano` → "a fissure in the earth's crust... through which molten lava and
gases erupt").

**Now wired into `GrammarEngine.compose()`** as the general-purpose version of build
121's curated topics: checked after the curated topic list (so a real hand-written
summary still wins when one exists), matching "what is/what's/define X" explicitly,
or the most prominent noun in a genuine question as a broader fallback. Real,
substantial coverage — tens of thousands of ordinary English nouns now get an actual
definition instead of falling through to a generic template.

**Same honest boundary as build 121, stated again because it's still true:** a
definition is retrieval, not discussion — she'll tell you what a volcano *is*, not
discuss volcanoes, hold an opinion on one, or handle a proper noun/personal topic that
isn't in a dictionary. That gap is real and still needs either more curated topic
content or the isolated Claude path to close for genuinely open conversation.

## Build 121 — real topic knowledge (retrieval, not training) — history to start

The actual buildable version of "she needs to know about world events, the Egyptians,
the Roman Empire, the Iron Age, world economics" without training an actual neural
network: retrieval. `GrammarReference.topics` — new keyword-matched real content,
same live-fetch mechanism as build 117's phrases and build 120's stories. A message
mentioning a topic gets the actual written summary as its answer, not a template
wrapped around an echo of the question. Longest matching key wins, so "roman empire"
beats a looser single-word coincidence.

Started narrow and real rather than broad and thin: six genuine history topics (Roman
Empire, Ancient Egypt, Bronze/Iron Age, Medieval period, Industrial Revolution, world
economics) with actual written content, to prove the mechanism end to end before
expanding across every category in the Training branch. Adding more topics — history
or any other category — is editing `ashtree/reference/grammar-en.json` on `main`, no
rebuild, same as everything else in this reference-sync system.

**The honest boundary, stated plainly:** this makes her genuinely good at topics that
have real content written for them. It does not give her an opinion, let her
synthesize two unrelated topics into something new, or handle a subject nobody's
written reference material for yet — that's not a bug to fix later, it's the actual
edge of what retrieval does versus what a trained model does.

## Build 120 — real story-telling + the actual reason writes could silently fail

**Feedback submission showing "SUBMITTED" but never appearing in MESSAGES:** found a
real, significant bug by comparing directly against the web app's own write code.
`postPlain` (used by every GAS write — feedback, journal, sessions) only checked the
HTTP status code, treating any 200 response as success. But GAS webapps almost always
return HTTP 200 even when the operation failed internally — the script catches its
own errors and still responds normally at the HTTP level. Web's own `viaGas` function
parses the response *body* and checks for a real success indicator (`ok`/`commit`/
`sha`) or an explicit `error` field — it never trusts the status code alone. iOS never
did this check at all. Fixed `postPlain` to match web's exact contract. This affects
every write through this path, not just feedback — journal entries and session writes
were exposed to the same silent-failure risk.

**"Tell me a story" → "Got it — Tell me a story.":** a fair, glaring catch — an
acknowledgment isn't a story. Added real story-telling: `GrammarEngine` now recognizes
story requests and returns one of five actual complete short stories, live from
`ashtree/reference/grammar-en.json`'s new `stories` array (same dynamic-sync mechanism
from build 117 — add more there anytime, no rebuild needed) with a small built-in
fallback set if the reference hasn't loaded. Won't repeat the same story twice in a
row for the same person.

**Not done this build, stated plainly again:** Ash Star's per-user "Autumn Ash"
library save (folder picker, Save All) is real, substantial new feature work that
still hasn't been started — it needs its own dedicated pass, not another turn where
it competes with verified bug fixes for the same build's attention.

## Build 119 — repetition bug, mailbox hang, and button layout — three confirmed, fixed

**"Picking up where we left off" gluing onto nearly every reply:** found the exact
bug — the condition was "previous message text != current message text," which is
true for almost any two real consecutive messages a person actually sends. It wasn't
narrowly catching genuine continuity, it was firing on nearly everything. Removed
entirely rather than trying to narrow the condition — it wasn't referencing anything
specific from the prior turn anyway, so it added repetition without adding real
continuity. Also fixed the garbled topic extraction ("Einstein learning have you
learned who" → "Einstein learning learned") by echoing a cleaned version of what was
actually said instead of reassembling scattered content-word tokens, which isn't
sentence reconstruction and can come out scrambled.

**MESSAGES tab stuck on "LOADING..." indefinitely (both INBOX and ANALYSIS):** added
a hard 15-second overall timeout around the whole folder load. Each individual fetch
attempt inside `loadFolder` already had its own timeout, but nothing bounded the total
across all of them, so a slow chain could look identical to a permanent hang with no
way to tell the difference. Now it always resolves to either real data or a visible
error with Retry.

**Button row deforming when switching to ANALYSIS/READ:** the UNREAD button only
shows on non-Inbox folders, making that row one button wider than the fixed-width
admin panel comfortably fits — that's what was squeezing everything. Row now scrolls
horizontally instead of trying to compress to fit.

**Not done this build, scoped honestly:** Ash Star's per-user save-to-"Autumn Ash"
library (folder picker, Save All, matching the web app) is real, substantial new
feature work — building it into this same pass risked rushing three fixes that
needed to be verified. Next up once these are confirmed.

## Build 118 — real weather answers instead of a template (the "prescriptive, not proportional" fix)

Confirmed live in the recording: "What's the weather today?" got "On What's weather
today — tell me a bit more and I'll work through it with you. Picking up where we left
off." — a fair, important catch. That's still a template, just a nicer-sounding one
than build 116's; for a factual question with a real answer, no template can ever be
a genuinely proportional response, because there's nothing to compute from in a
template — only in real fetched data.

Found the same pattern as MusicKit before it: `AutumnWeather.swift` is a complete,
correctly-written WeatherKit integration (current conditions + hourly forecast) that
was never called from anywhere. New `WeatherIntent` detects weather questions and
routes them to actually fetch real weather via `AutumnWeather` + the existing
`AutumnMaps` location manager, then reports genuinely computed data — actual
temperature, condition, feels-like, UV index — instead of falling into
`GrammarEngine`'s generic templates. If location isn't available or the fetch fails,
it says so honestly (no location access yet; the request failed) rather than
fabricating a plausible-sounding non-answer.

**Scope note, stated plainly:** this fixes the one concrete example shown — weather —
by giving it a real capability to route to. It is not a general solution to every
open-ended question; genuinely conversational exchanges ("how are you") still use the
build 116/117 template system, honestly, because there's no objective fact to compute
for those — a feeling isn't something you fetch. The distinction going forward: does
this question have a real, computable answer? If yes, it should get its own intent
route like this one, not a nicer template. If no, template variety (already reference-
data-driven since build 117) is the honest approach.

**Also investigated, not yet fixed:** the MESSAGES tab still showing "0 entries in
ANALYSIS (feedback/analysis.json)" despite that file genuinely having 2 valid entries
on `leatr-ash` main — confirmed the file itself is fine and build 113's legacy-path
fix wasn't the actual problem here (the primary path already has real data). The
actual failure is somewhere further down the read pipeline (`readViaGAS`/`coerce` in
`FeedbackService`) that I haven't isolated yet — flagging honestly rather than
shipping a second guess in the same build.

## Build 117 — the real dynamic-sync loop: GrammarEngine reads live reference data, no rebuild needed

First real, working piece of "she should always be dynamically syncing with reference
material." Added `ashtree/reference/grammar-en.json` to `leatr-ash`'s **main** branch
(not `training` — confirmed the app's GitHub reads are hardcoded to `main`, so that's
where anything she actually reads at runtime has to live; `training` stays the staging
ground for building new material before merging finished pieces over). This file is
genuinely structured data — feeling-phrase variants per emotion, follow-up question
banks, acknowledgment templates — unlike `Training/grammar/`'s citation catalogs.

New `GrammarReferenceSync` (`AutumnServices`) fetches that file once per launch via the
existing no-token `ashread` GAS proxy and hands it to `GrammarEngine` as a plain
`GrammarReference` value. `GrammarEngine` itself never reaches out over the network —
it lives in `LEATRCore`, which by design has no network access and can't depend on
`AutumnServices` without a circular dependency, so the fetch happens one layer up and
gets handed down. `compose()`'s feeling-phrases, follow-ups, thanks, farewells, and
acknowledgment templates all now prefer this live data (multiple phrasing variants,
picked at random) and fall back to the small built-in set from build 116 if the fetch
hasn't completed or ever fails — so she always has something to say, online or off.

**What this actually proves:** editing `grammar-en.json` on `main` changes what she
says on both platforms' next launch, with zero app rebuild — the concrete, working
version of "the training branch lets her keep growing without touching the app,"
scoped honestly to what's real today (one file, one composer) rather than promised
broadly. Expanding her range from here is editing that JSON (or adding new reference
files following the same pattern), not writing more Swift.

## Build 116 — GrammarEngine.compose() speaks like conversation, not a log line

Confirmed live: "How are you doing autumn" → "Noted: doing autumn. Buoyancy reflexed
on REFLEX. Inspiring on the outer shell. Journal will write this turn into leatr-ash
via GAS." That's `compose()`'s literal fallback template, firing exactly as written —
not a bug, this is her own local LEATR-only engine genuinely running, just with a
mechanical, debug-log-style vocabulary for anything that wasn't a greeting or an
identity question.

Added real pattern handling for common conversational turns instead of falling
straight to the shell-report template: how-are-you style check-ins now get an actual
first-person feeling answer (`feelingPhrase(emotion)`, one phrase per emotion —
happy/excited, sad, worried, angry, neutral, etc.) plus a natural follow-up question;
"thanks"/"thank you" gets a real acknowledgment; farewells get a real goodbye. The
general fallback (anything else) now says something like "Got it — topic." or "On
topic — tell me more" instead of "Noted: topic. Buoyancy reflexed on..." — the
shell/buoyancy/tool values still get journaled internally exactly as before
(`journalInner`, unchanged), they just don't get spoken aloud as the reply text
anymore.

This only touches `compose()`'s output text — the FRP math, shell routing, emotion
classification, and journaling underneath are all unchanged.

## Build 115 — Claude isolated into its own removable directory (pure reorganization, no behavior change)

Moved `AnthropicClaudeProvider` out of the shared `ReasoningProvider.swift` file into its
own `Sources/AutumnServices/ClaudeIntegration/` directory — Autumn's one optional
external collaborator, structured so the whole directory (plus one switch case in
`ChatViewModel.configure()`) can be deleted entirely without touching her own network
at all: `GrammarEngine`, `LEATROnlyProvider`, and the `ReasoningProvider` protocol
itself all stay in place, unaffected. `LEATROnlyProvider` (her permanent, non-optional
default) and `AppleIntelligenceProvider` stay where they are — this move is scoped to
exactly what was asked, the Claude piece specifically.

**Capability note, documented directly in the new file:** `AnthropicClaudeProvider` is
correctly implemented — it builds a real request to Claude, includes conversation
history, and passes her LEATR shell/buoyancy/emotion state in as context — but it is
not currently invoked anywhere. `ChatViewModel.send()` calls
`GrammarEngine.processForChat()` directly rather than going through
`reasoningProvider`, so adding an API key today doesn't yet change actual replies.
Wiring that up is real, separate follow-up work — deliberately not attempted here, so
this move changes zero behavior, only organization.

**Worth flagging — an asymmetry between the two apps:** on iOS, Autumn's own
`GrammarEngine`-based reflex engine already handles 100% of chat with no external
dependency; Claude would only ever be an optional enhancement once wired in. On the
web app, by contrast, Claude is currently the *only* engine — there's no equivalent
local-only fallback there yet. Isolating "the Claude piece" the same way on web isn't
a safe like-for-like move yet, since removing it would remove all chat capability,
not just an enhancement layer. Porting an equivalent to `GrammarEngine` for web would
be its own project, not a rename/move.

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
