import Foundation

/// Public Autumn contracts copied from live web (`index.html` at c9e6512 / leatr.xyz).
/// No secrets. Client ID is the public GitHub OAuth App id. GAS is the same proxy the web uses.
public enum AutumnConfig {
    /// Live GAS Web App — source of truth: `/workspace/Autumn/index.html` `AUTUMN_GAS_URL`.
    public static let gasURL = "https://script.google.com/macros/s/AKfycbyzkQxLR5miUXP6oDw-1AR1GIjgpzlw9iLw0gO_ZTeLfL849LWbNX7WVz_kf7yLWBKA_w/exec"

    /// Public GitHub OAuth App client id (same as web `GH_CLIENT_ID`). No client secret in the app.
    public static let githubClientId = "Ov23li2K0njEqO1WTSdD"

    /// Same scopes as web. Device flow does not need a registered custom redirect.
    public static let githubScopes = "repo,read:user"

    /// Web OAuth redirect (leatr.xyz). Native uses device flow + ASWebAuthenticationSession.
    public static let githubWebRedirect = "https://leatr.xyz/"

    public static let ashOwner = "DART-Skyboard"
    public static let ashRepo = "leatr-ash"

    /// OTHER APPS depend on this path. Do not change it.
    public static let feedbackInboxPath = "feedback/inbox.json"
    /// MSG mailbox folders (web PR #29). inbox.json is the shared ingest path.
    public static let mailboxFolders = ["inbox", "analysis", "read", "trash"]

    public static let journalPath = "ashtree/sentient/journal.json"
    public static let sessionsPrefix = "ashtree/sessions/"

    /// Admin gate — matches web `_autAdminAllowed` (dartsolarpunk only).
    public static let adminUsername = "dartsolarpunk"

    public static let oauthCallbackScheme = "autumn"
    public static let bundleId = "com.dartmeadow.autumn"

    /// Admin ACL file in leatr-ash (web `_grantRole` / `_admRenderData`).
    public static let circuitPath = "admin/circuit.json"
    public static let aclPath = "admin/acl.json"
    public static let usersPrefix = "ashtree/users"
    public static let grammarStudyPath = "ashtree/grammar-study/index.json"

    /// Public Movement quote proxy already published on movement-conjecture.html (not a secret).
    public static let movementQuoteGAS = "https://script.google.com/macros/s/AKfycbwTBiGJ3YTibAGAsrC5sZMuQO-PqY0yK8gmmc7zvp1zXnaWQJvaZoRFCi2xLiI7QgSwfA/exec"
}

