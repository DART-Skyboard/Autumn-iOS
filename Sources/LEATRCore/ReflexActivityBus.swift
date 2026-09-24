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
    fileprivate static let toolNotificationName = Notification.Name("LeatrReflexTool")
    fileprivate static let mathOpNotificationName = Notification.Name("LeatrReflexMathOp")

    /// Post a real pipeline stage. Safe to call from any thread/actor.
    public static func fire(_ stage: ReflexStage) {
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: ["stage": stage.rawValue])
    }

    /// Post the specific Nature Tool actually routed for this message
    /// (e.g. "Maze", "Puzzle") — matched against the mind map's own Nature
    /// Tools node text, same node names shown in Ash Canvas.
    public static func fireTool(_ toolName: String) {
        NotificationCenter.default.post(name: toolNotificationName, object: nil, userInfo: ["tool": toolName])
    }

    /// Post the specific math operation actually evaluated (e.g.
    /// "Multiplication"), when MathOOO genuinely performs one — matches
    /// the mind map's own PEMDAS node text under Natural Order of
    /// Operations.
    public static func fireMathOp(_ opName: String) {
        NotificationCenter.default.post(name: mathOpNotificationName, object: nil, userInfo: ["op": opName])
    }
}
