import Foundation
import CoreNFC

/// AutumnNFC — NFC tag reading
/// Lets users scan product tags for info lookup via Autumn
@available(iOS 13.0, *)
public final class AutumnNFC: NSObject, NFCNDEFReaderSessionDelegate, Sendable {
    public static let shared = AutumnNFC()
    public var onTagRead: ((String) -> Void)?
    private var nfcSession: NFCNDEFReaderSession?

    public override init() { super.init() }

    public func startScanning(prompt: String = "Hold your iPhone near the tag") {
        guard NFCNDEFReaderSession.readingAvailable else { return }
        nfcSession          = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
        nfcSession?.alertMessage = prompt
        nfcSession?.begin()
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {}

    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        var result = ""
        for message in messages {
            for record in message.records {
                if let text = String(data: record.payload, encoding: .utf8) {
                    result += text + " "
                }
            }
        }
        if !result.isEmpty { onTagRead?(result.trimmingCharacters(in: .whitespaces)) }
    }
}
