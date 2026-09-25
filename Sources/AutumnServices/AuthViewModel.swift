import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import Security

/// AuthViewModel — guest-first like the web app.
/// GitHub: device flow + ASWebAuthenticationSession using the same OAuth App as leatr.xyz.
/// OAuth access tokens live in Keychain. Never a PAT paste field.
@MainActor
public final class AuthViewModel: NSObject, ObservableObject {

    @Published public var isSignedIn      = true   // web is guest-first; no hard gate
    @Published public var isGuest         = true
    @Published public var githubConnected = false
    @Published public var username        = "Guest"
    @Published public var githubUsername  = ""
    @Published public var appleUserId     = ""
    @Published public var appleEmail      = ""
    @Published public var error: String?  = nil
    @Published public var deviceFlowCode: DeviceFlowDisplay? = nil
    @Published public var savedAppleAccounts:  [SavedAccount] = []
    @Published public var savedGitHubAccounts: [SavedAccount] = []
    @Published public var githubAvatarURL: URL? = nil
    @Published public var isAuthenticating = false
    @Published public var adminEnabled = false
    /// When true, Welcome / SIWA cover can show an Open Settings deep-link (1000/1001).
    @Published public var appleErrorOffersSettings = false

    /// TF105: custom profile username, independent of GitHub/Apple identity —
    /// what makes this necessary is Apple-only sign-in has no inherently unique
    /// handle the way a GitHub username already is. Uniqueness is enforced
    /// against ashtree/users/<name>/ in leatr-ash (the same directory
    /// AdminDataService.loadUsers() already lists as the admin console's user
    /// roster — claiming a name here is what populates it, not a separate
    /// registry). Persisted locally so it's restored exactly as left on next
    /// launch; also written to leatr-ash so it renders in Admin Console data.
    @Published public var customUsername: String = ""
    @Published public var usernameClaimState: UsernameClaimState = .idle

    public enum UsernameClaimState: Equatable {
        case idle
        case checking
        case available
        case taken
        case claimed
        case invalid(String)
        case error(String)
    }

    /// What every profile-facing display (Apple ID row, GitHub row, header)
    /// should show once a custom username is set — falls back to whatever
    /// identity is already active otherwise. This is purely a *display* layer;
    /// the real githubUsername/appleUserId used for auth/backend calls never
    /// changes.
    public var effectiveDisplayName: String {
        customUsername.isEmpty ? username : customUsername
    }

    public var sessionUID: String {
        if githubConnected && !githubUsername.isEmpty { return githubUsername }
        if !appleUserId.isEmpty { return "apple-" + appleUserId.prefix(8) }
        return UserDefaults.standard.string(forKey: "autumn_guest_uid") ?? {
            let u = "ios-" + UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(u, forKey: "autumn_guest_uid")
            return u
        }()
    }

    /// Web `_aut_sid` — one sid per install so we do not mint a new live orb every launch.
    public var sessionSID: String {
        if let s = UserDefaults.standard.string(forKey: "autumn_session_sid"), !s.isEmpty { return s }
        let s = sessionUID + "_t" + String(Int(Date().timeIntervalSince1970), radix: 36)
        UserDefaults.standard.set(s, forKey: "autumn_session_sid")
        return s
    }

    public var adminAllowed: Bool {
        githubConnected && githubUsername.lowercased() == AutumnConfig.adminUsername
    }

    /// Bumped by cancelGitHubAuth so in-flight poll loops exit.
    private var githubPollGeneration = 0

    private let keychainKey    = "autumn_apple_user_id"
    private let displayNameKey = "autumn_apple_display_name"
    private let appleEmailKey  = "autumn_apple_email"
    private let oauthTokenKey  = "github_oauth_token"
    private let oauthUserKey   = "github_username"
    private let customUsernameKey = "autumn_custom_username"
    /// TF114: persisted pending device-flow state — see startGitHubAuth/resumePendingGitHubAuthIfNeeded.
    private let pendingDeviceCodeKey = "autumn_pending_device_code"
    private let pendingDeviceIntervalKey = "autumn_pending_device_interval"
    private let pendingDeviceStartedKey = "autumn_pending_device_started"

    private var _currentNonce = ""
    /// Strongly retain the ProfileSheet-driven ASAuthorizationController.
    private var appleAuthController: ASAuthorizationController?

