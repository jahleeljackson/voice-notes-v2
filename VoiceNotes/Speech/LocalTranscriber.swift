import AVFoundation
import Foundation
import Speech

final class LocalTranscriber {
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var lastText = ""
    private var stopped = false
    var onPartial: ((String) -> Void)?

    init() {
        let current = SFSpeechRecognizer()
        if current?.supportsOnDeviceRecognition == true {
            recognizer = current
        } else {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
        }
    }

    var onDeviceAvailable: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func warmUp() {
        _ = recognizer?.isAvailable
        _ = recognizer?.supportsOnDeviceRecognition
    }

    func start() throws {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw DictationError.onDeviceUnavailable
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw DictationError.speechDenied
        }
        cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request
        lock.lock()
        lastText = ""
        stopped = false
        lock.unlock()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                self.lock.lock()
                self.lastText = text
                self.lock.unlock()
                let partial = text
                DispatchQueue.main.async { [weak self] in
                    self?.onPartial?(partial)
                }
            }
            if result?.isFinal == true || error != nil {
                self.lock.lock()
                self.stopped = true
                self.lock.unlock()
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func finish() async throws -> String {
        request?.endAudio()
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let (done, text) = snapshot()
            if done {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        task?.finish()
        return snapshot().text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snapshot() -> (done: Bool, text: String) {
        lock.lock()
        defer { lock.unlock() }
        return (stopped, lastText)
    }

    func cancel() {
        task?.cancel()
        request = nil
        task = nil
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
