import Foundation
import Intents

/// AutumnSiriHandler — SiriKit intent handler
/// Allows "Hey Siri, ask Autumn..." voice commands
/// Routes Siri requests into Autumn's LEATR reasoning engine
@available(iOS 14.0, *)
public final class AutumnSiriHandler: NSObject, INSendMessageIntentHandling, Sendable {
    public static let shared = AutumnSiriHandler()
    public var onSiriQuery: ((String) -> Void)?

    public override init() { super.init() }

    // MARK: - INSendMessageIntentHandling
    public func handle(intent: INSendMessageIntent,
        completion: @escaping (INSendMessageIntentResponse) -> Void) {
        let query = intent.content ?? ""
        onSiriQuery?(query)
        completion(INSendMessageIntentResponse(code: .success, userActivity: nil))
    }

    public func confirm(intent: INSendMessageIntent,
        completion: @escaping (INSendMessageIntentResponse) -> Void) {
        completion(INSendMessageIntentResponse(code: .ready, userActivity: nil))
    }

    public func resolveRecipients(for intent: INSendMessageIntent,
        with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void) {
        completion([.notRequired()])
    }
}