    public func restoreSession() {
        loadSavedAccounts()
        customUsername = KeychainService.shared.load(key: customUsernameKey) ?? ""
        appleEmail = KeychainService.shared.load(key: appleEmailKey) ?? ""
        adminEnabled = (UserDefaults.standard.string(forKey: AutumnSettingsSync.adminKey) == "1"
            || UserDefaults.standard.bool(forKey: AutumnSettingsSync.adminKey)) && adminAllowed
        if let urlStr = KeychainService.shared.load(key: "github_avatar_url"),
           let url = URL(string: urlStr) {
            githubAvatarURL = GitHubClient.sizedAvatarURL(from: url.absoluteString) ?? url
        }

        // OAuth token only — never read a user-pasted PAT field.
        // Migrate leftover device-flow token stored under the old key.
        let token = KeychainService.shared.load(key: oauthTokenKey)
            ?? KeychainService.shared.load(key: "github_pat")
        if let token, !token.isEmpty {
            if KeychainService.shared.load(key: oauthTokenKey) == nil {
                KeychainService.shared.save(key: oauthTokenKey, value: token)
                KeychainService.shared.delete(key: "github_pat")
            }
            let ghUser = KeychainService.shared.load(key: oauthUserKey) ?? ""
            if !ghUser.isEmpty {
                githubConnected = true
                githubUsername  = ghUser
                isGuest = false
                if username == "Guest" || username.isEmpty { username = ghUser }
                restoreAdminFlag()
            }
            // Always refresh login + avatar from GET /user when a token is present.
            let restoreUser = ghUser
            Task {
                await GitHubClient.shared.setToken(token)
                await applyGitHubProfile()
                if !restoreUser.isEmpty {
                    await AutumnSettingsSync.restoreFromVaultThenPush(username: restoreUser)
                }
            }
        }

        // TF114: resume a pending device-flow poll that survived an app kill —
        // see resumePendingGitHubAuthIfNeeded's own comment for why this exists.
        resumePendingGitHubAuthIfNeeded()

        guard let savedUID = KeychainService.shared.load(key: keychainKey),
              !savedUID.isEmpty else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: savedUID) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized, .transferred:
                    self.appleUserId = savedUID
                    // TF107: same GitHub-takes-priority fix as applyAppleAuthorization —
                    // this ran AFTER GitHub restoration above already set the correct
                    // username, then stomped it with the saved (possibly "User")
                    // Apple display name regardless.
                    if !(self.githubConnected && !self.githubUsername.isEmpty) {
                        self.username = KeychainService.shared.load(key: self.displayNameKey) ?? self.username
                    }
                    self.isSignedIn  = true
                    self.isGuest     = false
                    Task { await UserVaultService.shared.setup(
                        githubUsername: self.githubConnected ? self.githubUsername : nil) }
                case .revoked, .notFound:
                    KeychainService.shared.delete(key: self.keychainKey)
                    KeychainService.shared.delete(key: self.displayNameKey)
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: — Apple

