import Foundation

@main
enum LogicCheckMain {
    static func main() {
        do {
            try VoiceNotesLogicChecks.runAll()
            print("logic checks passed")
        } catch {
            fputs("logic checks failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
