import AppKit
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingHUDController {
    private let panel: NonActivatingPanel

    init(model: AppModel) {
        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 112),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.title = "Voice Notes Recording"
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: RecordingHUDView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 112)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 28))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func capture(name: String) {
        guard let view = panel.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "/tmp/voicenotes-smoke/\(name).png"))
    }
}

struct RecordingHUDView: View {
    var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            indicator
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    Spacer(minLength: 8)
                    Text(model.settings.mode.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                if showsCancel {
                    Text(model.settings.shortcuts.cancelLegend)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 400, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }

    private var title: String {
        switch model.phase {
        case .recording(.push): return "Listening"
        case .recording(.handsFree): return "Hands-free"
        case .processing(let status): return status
        case .message: return "Voice Notes"
        case .idle: return "Voice Notes"
        }
    }

    private var detail: String {
        switch model.phase {
        case .message(let text):
            return text
        case .processing:
            return model.partialText.isEmpty ? "Working on what you said" : model.partialText
        case .recording:
            return model.partialText.isEmpty ? "Speak now" : model.partialText
        case .idle:
            return ""
        }
    }

    private var showsCancel: Bool {
        switch model.phase {
        case .recording, .processing: return true
        default: return false
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if case .recording = model.phase {
            Waveform(level: model.audioLevel)
                .frame(width: 28, height: 28)
        } else if case .processing = model.phase {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
    }
}

private struct Waveform: View {
    var level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: 3, height: height(index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func height(_ index: Int) -> CGFloat {
        let weights: [CGFloat] = [0.45, 0.78, 1, 0.7, 0.42]
        return 5 + CGFloat(level) * 22 * weights[index]
    }
}