    /// Called from AppleSignInButton.onRequest — sets nonce BEFORE performRequests.
    public func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        error = nil
        appleErrorOffersSettings = false
        let rawNonce = generateNonce()
        _currentNonce = rawNonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)
    }

    /// Called from AppleSignInButton.onCompletion (and legacy delegate).
    public func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            applyAppleAuthorization(authorization)
        case .failure(let error):
            applyAppleError(error)
        }
    }

    /// Legacy no-op — AppleSignInButton owns the ASAuthorizationController
    /// (Welcome + root fullScreenCover). Never start SIWA outside the button's tap gesture.
    public func signInWithApple() {
        // Intentionally empty (Ashtree IDEAuthViewModel pattern).
    }

    /// Removed (TF84/87): dismiss-then-perform or nested Profile button → .unknown / 1000.
    /// Welcome is primary SIWA; Profile opens root fullScreenCover with AppleSignInButton.
    public func performAppleSignInFromRootWindow() {
        // Intentionally empty — keep symbol for any stale call sites.
    }

    public func switchAppleAccount(to account: SavedAccount) {
        appleUserId = account.id
        username    = account.displayName
        KeychainService.shared.save(key: keychainKey,      value: account.id)
        KeychainService.shared.save(key: displayNameKey,   value: account.displayName)
        isSignedIn = true; isGuest = false
        Task { await UserVaultService.shared.setup(
            githubUsername: githubConnected ? githubUsername : nil) }
    }

    // MARK: — GitHub device flow (ASWebAuthenticationSession)
    /// - Parameter openVerification: When true (default), opens ASWebAuthenticationSession.
    ///   GitHubDeviceFlowSheet passes false and owns the dismissible Safari sheet instead —
    ///   stacking both overlays left Cancel/swipe broken.
    public func startGitHubAuth(openVerification: Bool = true) async {
        error = nil
        isAuthenticating = true
        githubPollGeneration += 1
        let gen = githubPollGeneration
        do {
            let flow = try await GitHubClient.shared.startDeviceFlow(clientId: AutumnConfig.githubClientId)
            guard gen == githubPollGeneration else { return }
            deviceFlowCode = DeviceFlowDisplay(
                userCode: flow.userCode, verificationUrl: flow.verificationUri,
                deviceCode: flow.deviceCode, interval: flow.interval)
            persistPendingDeviceFlow(deviceCode: flow.deviceCode, interval: flow.interval)
            if openVerification, let url = URL(string: flow.verificationUri) {
                GitHubOAuth.shared.openDeviceVerification(url: url)
            }
            await pollForGitHubToken(deviceCode: flow.deviceCode, interval: flow.interval, generation: gen)
        } catch {
            // GAS fallback for device code (same as web)
            if let d = await AutumnGASClient.shared.deviceCode(),
               let userCode = d["user_code"] as? String,
               let deviceCode = d["device_code"] as? String,
               let uri = d["verification_uri"] as? String {
                guard gen == githubPollGeneration else { return }
                let interval = d["interval"] as? Int ?? 5
                deviceFlowCode = DeviceFlowDisplay(
                    userCode: userCode, verificationUrl: uri,
                    deviceCode: deviceCode, interval: interval)
                persistPendingDeviceFlow(deviceCode: deviceCode, interval: interval)
                if openVerification, let url = URL(string: uri) {
                    GitHubOAuth.shared.openDeviceVerification(url: url)
                }
                await pollForGitHubToken(deviceCode: deviceCode, interval: interval, generation: gen)
            } else {
                self.error = error.localizedDescription
                isAuthenticating = false
            }
        }
    }

    /// Stop device-flow poll + dismiss any ASWebAuthenticationSession. Safe to call from Cancel / sheet onDismiss.
    public func cancelGitHubAuth() {
        githubPollGeneration += 1
        deviceFlowCode = nil
        isAuthenticating = false
        GitHubOAuth.shared.cancel()
        clearPendingDeviceFlow()
    }

    // MARK: — Pending device-flow persistence (TF114)
    // A plain in-memory poll loop (below) doesn't survive the app being fully
    // terminated by iOS while backgrounded during the Safari round-trip — not
    // just suspended, actually killed, which does happen under memory pressure
    // or after enough time away. That wipes deviceFlowCode and the poll Task,
    // so on relaunch GitHubDeviceFlowSheet saw a nil deviceFlowCode and started
    // an entirely new device flow — a new code, orphaning the one the person
    // had just approved in Safari, which is exactly the "never completes,
    // has to start over" symptom. Persisting the pending code (until success,
    // cancel, or its own timeout) lets a fresh launch resume polling the SAME
    // code instead of silently discarding real progress.
    private func persistPendingDeviceFlow(deviceCode: String, interval: Int) {
        let d = UserDefaults.standard
        d.set(deviceCode, forKey: pendingDeviceCodeKey)
        d.set(interval, forKey: pendingDeviceIntervalKey)
        d.set(Date().timeIntervalSince1970, forKey: pendingDeviceStartedKey)
    }

    private func clearPendingDeviceFlow() {
        let d = UserDefaults.standard
        d.removeObject(forKey: pendingDeviceCodeKey)
        d.removeObject(forKey: pendingDeviceIntervalKey)
        d.removeObject(forKey: pendingDeviceStartedKey)
    }

    /// Called on launch (restoreSession) and whenever GitHubDeviceFlowSheet
    /// appears with no in-memory deviceFlowCode — if a still-valid pending
    /// code exists from before the app was killed, resume polling it instead
    /// of starting fresh. Device codes are valid for the ~15 minutes GitHub
    /// itself allots; past that there's nothing worth resuming.
    public func resumePendingGitHubAuthIfNeeded() {
        guard deviceFlowCode == nil, !isAuthenticating, !githubConnected else { return }
        let d = UserDefaults.standard
        guard let code = d.string(forKey: pendingDeviceCodeKey) else { return }
        let interval = d.integer(forKey: pendingDeviceIntervalKey)
        let started = d.double(forKey: pendingDeviceStartedKey)
        let age = Date().timeIntervalSince1970 - started
        guard age < 15 * 60, age >= 0 else { clearPendingDeviceFlow(); return }
        isAuthenticating = true
        githubPollGeneration += 1
        let gen = githubPollGeneration
        // No userCode/verificationUrl survive the kill (never persisted — GitHub
        // doesn't need them for polling, only the person re-entering the code
        // did, and they already did that in Safari). Resume the poll silently;
        // if it succeeds the sheet dismisses on its own via githubConnected.
        Task { await pollForGitHubToken(deviceCode: code, interval: max(interval, 5), generation: gen) }
    }

    /// If a web-flow `code` ever lands (universal link / autumn://oauth?code=), exchange via GAS.
    public func completeWebFlow(code: String) async {
        error = nil
        isAuthenticating = true
        if let d = await AutumnGASClient.shared.exchangeCode(code),
           let token = d["access_token"] as? String, !token.isEmpty {
            await applyOAuthToken(token)
        } else {
            error = "GitHub exchange failed"
            isAuthenticating = false
        }
    }

    private func pollForGitHubToken(deviceCode: String, interval: Int, generation: Int) async {
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(max(interval, 5)) * 1_000_000_000)
            guard generation == githubPollGeneration else { return }
            guard let token = try? await GitHubClient.shared.pollDeviceFlow(
                clientId: AutumnConfig.githubClientId, deviceCode: deviceCode), !token.isEmpty else { continue }
            await applyOAuthToken(token)
            return
        }
        guard generation == githubPollGeneration else { return }
        deviceFlowCode = nil
        isAuthenticating = false
        GitHubOAuth.shared.cancel()
        clearPendingDeviceFlow()
        error = "Authorization timed out. Please try again."
    }

    private func applyOAuthToken(_ token: String) async {
        KeychainService.shared.save(key: oauthTokenKey, value: token)
        KeychainService.shared.delete(key: "github_pat")
        await GitHubClient.shared.setToken(token)
        await applyGitHubProfile()
        deviceFlowCode  = nil
        isAuthenticating = false
        clearPendingDeviceFlow()
        isSignedIn = true
        isGuest = false
        GitHubOAuth.shared.cancel()
        let user = githubUsername
        Task {
            await UserVaultService.shared.setup(githubUsername: user)
            await AutumnSettingsSync.restoreFromVaultThenPush(username: user)
        }
    }

    /// One GET /user. Persists login + avatar URL. Letter fallback only if this fails.
    private func applyGitHubProfile() async {
        guard let profile = try? await GitHubClient.shared.fetchAuthenticatedProfile() else { return }
        let ghUser = profile.login.isEmpty ? "GitHub User" : profile.login
        KeychainService.shared.save(key: oauthUserKey, value: ghUser)
        githubConnected = true
        githubUsername  = ghUser
        username = ghUser
        // TF157: AutumnServices can't import AutumnApp (would be circular),
        // so a notification is how a fresh sign-in tells
        // AnalyticsExportMaze to regenerate for the new session, rather
        // than a direct call.
        NotificationCenter.default.post(name: .autumnDidSignIn, object: nil)
        if let avatar = profile.avatarURL {
            githubAvatarURL = avatar
            KeychainService.shared.save(key: "github_avatar_url", value: avatar.absoluteString)
        }
        saveGitHubAccount(id: ghUser, displayName: ghUser, avatarURL: profile.avatarURL?.absoluteString)
        restoreAdminFlag()
    }

    public func switchGitHubAccount(to account: SavedAccount) {
        guard let token = KeychainService.shared.load(key: "github_oauth_\(account.id)") else { return }
        KeychainService.shared.save(key: oauthTokenKey, value: token)
        githubUsername = account.displayName
        githubConnected = true
        username = account.displayName
        isGuest = false
        if let s = account.avatarURL, let url = URL(string: s) {
            githubAvatarURL = url
            KeychainService.shared.save(key: "github_avatar_url", value: s)
        }
        restoreAdminFlag()
        Task {
            await GitHubClient.shared.setToken(token)
            await applyGitHubProfile()
            await UserVaultService.shared.setup(githubUsername: account.displayName)
            await AutumnSettingsSync.restoreFromVaultThenPush(username: account.displayName)
        }
    }

    public func disconnectGitHub() {
        githubConnected = false; githubUsername = ""
        githubAvatarURL = nil
        adminEnabled = false
        KeychainService.shared.delete(key: oauthTokenKey)
        KeychainService.shared.delete(key: oauthUserKey)
        KeychainService.shared.delete(key: "github_avatar_url")
        KeychainService.shared.delete(key: "github_pat")
        if appleUserId.isEmpty {
            isGuest = true
            username = "Guest"
        }
    }

    public func continueAsGuest() {
        isGuest = true; isSignedIn = true; username = "Guest"; error = nil
        Task { await UserVaultService.shared.setup(githubUsername: nil) }
    }

    public func signOut() {
        cancelGitHubAuth()
        disconnectGitHub()
        isGuest = true; githubConnected = false
        username = "Guest"; githubUsername = ""; appleUserId = ""
        error = nil; adminEnabled = false
        KeychainService.shared.delete(key: keychainKey)
        KeychainService.shared.delete(key: displayNameKey)
    }

    // MARK: — Admin flag (dartsolarpunk only)
    public func restoreAdminFlag() {
        guard adminAllowed else { adminEnabled = false; return }
        adminEnabled = UserDefaults.standard.string(forKey: AutumnSettingsSync.adminKey) == "1"
    }

    public func setAdminEnabled(_ on: Bool) {
        guard adminAllowed else { adminEnabled = false; return }
        adminEnabled = on
        UserDefaults.standard.set(on ? "1" : "0", forKey: AutumnSettingsSync.adminKey)
        AutumnSettingsSync.noteLocalChange()
    }

    public func toggleAdminFlag() {
        setAdminEnabled(!adminEnabled)
    }

    // MARK: — Custom profile username (TF105)
    // Uniqueness is enforced against ashtree/users/<name>/profile.json in leatr-ash
    // via the same no-token-needed GAS proxy (ashread/ashwrite) every other Ash
    // write already uses — not a new registry, the one AdminDataService.loadUsers()
    // already reads as the admin console's user roster. Claiming a name here is
    // literally what populates that directory.
    private static let usernamePattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_]{3,20}$")

    public func validateUsernameFormat(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard Self.usernamePattern.firstMatch(in: trimmed, range: range) != nil else {
            return "3-20 characters: letters, numbers, underscore only"
        }
        return nil
    }

    /// Checks availability, then claims the name if free. Updates
    /// `usernameClaimState` throughout so the UI can reflect checking/
    /// available/taken/claimed/error without a separate polling loop.
    public func claimUsername(_ raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = validateUsernameFormat(name) {
            usernameClaimState = .invalid(problem)
            return
        }
        let lower = name.lowercased()
        if lower == customUsername.lowercased() {
            usernameClaimState = .claimed
            return
        }
        usernameClaimState = .checking
        let path = "\(AutumnConfig.usersPrefix)/\(lower)/profile.json"
        let existing = await AutumnGASClient.shared.ashread(path: path)
        // TF107: was treating ANY non-empty dict response as "taken", including
        // a missing-file response — which GAS returns as a non-empty dict with
        // an `error` key (e.g. {"error":"not found"}), never as nil. That made
        // every single name look taken, no matter what was tried. Matched to
        // the same contract the web app's own _admUsable/_admIsNotFound use:
        // only a real `payload` or non-empty `content` means something's
        // actually there; an `error`-only response (or nil) means available.
        let taken: Bool
        if let dict = existing as? [String: Any] {
            let hasPayload = dict["payload"] != nil && !(dict["payload"] is NSNull)
            let hasContent = (dict["content"] as? String)?.isEmpty == false
            taken = hasPayload || hasContent
        } else if let str = existing as? String {
            taken = !str.isEmpty
        } else {
            taken = false
        }
        if taken {
            usernameClaimState = .taken
            return
        }
        usernameClaimState = .available
        let payload: [String: Any] = [
            "username": name,
            "claimedAt": ISO8601DateFormatter().string(from: Date()),
            "uid": sessionUID,
            "githubUsername": githubConnected ? githubUsername : "",
            "appleEmail": appleEmail
        ]
        let ok = await AutumnGASClient.shared.ashwrite(path: path, uid: sessionUID, append: false, payload: payload)
        if ok {
            customUsername = name
            KeychainService.shared.save(key: customUsernameKey, value: name)
            usernameClaimState = .claimed
        } else {
            usernameClaimState = .error("Couldn't save — try again")
        }
    }

    public func clearCustomUsername() {
        customUsername = ""
        KeychainService.shared.delete(key: customUsernameKey)
        usernameClaimState = .idle
    }

    @AppStorage("policy_accepted_v1") public var hasAcceptedPolicy = false
    public func acceptPolicy() { hasAcceptedPolicy = true }

    private func saveGitHubAccount(id: String, displayName: String, avatarURL: String? = nil) {
        if let idx = savedGitHubAccounts.firstIndex(where: { $0.id == id }) {
            if let avatarURL { savedGitHubAccounts[idx].avatarURL = avatarURL }
        } else {
            savedGitHubAccounts.append(SavedAccount(id: id, displayName: displayName, avatarURL: avatarURL))
        }
        persistAccounts()
        if let token = KeychainService.shared.load(key: oauthTokenKey) {
            KeychainService.shared.save(key: "github_oauth_\(id)", value: token)
        }
    }

    private func loadSavedAccounts() {
        if let d = UserDefaults.standard.data(forKey: "saved_github_accounts"),
           let a = try? JSONDecoder().decode([SavedAccount].self, from: d) { savedGitHubAccounts = a }
        if let d = UserDefaults.standard.data(forKey: "saved_apple_accounts"),
           let a = try? JSONDecoder().decode([SavedAccount].self, from: d) { savedAppleAccounts = a }
    }

    private func persistAccounts() {
        if let d = try? JSONEncoder().encode(savedGitHubAccounts) {
            UserDefaults.standard.set(d, forKey: "saved_github_accounts")
        }
    }
}

