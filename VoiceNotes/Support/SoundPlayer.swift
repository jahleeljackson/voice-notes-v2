import AppKit
import Foundation

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var playing: NSSound?

    func playStart() {
        play(named: "start")
    }

    func playStop() {
        play(named: "stop")
    }

    private func play(named name: String) {
        guard AppSettings.shared.soundsEnabled else { return }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        playing = sound
        sound.play()
    }
}
