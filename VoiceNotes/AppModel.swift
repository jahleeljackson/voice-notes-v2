import AppKit
import AVFoundation
import Foundation
import os
import Speech
import SwiftUI

enum SessionPhase: Equatable {
    case idle
    case recording(RecordingKind)
    case processing(String)
    case message(String)
}

enum RecordingKind: String, Equatable {
    case push
    case handsFree
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private let logger = Logger(subsystem: "app.voicenotes.local", category: "dictation")
    private let hotkeys = HotkeyMonitor()
    private let recorder = Recorder()
    private let transcriber = LocalTranscriber()
    private let cleaner = OpenAICleaner()
    private let pasteController = PasteController()
    private var hud: RecordingHUDController?
    private let notes = NoteStore.shared
    private var lastExternalApp: NSRunningApplication?
    private var focusedApp: NSRunningApplication?
    private var session = UUID()
    private var startedAt = Date()
    private var hideToken = 0
    private var started = false
    private var didShowPermissionAlert = false
    private var permissionAlertArmed = false
    private var activationCount = 0

    var phase: SessionPhase = .idle
    var partialText = ""
    var audioLevel: Float = 0
    var microphoneGranted = false
    var speechGranted = false
    var accessibilityGranted = false
    var hotkeysActive = false
    var rebind: ShortcutAction?

    var settings: AppSettings { .shared }

    var statusSymbol: String {
        switch phase {
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        default: return "waveform"
        }
    }

    var isSessionActive: Bool {
        switch phase {
        case .recording, .processing: return true
        default: return false
        }
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        hotkeys.onEffects = { effects in
            Task { @MainActor in
                AppModel.shared.perform(effects)
            }
        }
        hotkeys.onRebind = { action, combo in
            Task { @MainActor in
                AppModel.shared.applyRebind(action, combo)
            }
        }
        hotkeys.onRebindCancelled = {
            Task { @MainActor in
                AppModel.shared.cancelRebind()
            }
        }
        watchApplications()
        installHUD()
        if CommandLine.arguments.contains("--smoke-ui") {
            showSmokeInterface()
            return
        }
        requestPermissions()
        transcriber.warmUp()
        hotkeys.start()
        refreshPermissions()
    }

    func shutdown() {
        hotkeys.stop()
    }

