import Foundation

enum TranscriptionMode: String, Codable, CaseIterable, Equatable {
    case cleaned
    case raw

    var title: String {
        switch self {
        case .cleaned: return "Cleaned"
        case .raw: return "Raw"
        }
    }
}
