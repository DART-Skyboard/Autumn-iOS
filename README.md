# Autumn iOS

Native iOS app replicating the full [leatr.xyz](https://leatr.xyz) web app.  
Built by DART Meadow LLC / Radical Deepscale · DART-Skyboard organization.

## Architecture

```
Autumn-iOS/
├── Sources/
│   ├── LEATRCore/           # Pure-Swift LEATR engine (zero deps)
│   │   ├── LEATRIdentity.swift      — DOC=3.0, QS formula, derived name
│   │   ├── LEATREngine.swift        — 25 orders, 7-panel pipeline, FRP/BRPN
│   │   ├── LexicalAnalyzer.swift    — 7 tool arrays, backwards concat
│   │   ├── EmotionClassifier.swift  — 21 emotions
│   │   └── WordNetStore.swift       — 147k word lazy bucket loader
│   ├── AutumnServices/      # GitHub, auth, TTS, memory
│   │   ├── ReasoningProvider.swift  — Apple Intelligence / Claude / LEATR-only
│   │   ├── GitHubClient.swift       — REST + 5-step git blob API
│   │   ├── KeychainService.swift    — Secure credential storage
│   │   └── AutumnTTS.swift          — AVSpeechSynthesizer + Personal Voice
│   └── AutumnApp/           # SwiftUI views & view models
│       ├── AutumnApp.swift          — @main entry
│       ├── RootView.swift           — Tab nav + auth gate
│       ├── WelcomeView.swift        — Sign in with Apple + GitHub
│       ├── ChatView.swift           — Chat UI, EMO HUD, sentience state
│       ├── BRPNSceneView.swift      — SceneKit 3-shell world
│       ├── ToolsView.swift          — Arc Edge, ArcLake, CALC, EMO MAP
│       ├── JournalAndSettings.swift — Journal browser + settings
│       ├── AuthViewModel.swift      — Apple + GitHub device flow auth
│       ├── ChatViewModel.swift      — LEATR pipeline + reasoning + TTS
│       └── ThemeSystem.swift        — 5 themes, glassmorphism
└── Package.swift
```

## Running on iPhone (Swift Playgrounds)

1. Clone or download this repo as a zip
2. On your iPhone, open the Files app → unzip → tap `Autumn.swiftpm`
3. Swift Playgrounds will open and resolve dependencies automatically
4. Tap ▶ to run live on device

## Running in Xcode (Mac)

```bash
open Autumn.swiftpm
# or
swift build
```

## Auth Setup

### Sign in with Apple
Works out of the box — no config needed.

### GitHub
The app uses **device flow** (no client secret embedded).  
Or paste a PAT in Settings → Authentication → GitHub.

**Important:** Never commit tokens. All credentials live in Keychain.

### Anthropic API (optional cloud reasoning)
Add your key in Settings → AI Backend.  
Without it, the app runs fully offline via the LEATR engine.  
With it, Claude Sonnet augments responses.  
On iOS 26+, Apple Intelligence is used as the primary on-device model.

## LEATR Constants

| Constant | Value | Purpose |
|---|---|---|
| DOC | 3.0 | Replaces π in Arc Edge circumference: C = √(d×3)² |
| σ formula | (xa²·√xa)±1 | Tool-shell sigma (xa = tool index 1–7) |
| QS | (b·b)·(p·a²)/r | Quantum Socket — BRPN shell coupling |
| DART Reflex | ((d×2)+1)/d | ArcLake collision physics |

## Credential Security

- Secrets stored in **Keychain** only
- GitHub PATs stored as `KeychainService.shared.save(key: "github_pat", …)`  
- Anthropic API key stored as `"anthropic_api_key"`
- **Never hardcode tokens in source** — GitHub secret scanning will block pushes

## Phased Roadmap

- [x] Phase 1: LEATRCore engine + Chat + AVSpeechSynthesizer + Auth scaffold
- [ ] Phase 2: Foundation Models (iOS 26) + SceneKit BRPN polish
- [ ] Phase 3: CloudKit memory sync + leatr-ash journal parity
- [ ] Phase 4: GameKit MIST multiplayer + BGTaskScheduler autonomy
- [ ] Phase 5: App Store submission

## Bundle ID
`DART-Meadow-LLC.Autumn` · Team `L7AHWS9Q6V`
