import SwiftUI
import AppKit
import Vision

struct EditorView: View {
    @EnvironmentObject private var state: EditorState
    @State private var exportFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(onCopy: copyToClipboard,
                          onSave: saveToFile,
                          onPaste: pasteImage,
                          onUndo: { state.undo() },
                          onRedo: { state.redo() },
                          onCopyText: copyRecognizedText,
                          makeDragProvider: makeDragProvider)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)

            Divider()

            HStack(spacing: 0) {
                EditorCanvas()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EditorBackdrop())

                Divider()

                EditorSidebar()
                    .frame(width: 300)
                    .background(.regularMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            if let exportFeedback {
                Text(exportFeedback)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            let shift = press.modifiers.contains(.shift)
            let ch = press.key.character
            switch ch {
            case "c": copyToClipboard(); return .handled
            case "s": saveToFile();      return .handled
            case "v": pasteImage();      return .handled
            case "z":
                if shift { state.redo() } else { state.undo() }
                return .handled
            case "y": state.redo(); return .handled
            case "a": // ⌘⇧A → bring to front, ⌘A → ignore (let users still select-all in text fields)
                if shift { state.bringToFront(); return .handled }
                return .ignored
            case "b":
                if shift { state.sendToBack(); return .handled }
                return .ignored
            case "]": state.bringForward();  return .handled
            case "[": state.sendBackward();  return .handled
            default: break
            }
        }
        switch press.key {
        case .delete, .deleteForward:
            if state.selectedAnnotationID != nil { state.deleteSelected(); return .handled }
        case .escape:
            state.selectedAnnotationID = nil
            state.tool = .select
            state.pendingCrop = nil
            return .handled
        default: break
        }
        for tool in Tool.allCases where tool.keyboardShortcut.character == press.key.character {
            state.tool = tool
            state.selectedAnnotationID = nil
            return .handled
        }
        return .ignored
    }

    private func copyToClipboard() {
        Task {
            let image = ImageComposer.compose(state: state)
            Exporter.copyToClipboard(image)
            await showFeedback("Copied to clipboard")
        }
    }

    private func saveToFile() {
        let image = ImageComposer.compose(state: state)
        let panel = NSSavePanel()
        panel.title = "Save Screenshot"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snapture-\(timestamp()).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                if Exporter.write(image, to: url) {
                    await showFeedback("Saved to \(url.lastPathComponent)")
                } else {
                    await showFeedback("Save failed — check folder permissions")
                }
            }
        }
    }

    private func pasteImage() {
        let canvasSize = CGSize(
            width: state.croppedImage.size.width + state.padding * 2,
            height: state.croppedImage.size.height + state.padding * 2
        )
        if state.pasteImageFromClipboard(intoCanvasSize: canvasSize) {
            state.tool = .select
            Task { await showFeedback("Pasted image layer") }
        } else {
            Task { await showFeedback("No image on clipboard") }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /// OCR the screenshot (Vision) and copy the recognized text to the clipboard.
    private func copyRecognizedText() {
        guard let cg = state.croppedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task {
            let text = await Self.recognizeText(in: cg)
            if text.isEmpty {
                await showFeedback("No text found")
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                await showFeedback("Copied \(text.count) characters of text")
            }
        }
    }

    private nonisolated static func recognizeText(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }

    /// Compose the current state to a temp PNG and return a provider so the
    /// user can drag the result straight into Slack / Figma / Finder.
    private func makeDragProvider() -> NSItemProvider {
        let image = ImageComposer.compose(state: state)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snapture-\(timestamp()).png")
        if Exporter.write(image, to: url), let provider = NSItemProvider(contentsOf: url) {
            provider.suggestedName = url.lastPathComponent
            return provider
        }
        return NSItemProvider(object: image)
    }

    @MainActor
    private func showFeedback(_ message: String) async {
        withAnimation(.spring(duration: 0.25)) { exportFeedback = message }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        withAnimation(.easeOut(duration: 0.25)) { exportFeedback = nil }
    }
}

struct EditorBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            CheckerboardPattern().opacity(0.15)
        }
    }
}

struct EditorToolbar: View {
    @EnvironmentObject private var state: EditorState
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPaste: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopyText: () -> Void
    let makeDragProvider: () -> NSItemProvider

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Tool.allCases) { tool in
                    ToolButton(tool: tool)
                }
            }
            .padding(4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 2) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!state.canUndo)
                .help("Undo (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!state.canRedo)
                .help("Redo (⌘⇧Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button(action: onPaste) {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Paste image as layer (⌘V)")
                .keyboardShortcut("v", modifiers: .command)

                Button(action: onCopyText) {
                    Image(systemName: "text.viewfinder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Copy text in screenshot (OCR)")
            }
            .padding(4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            if state.tool == .crop, let _ = state.pendingCrop {
                Button("Apply Crop") {
                    if let rect = state.pendingCrop { state.applyCrop(rect: rect) }
                    state.tool = .select
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") { state.pendingCrop = nil }
                    .buttonStyle(.bordered)
            }

            // Drag this chip into Slack / Figma / Finder to export without saving.
            Label("Drag", systemImage: "hand.draw")
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
                .onDrag { makeDragProvider() }
                .help("Drag the composed image into another app")

            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("s", modifiers: .command)

            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)
        }
    }
}

struct ToolButton: View {
    @EnvironmentObject private var state: EditorState
    let tool: Tool

    var body: some View {
        Button {
            // Only write what actually changes — every @Published write
            // invalidates the whole observing view tree.
            if state.tool != tool { state.tool = tool }
            if tool != .select, state.selectedAnnotationID != nil { state.selectedAnnotationID = nil }
            if tool != .crop, state.pendingCrop != nil { state.pendingCrop = nil }
        } label: {
            Image(systemName: tool.systemImage)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(state.tool == tool ? Color.accentColor.opacity(0.25) : Color.clear)
                )
                .foregroundStyle(state.tool == tool ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) (\(String(tool.keyboardShortcut.character)))")
        .keyboardShortcut(tool.keyboardShortcut, modifiers: [])
    }
}