    func perform(_ effects: [HotkeyStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .startPush:
                begin(.push)
            case .startHandsFree:
                begin(.handsFree)
            case .finish:
                finish()
            case .cancelSession:
                cancelSession()
            case .deleteLast:
                deleteLastNote()
            case .scheduleArm, .cancelArm, .scheduleTapWindow, .cancelTapWindow:
                break
            }
        }
    }

    func beginRebind(_ action: ShortcutAction) {
        rebind = action
        ShortcutSync.box.updateRebind(action)
    }

    func cancelRebind() {
        rebind = nil
        ShortcutSync.box.updateRebind(nil)
    }

    func applyRebind(_ action: ShortcutAction, _ combo: KeyCombo) {
        var shortcuts = settings.shortcuts
        switch action {
        case .push: shortcuts.push = combo
        case .press: shortcuts.press = combo
        case .cancel: shortcuts.cancel = combo
        case .delete: shortcuts.delete = combo
        }
        settings.shortcuts = shortcuts
        cancelRebind()
    }

    func useDoubleTapPress() {
        var shortcuts = settings.shortcuts
        shortcuts.press = nil
        settings.shortcuts = shortcuts
    }

    func toggleMode() {
        settings.mode = settings.mode == .cleaned ? .raw : .cleaned
    }

    func deleteLastNote() {
        guard notes.deleteNewest() else {
            if !isSessionActive { flash("No note to delete") }
            return
        }
        if !isSessionActive { flash("Deleted last note") }
    }

    func delete(_ note: Note) {
        notes.delete(id: note.id)
    }

    func pasteLastNote() {
        guard let note = notes.newest() else {
            flash("No note to paste")
            return
        }
        pasteAgain(note)
    }

    func pasteAgain(_ note: Note) {
        let text = note.displayText
        let app = captureFocus()
        Task {
            await pasteController.paste(text, to: app)
        }
    }

    func copy(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.displayText, forType: .string)
    }

    func noteBecameActive() {
        activationCount += 1
        if activationCount > 1 {
            permissionAlertArmed = true
        }
        refreshPermissions()
    }

    func requestPermissions() {
        let needsKeyTrust = !Permissions.accessibilityTrusted || !Permissions.inputMonitoringTrusted
        if needsKeyTrust {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
        _ = Permissions.promptAccessibility()
        _ = Permissions.promptInputMonitoring()
        AVAudioApplication.requestRecordPermission { _ in
            Task { @MainActor in
                AppModel.shared.refreshPermissions()
            }
        }
        SFSpeechRecognizer.requestAuthorization { _ in
            Task { @MainActor in
                AppModel.shared.refreshPermissions()
                AppModel.shared.transcriber.warmUp()
            }
        }
        refreshPermissions()
    }

    func refreshPermissions() {
        microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityGranted = Permissions.accessibilityTrusted
        let listen = Permissions.inputMonitoringTrusted
        if !hotkeys.isInstalled && started && !CommandLine.arguments.contains("--smoke-ui") {
            hotkeys.start()
        }
        hotkeysActive = hotkeys.isInstalled
        if accessibilityGranted && listen && hotkeys.isInstalled {
            NSApp.setActivationPolicy(.accessory)
        }
        let micDecided = AVAudioApplication.shared.recordPermission != .undetermined
        let speechDecided = SFSpeechRecognizer.authorizationStatus() != .notDetermined
        if permissionAlertArmed && micDecided && speechDecided && (!accessibilityGranted || !listen || !hotkeys.isInstalled) {
            presentMissingPermissionsIfNeeded()
        }
    }

    private func presentMissingPermissionsIfNeeded() {
        guard !didShowPermissionAlert else { return }
        var missing: [String] = []
        if !microphoneGranted { missing.append("Microphone") }
        if !speechGranted { missing.append("Speech Recognition") }
        if !accessibilityGranted { missing.append("Accessibility") }
        if !hotkeys.isInstalled { missing.append("Input Monitoring") }
        guard !missing.isEmpty else { return }
        didShowPermissionAlert = true
        let alert = NSAlert()
        alert.messageText = "Voice Notes can’t hear the right Option key yet"
        alert.informativeText = "Turn on \(missing.joined(separator: ", ")) for Voice Notes. After Accessibility and Input Monitoring are on, quit the app and open it again. Hold the right Option key while you speak, then release it to paste."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Permissions.open(accessibilityGranted ? "ListenEvent" : "Accessibility")
    }

    func openNotes() {
        NSApp.activate()
    }

    private func begin(_ kind: RecordingKind) {
        guard case .idle = phase else { return }
        let token = UUID()
        session = token
        do {
            guard microphoneGranted || AVAudioApplication.shared.recordPermission == .granted else {
                throw DictationError.microphoneDenied
            }
            guard speechGranted || SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw DictationError.speechDenied
            }
            transcriber.onPartial = { text in
                Task { @MainActor in
                    guard AppModel.shared.session == token else { return }
                    AppModel.shared.partialText = text
                }
            }
            try transcriber.start()
            try recorder.start { [weak self] buffer in
                self?.transcriber.append(buffer)
            } onLevel: { level in
                Task { @MainActor in
                    guard AppModel.shared.session == token else { return }
                    AppModel.shared.audioLevel = level
                }
            }
        } catch {
            recorder.stop()
            transcriber.cancel()
            hotkeys.forceIdle()
            logger.error("Recording failed: \(error.localizedDescription, privacy: .public)")
            flash(error.localizedDescription)
            return
        }
        focusedApp = captureFocus()
        startedAt = Date()
        partialText = ""
        audioLevel = 0
        phase = .recording(kind)
        SoundPlayer.shared.playStart()
        showHUD()
    }

    private func finish() {
        guard case .recording = phase else {
            hotkeys.noteSessionEnded()
            return
        }
        let token = session
        let duration = Date().timeIntervalSince(startedAt)
        let mode = settings.mode
        let autoPaste = settings.autoPaste
        let modelName = settings.model
        let focus = focusedApp
        phase = .processing("Transcribing…")
        showHUD()
        SoundPlayer.shared.playStop()
        recorder.stop()
        Task {
            let raw: String
            do {
                raw = try await transcriber.finish()
            } catch {
                abandon(token, message: error.localizedDescription)
                return
            }
            guard token == session else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                abandon(token, message: "Didn't catch anything.")
                return
            }

            var cleaned: String?
            var output = trimmed
            if mode == .cleaned {
                phase = .processing("Cleaning…")
                do {
                    guard let apiKey = KeychainStore.load(), !apiKey.isEmpty else {
                        throw DictationError.missingAPIKey
                    }
                    cleaned = try await cleaner.clean(
                        transcript: trimmed,
                        apiKey: apiKey,
                        model: modelName
                    )
                    output = cleaned ?? trimmed
                } catch {
                    let unreachable: Bool
                    if case .openaiUnreachable = error as? DictationError {
                        unreachable = true
                    } else {
                        unreachable = false
                    }
                    saveNote(
                        duration: duration,
                        mode: mode,
                        raw: trimmed,
                        cleaned: nil,
                        didPaste: false,
                        cleanupFailed: true
                    )
                    if unreachable {
                        if autoPaste {
                            await pasteController.paste(trimmed, to: focus)
                            if token == session {
                                markNewestNotePasted()
                            }
                        }
                        guard token == session else { return }
                        phase = .idle
                        partialText = ""
                        hideHUD()
                        hotkeys.noteSessionEnded()
                        alertOpenAIUnreachable(pasted: autoPaste)
                        return
                    }
                    abandon(token, message: error.localizedDescription)
                    return
                }
            }

            guard token == session else { return }
            saveNote(
                duration: duration,
                mode: mode,
                raw: trimmed,
                cleaned: cleaned,
                didPaste: false,
                cleanupFailed: false
            )
            if autoPaste {
                await pasteController.paste(output, to: focus)
                if token == session {
                    markNewestNotePasted()
                }
            }
            guard token == session else { return }
            phase = .idle
            partialText = ""
            hideHUD()
            hotkeys.noteSessionEnded()
        }
    }

    private func cancelSession() {
        session = UUID()
        recorder.stop()
        transcriber.cancel()
        partialText = ""
        audioLevel = 0
        phase = .idle
        hideHUD()
    }

    private func abandon(_ token: UUID, message: String) {
        guard token == session else { return }
        recorder.stop()
        transcriber.cancel()
        hotkeys.noteSessionEnded()
        partialText = ""
        flash(message)
    }

    private func markNewestNotePasted() {
        notes.markNewestPasted()
    }

    private func saveNote(
        duration: Double,
        mode: TranscriptionMode,
        raw: String,
        cleaned: String?,
        didPaste: Bool,
        cleanupFailed: Bool
    ) {
        notes.insert(Note(
            duration: duration,
            mode: mode,
            rawText: raw,
            cleanedText: cleaned,
            didPaste: didPaste,
            cleanupFailed: cleanupFailed
        ))
    }

    private func captureFocus() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = front
            return front
        }
        return lastExternalApp
    }

    private func watchApplications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                AppModel.shared.lastExternalApp = app
            }
        }
    }

    private func alertOpenAIUnreachable(pasted: Bool) {
        let alert = NSAlert()
        alert.messageText = "Couldn't reach OpenAI"
        alert.informativeText = pasted
            ? "The raw transcript was pasted instead."
            : "The raw transcript was saved. Auto-paste is off, so it was not pasted."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    private func flash(_ text: String) {
        hideToken += 1
        let token = hideToken
        phase = .message(text)
        showHUD()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard token == hideToken, case .message = phase else { return }
            phase = .idle
            hideHUD()
        }
    }

    private func installHUD() {
        if hud == nil {
            hud = RecordingHUDController(model: self)
        }
    }

    private func showHUD() {
        installHUD()
        hud?.show()
    }

    private func hideHUD() {
        hud?.hide()
    }

    private func showSmokeInterface() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        phase = .recording(.handsFree)
        partialText = "Buy milk, eggs, and bread tomorrow"
        audioLevel = 0.62
        showHUD()
        if !notes.notes.contains(where: { $0.rawText.hasPrefix("um buy milk") }) {
            notes.insert(Note(
                createdAt: .now,
                duration: 4,
                mode: .cleaned,
                rawText: "um buy milk eggs and bread tomorrow actually sourdough",
                cleanedText: "Buy milk, eggs, and sourdough tomorrow.",
                didPaste: true,
                cleanupFailed: false
            ))
        }

        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let notesWindow = NSWindow(
            contentRect: NSRect(x: visible.minX + 40, y: visible.minY + 80, width: min(760, visible.width * 0.55), height: min(520, visible.height - 120)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        notesWindow.title = "Notes"
        notesWindow.contentView = NSHostingView(rootView: HistoryView())
        notesWindow.makeKeyAndOrderFront(nil)

        let settingsWindow = NSWindow(
            contentRect: NSRect(
                x: visible.maxX - min(480, visible.width * 0.38) - 24,
                y: visible.minY + 80,
                width: min(460, visible.width * 0.36),
                height: min(620, visible.height - 120)
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Settings"
        settingsWindow.contentView = NSHostingView(rootView: SettingsView())
        settingsWindow.makeKeyAndOrderFront(nil)
        smokeWindows = [notesWindow, settingsWindow]
        writeSmokePreviews()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [notesWindow, settingsWindow] in
            self.captureWindow(notesWindow, name: "notes-window")
            self.captureWindow(settingsWindow, name: "settings-window")
            self.hud?.capture(name: "hud-window")
        }
    }

    private var smokeWindows: [NSWindow] = []

    private func captureWindow(_ window: NSWindow, name: String) {
        guard let view = window.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: "/tmp/voicenotes-smoke/\(name).png")
        try? png.write(to: url)
    }

    private func writeSmokePreviews() {
        let directory = URL(fileURLWithPath: "/tmp/voicenotes-smoke")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savePreview(HistoryView().frame(width: 860, height: 560), name: "notes-view", to: directory)
        savePreview(SettingsView().frame(width: 460, height: 720), name: "settings-view", to: directory)
        savePreview(RecordingHUDView(model: self).padding(24), name: "hud-view", to: directory)
        savePreview(
            VStack(alignment: .leading, spacing: 8) {
                Text("Hold Right ⌥ to record")
                Text("Double-tap Right ⌥ to start, tap again to stop")
                Text("Esc cancels")
                Text("Transcription: \(settings.mode.title)")
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
            .background(.white)
            .foregroundStyle(.black),
            name: "menu-view",
            to: directory
        )
    }

    private func savePreview<V: View>(_ view: V, name: String, to directory: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
