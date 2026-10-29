import Foundation

enum DictationError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case onDeviceUnavailable
    case missingAPIKey
    case openaiUnreachable
    case cleanupFailed(String)
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Allow microphone access to record."
        case .speechDenied:
            return "Allow speech recognition to transcribe on this Mac."
        case .onDeviceUnavailable:
            return "On-device speech recognition isn't available on this Mac."
        case .missingAPIKey:
            return "Add an OpenAI API key in Settings. The raw note was saved."
        case .openaiUnreachable:
            return "Couldn't reach OpenAI."
        case .cleanupFailed(let message):
            return message
        case .keychain(let message):
            return message
        }
    }
}

struct LogicCheckError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