extension AuthViewModel:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        appleAuthController = nil
        handleAppleCompletion(.success(authorization))
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        appleAuthController = nil
        handleAppleCompletion(.failure(error))
    }

    fileprivate func applyAppleAuthorization(_ authorization: ASAuthorization) {
        switch authorization.credential {
        case let appleID as ASAuthorizationAppleIDCredential:
            let uid = appleID.user
            let first   = appleID.fullName?.givenName ?? ""
            let last    = appleID.fullName?.familyName ?? ""
            let newName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            // TF105: Apple only sends fullName/email on the VERY FIRST authorization
            // for a given app; every subsequent sign-in returns nil for both, which
            // is expected, not a bug. Persist whichever we get the first time we see
            // it, and prefer, in order: this authorization's name -> previously
            // saved display name -> this authorization's email -> previously saved
            // email -> "User" as the last resort (was always falling straight to
            // "User" before because only fullName was ever captured/fallen back to).
            if let email = appleID.email, !email.isEmpty {
                appleEmail = email
                KeychainService.shared.save(key: appleEmailKey, value: email)
            }
            let savedName  = KeychainService.shared.load(key: displayNameKey)
            let savedEmail = appleEmail.isEmpty ? KeychainService.shared.load(key: appleEmailKey) : appleEmail
            let display = !newName.isEmpty ? newName
                : (savedName ?? (savedEmail ?? "User"))
            KeychainService.shared.save(key: keychainKey,    value: uid)
            KeychainService.shared.save(key: displayNameKey, value: display)
            if !savedAppleAccounts.contains(where: { $0.id == uid }) {
                savedAppleAccounts.append(SavedAccount(id: uid, displayName: display))
                if let d = try? JSONEncoder().encode(savedAppleAccounts) {
                    UserDefaults.standard.set(d, forKey: "saved_apple_accounts")
                }
            }
            appleUserId = uid
            // TF107: don't let Apple's display name stomp an already-connected
            // GitHub account's username. Previously unconditional — if Apple
            // Sign In ran (or re-ran, e.g. during restoreSession) while GitHub
            // was already connected and active, and this authorization had no
            // fullName/email to derive a real name from, `username` got reset
            // to the bare "User" fallback, overwriting the correct GitHub
            // handle everywhere it's displayed (Profile header, Apple ID row,
            // GitHub row all read the same `username`). GitHub, once
            // connected, is the authoritative display identity.
            if !(githubConnected && !githubUsername.isEmpty) {
                username = display
            }
            isSignedIn = true; isGuest = false; error = nil
            let vaultUser = githubConnected ? githubUsername : nil
            Task {
                await UserVaultService.shared.setup(githubUsername: vaultUser)
                if let vaultUser, !vaultUser.isEmpty {
                    await AutumnSettingsSync.restoreFromVaultThenPush(username: vaultUser)
                }
            }
        case let password as ASPasswordCredential:
            username   = password.user
            isSignedIn = true; isGuest = false; error = nil
        default:
            break
        }
    }

    fileprivate func applyAppleError(_ error: Error) {
        let asErr = error as? ASAuthorizationError
        // Always keep raw [ASAuthorizationError N] for device reports.
        let code = asErr?.code.rawValue
        let codeTag: String = {
            if let c = code { return " [ASAuthorizationError \(c)]" }
            return " [non-ASAuthorizationError]"
        }()
        let desc = error.localizedDescription
        let signUpNotCompleted = desc.localizedCaseInsensitiveContains("Sign Up Not Completed")
            || desc.localizedCaseInsensitiveContains("signup not completed")

        switch asErr?.code {
        case .canceled:
            // User dismissed the sheet — stay silent (raw 1001 is .canceled).
            // Still map Apple's "Sign Up Not Completed" sheet copy if it arrives as canceled-ish.
            if signUpNotCompleted {
                self.error = "Sign in with Apple is temporarily unavailable. Please try GitHub or Settings → Apple ID, then try again." + codeTag
                self.appleErrorOffersSettings = true
            }
            return
        default:
            break
        }

        // Ashtree-style: 1001 / "Sign Up Not Completed" → temporarily unavailable.
        // 1000 (.unknown) often means entitlement/presentation poison or Apple ID hiccup.
        if code == 1001 || code == 1000 || signUpNotCompleted || asErr?.code == .unknown {
            self.error = "Sign in with Apple is temporarily unavailable. Please try GitHub or Settings → Apple ID, then try again." + codeTag
            self.appleErrorOffersSettings = true
            return
        }

        switch asErr?.code {
        case .invalidResponse, .notHandled, .failed:
            self.error = "Sign in failed: \(desc)" + codeTag
            self.appleErrorOffersSettings = (code == 1000 || code == 1001)
        case .notInteractive:
            self.error = "Sign in failed — Apple Sign In is not available in this context. Try again from Welcome." + codeTag
            self.appleErrorOffersSettings = false
        case nil:
            self.error = desc + codeTag
            self.appleErrorOffersSettings = signUpNotCompleted
        default:
            if let asErr {
                self.error = "Sign in failed (\(asErr.code.rawValue)): \(desc)" + codeTag
            } else {
                self.error = desc + codeTag
            }
            self.appleErrorOffersSettings = false
        }
    }

    public func openAppleIDSettings() {
        // App Settings (reliable). Undocumented App-prefs:APPLE_ID URLs are unreliable on modern iOS.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    fileprivate func generateNonce(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for r in randoms {
                guard remaining > 0 else { break }
                guard r < charset.count else { continue }
                let idx = charset.index(charset.startIndex, offsetBy: Int(r))
                result.append(charset[idx])
                remaining -= 1
            }
        }
        return result
    }

    fileprivate func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct DeviceFlowDisplay {
    public let userCode: String
    public let verificationUrl: String
    public let deviceCode: String
    public let interval: Int
}

public struct SavedAccount: Codable, Identifiable {
    public let id: String
    public let displayName: String
    public var avatarURL: String? = nil
}

extension Notification.Name {
    /// Fired once per fresh GitHub OAuth sign-in success — AutumnServices
    /// can't import AutumnApp, so this is how AnalyticsExportMaze (in
    /// AutumnApp) learns to regenerate for the new session.
    public static let autumnDidSignIn = Notification.Name("autumnDidSignIn")
}
