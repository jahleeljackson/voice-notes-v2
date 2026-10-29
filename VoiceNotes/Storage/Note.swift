import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var duration: Double
    var modeRaw: String
    var rawText: String
    var cleanedText: String?
    var didPaste: Bool
    var cleanupFailed: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        duration: Double,
        mode: TranscriptionMode,
        rawText: String,
        cleanedText: String?,
        didPaste: Bool,
        cleanupFailed: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.modeRaw = mode.rawValue
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.didPaste = didPaste
        self.cleanupFailed = cleanupFailed
    }

    var mode: TranscriptionMode {
        TranscriptionMode(rawValue: modeRaw) ?? .raw
    }

    var displayText: String {
        if mode == .cleaned, let cleanedText, !cleanedText.isEmpty, !cleanupFailed {
            return cleanedText
        }
        return rawText
    }
}

@MainActor
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    private let fileURL: URL

    private init() {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("VoiceNotes", isDirectory: true)
        let folder = directory ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoiceNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("notes.json")
        load()
    }

    func insert(_ note: Note) {
        notes.insert(note, at: 0)
        notes.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func deleteNewest() -> Bool {
        guard let newest = notes.max(by: { $0.createdAt < $1.createdAt }) else { return false }
        delete(id: newest.id)
        return true
    }

    func newest() -> Note? {
        notes.max(by: { $0.createdAt < $1.createdAt })
    }

    func markNewestPasted() {
        guard let newest = newest(), let index = notes.firstIndex(where: { $0.id == newest.id }) else { return }
        notes[index].didPaste = true
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Voice Notes couldn't save notes: \(error.localizedDescription)")
        }
    }
}
