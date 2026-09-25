import Foundation

/// TF143: real reflex activity, not simulated. GrammarEngine posts a named
/// stage each time it actually passes through a real step of processing a
/// real user message — tokenizing, verifying, doing math, routing a tool,
/// composing the reply, journaling. LeatrMindMapScene listens and pulses
/// the mind map nodes whose own text matches that stage, so what lights up
/// in the 3D view is a genuine reflection of what LEATR is actually doing
/// for that specific prompt, in that order, not a random idle walk.
///
/// NotificationCenter rather than a Combine/actor-based bus on purpose:
/// GrammarEngine.processForChat is async and its exact execution context
/// varies, and NotificationCenter.post is safe to call from anywhere
/// without the caller needing to know or care what thread it's on.
public enum ReflexStage: String {
    case userInput      = "User Input Prompt"
    case inbound         = "Inbound"
    case verification     = "Verification"
    case mathOrder        = "Natural Order of Operations"
    case allocation        = "Allocation"
    case branchLogic        = "Logic Allocation and Post Branch Inbound/Outbound"
    case outbound             = "Outbound"
    case aiOutput               = "AI Output Prompt"
    case journal                  = "Sentience Journal"
    case connectedResources        = "Connected Resources"
}

public enum ReflexActivityBus {
    public static let notificationName = Notification.Name("LeatrReflexStage")
    public static let toolNotificationName = Notification.Name("LeatrReflexTool")
    public static let mathOpNotificationName = Notification.Name("LeatrReflexMathOp")
    public static let emotionNotificationName = Notification.Name("LeatrReflexEmotion")
    // TF160: the three live real-time feeds animating in the BRPN scene
    // (aircraft/ADS-B, satellite/orbital, maritime vessels) had no
    // connection at all to analytics logging before this — only chat-driven
    // reflex stages were captured. Plus presence, for the fourth thing
    // asked for: the actual state of user-to-user buoyancy node
    // interactions in the scene, not just individual reflexes.
    public static let realTimeFeedNotificationName = Notification.Name("LeatrRealTimeFeed")
    public static let presenceNotificationName = Notification.Name("LeatrPresence")

    /// Post a real pipeline stage. Safe to call from any thread/actor.
    public static func fire(_ stage: ReflexStage) {
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: ["stage": stage.rawValue])
    }

    /// Post the specific Nature Tool actually routed for this message
    /// (e.g. "Maze", "Puzzle") — matched against the mind map's own Nature
    /// Tools node text, same node names shown in Ash Canvas. Carries the
    /// tool's real BRPNShell (geological/maritime/aerospace) so a listener
    /// can color the reflex by which shell actually did the work, using
    /// the same GEO/MAR/AERO palette the rest of the scene already uses —
    /// not a guessed or arbitrary color.
    public static func fireTool(_ toolName: String, shell: BRPNShell) {
        NotificationCenter.default.post(name: toolNotificationName, object: nil, userInfo: ["tool": toolName, "shell": shell.rawValue])
    }

    /// Post the specific math operation actually evaluated (e.g.
    /// "Multiplication"), when MathOOO genuinely performs one — matches
    /// the mind map's own PEMDAS node text under Natural Order of
    /// Operations.
    public static func fireMathOp(_ opName: String) {
        NotificationCenter.default.post(name: mathOpNotificationName, object: nil, userInfo: ["op": opName])
    }

    /// Post the emotion actually classified for this message (real output
    /// of classifyEmotion, not invented) — carries that emotion's own
    /// accentHex (already defined per-emotion in EmotionClassifier, used
    /// elsewhere in the UI for the same emotion) so the color a listener
    /// applies is the same one Autumn already associates with that
    /// emotion, not a new invented mapping.
    public static func fireEmotion(_ emotion: String, accentHex: String) {
        NotificationCenter.default.post(name: emotionNotificationName, object: nil, userInfo: ["emotion": emotion, "accentHex": accentHex])
    }

    /// Post one real-time-feed injection batch — fired once per batch
    /// (not per individual contact, since a batch can be dozens of
    /// aircraft/satellites/vessels at once and per-contact events would
    /// flood the log for no real analytical benefit). Carries the real
    /// counts actually injected into the scene for that feed type.
    public static func fireRealTimeFeed(kind: String, count: Int) {
        NotificationCenter.default.post(name: realTimeFeedNotificationName, object: nil, userInfo: ["kind": kind, "count": count])
    }

    /// Post the real state of user-to-user presence in the scene — how
    /// many other live buoyancy nodes are actually connected and
    /// interacting right now, the fourth thing asked for alongside the
    /// three live feeds above.
    public static func firePresence(connectedCount: Int) {
        NotificationCenter.default.post(name: presenceNotificationName, object: nil, userInfo: ["connectedCount": connectedCount])
    }
}
