import AppKit
import SwiftUI

// MARK: - Region outline

/// A thin, click-through border drawn around the recording region so the user
/// sees exactly what's being captured. It's a Snapture window, so it's excluded
/// from the capture and never appears in the GIF.
@MainActor
final class RegionOutlineWindow {
    private let window: NSWindow

    init(globalRect: NSRect) {
        // Sit just outside the region so the border doesn't cover recorded content.
        let frame = globalRect.insetBy(dx: -2, dy: -2)
        window = OverlayWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: RegionOutlineView())
    }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }
}

private struct RegionOutlineView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color.red.opacity(0.95), lineWidth: 2)
            .allowsHitTesting(false)
    }
}

// MARK: - Recording panel (options → recording)

/// A floating control shown after the region is chosen: first the quality
/// options, then the live timer + Stop button. One panel, swapped in place.
@MainActor
final class RecordingPanelController {
    private var window: OverlayWindow?
    private var screen: NSScreen?

    func showOptions(on screen: NSScreen, regionPoints: CGSize, retinaScale: CGFloat,
                     quality: Double,
                     onRecord: @escaping (Double) -> Void,
                     onCancel: @escaping () -> Void) {
        self.screen = screen
        let view = RecordingOptionsView(regionPoints: regionPoints, retinaScale: retinaScale,
                                        initialQuality: quality, onRecord: onRecord, onCancel: onCancel)
        present(AnyView(view), on: screen, makeKey: true)
    }

    func switchToRecording(startedAt: Date, onStop: @escaping () -> Void) {
        guard let screen = screen ?? NSScreen.main else { return }
        present(AnyView(RecordingTimerView(start: startedAt, onStop: onStop)), on: screen, makeKey: false)
    }

    /// Replace the Stop button with a "processing" indicator while the GIF encodes.
    func switchToProcessing() {
        guard let screen = screen ?? NSScreen.main else { return }
        present(AnyView(RecordingProcessingView()), on: screen, makeKey: false)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func present(_ view: AnyView, on screen: NSScreen, makeKey: Bool) {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 60 || size.height < 30 { size = NSSize(width: 360, height: 130) }

        let win = window ?? {
            let w = OverlayWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.level = .statusBar
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            return w
        }()
        win.contentView = host
        win.setContentSize(size)
        let vis = screen.visibleFrame
        win.setFrameOrigin(NSPoint(x: vis.midX - size.width / 2, y: vis.maxY - size.height - 16))
        if makeKey {
            // Non-activating: Return/Escape work in the options panel without
            // raising Snapture's windows over the region being recorded.
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        } else {
            win.orderFrontRegardless()
        }
        window = win
    }
}

private struct RecordingOptionsView: View {
    let regionPoints: CGSize
    let retinaScale: CGFloat
    let onRecord: (Double) -> Void
    let onCancel: () -> Void
    @State private var quality: Double

    init(regionPoints: CGSize, retinaScale: CGFloat, initialQuality: Double,
         onRecord: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.regionPoints = regionPoints
        self.retinaScale = retinaScale
        self.onRecord = onRecord
        self.onCancel = onCancel
        _quality = State(initialValue: initialQuality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text("Record GIF").font(.headline)
                Spacer()
                Text(dimsText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "photo").imageScale(.small).foregroundStyle(.secondary)
                    Slider(value: $quality, in: 0...1)
                    Text(qualityLabel).font(.caption.weight(.medium)).frame(width: 64, alignment: .trailing)
                }
                Text(estimateText)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button { onRecord(quality) } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }

    private var px: CGSize {
        GIFQuality.pixelSize(regionPoints: regionPoints, quality: quality, retinaScale: retinaScale)
    }
    private var dimsText: String { "\(Int(px.width))×\(Int(px.height)) · \(GIFQuality.fps(quality)) fps" }
    private var qualityLabel: String { quality < 0.34 ? "Smaller" : (quality < 0.7 ? "Balanced" : "Sharper") }
    private var estimateText: String {
        let r = GIFQuality.estimatedRange(regionPoints: regionPoints, quality: quality, retinaScale: retinaScale)
        return "≈ \(rate(r.low))–\(rate(r.high)) · depends on motion"
    }
    private func rate(_ bytesPerSec: Double) -> String {
        bytesPerSec >= 1_000_000
            ? String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
            : String(format: "%.0f KB/s", bytesPerSec / 1000)
    }
}

private struct RecordingProcessingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Processing recording…")
                .font(.system(.body).weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .fixedSize()
    }
}

private struct RecordingTimerView: View {
    let start: Date
    let onStop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)

            TimelineView(.periodic(from: start, by: 0.5)) { context in
                Text(timeString(context.date.timeIntervalSince(start)))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
            }

            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .fixedSize()
        .onAppear { pulse = true }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%01d:%02d", s / 60, s % 60)
    }
}
