import SwiftUI

struct HistoryView: View {
    private var store = NoteStore.shared
    @State private var query = ""
    @State private var selection: UUID?

    private var model: AppModel { .shared }

    private var filtered: [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.notes }
        return store.notes.filter { note in
            note.rawText.localizedCaseInsensitiveContains(trimmed)
                || (note.cleanedText?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var selectedNote: Note? {
        if let selection, let match = store.notes.first(where: { $0.id == selection }) {
            return match
        }
        return filtered.first
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if store.notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "waveform",
                        description: Text("Finished recordings are kept here.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filtered, selection: $selection) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.displayText)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Text(note.mode.title)
                                if note.cleanupFailed {
                                    Text("Cleanup failed")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .tag(note.id)
                        .contextMenu {
                            noteActions(note)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .navigationTitle("Notes")
        } detail: {
            if let note = selectedNote {
                NoteDetail(
                    note: note,
                    onCopy: { model.copy(note) },
                    onPaste: { model.pasteAgain(note) },
                    onDelete: { delete(note) }
                )
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "note.text")
            }
        }
        .searchable(text: $query, prompt: "Search notes")
    }

    @ViewBuilder
    private func noteActions(_ note: Note) -> some View {
        Button("Copy") { model.copy(note) }
        Button("Paste") { model.pasteAgain(note) }
        Button("Delete", role: .destructive) { delete(note) }
    }

    private func delete(_ note: Note) {
        if selection == note.id {
            selection = nil
        }
        model.delete(note)
    }
}

private struct NoteDetail: View {
    let note: Note
    var onCopy: () -> Void
    var onPaste: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(note.createdAt.formatted(date: .complete, time: .shortened))
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0fs", note.duration))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label(note.mode.title, systemImage: note.mode == .cleaned ? "sparkles" : "text.quote")
                if note.didPaste {
                    Label("Pasted", systemImage: "doc.on.clipboard")
                }
                if note.cleanupFailed {
                    Label("Cleanup failed", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            ScrollView {
                Text(note.displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if note.mode == .cleaned, let cleaned = note.cleanedText, !cleaned.isEmpty, cleaned != note.rawText {
                DisclosureGroup("Original transcript") {
                    Text(note.rawText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                }
            }

            HStack(spacing: 8) {
                actionButton("Copy", action: onCopy)
                actionButton("Paste Into Focused App", action: onPaste)
                Spacer()
                actionButton("Delete", action: onDelete)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Note")
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
