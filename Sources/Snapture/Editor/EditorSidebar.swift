import SwiftUI

struct EditorSidebar: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if state.selectedAnnotation != nil {
                    AnnotationPropertiesPanel()
                } else {
                    CanvasPropertiesPanel()
                }
            }
            .padding(16)
        }
    }
}

struct CanvasPropertiesPanel: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        SectionHeader("Background")
        BackgroundPickerView()

        SectionHeader("Window frame")
        Picker("", selection: Binding(
            get: { state.frameStyle },
            set: { v in state.snapshot(); state.frameStyle = v }
        )) {
            ForEach(FrameStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        SectionHeader("Frame")
        SliderRow(label: "Padding", value: $state.padding, range: 0...160, step: 4, unit: "pt",
                  onEditingChanged: { editing in if editing { state.snapshot() } })
        SliderRow(label: "Corner radius", value: $state.cornerRadius, range: 0...40, step: 1, unit: "pt",
                  onEditingChanged: { editing in if editing { state.snapshot() } })

        SectionHeader("Drop shadow")
        Toggle("Enabled", isOn: Binding(
            get: { state.shadowEnabled },
            set: { v in state.snapshot(); state.shadowEnabled = v }
        ))
        if state.shadowEnabled {
            SliderRow(label: "Radius",  value: $state.shadowRadius, range: 0...80, step: 1, unit: "pt",
                      onEditingChanged: { e in if e { state.snapshot() } })
            SliderRow(label: "Opacity", value: Binding(
                get: { CGFloat(state.shadowOpacity) },
                set: { state.shadowOpacity = Double($0) }
            ), range: 0...1, step: 0.05, unit: "",
                      onEditingChanged: { e in if e { state.snapshot() } })
        }

        SectionHeader("Image")
        Button {
            state.resetCrop()
            state.snapshot()
            state.annotations = []
            state.selectedAnnotationID = nil
        } label: {
            Label("Reset crop & annotations", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }
}

struct BackgroundPickerView: View {
    @EnvironmentObject private var state: EditorState
    @State private var customColor: Color = .indigo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                ForEach(BackgroundPresets.all) { preset in
                    Button {
                        state.snapshot()
                        state.background = preset.style
                    } label: {
                        ZStack {
                            // The transparent style renders as Color.clear now,
                            // so the "None" swatch shows the checkerboard itself.
                            if preset.style == .transparent {
                                CheckerboardPattern()
                                    .frame(width: 56, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            preset.style.view()
                                .frame(width: 56, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(state.background == preset.style ? Color.accentColor : Color.black.opacity(0.15), lineWidth: state.background == preset.style ? 2 : 1)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }

            HStack {
                ColorPicker("Solid", selection: $customColor)
                    .labelsHidden()
                Button("Use") {
                    state.snapshot()
                    state.background = .solid(CodableColor(customColor))
                }
                    .buttonStyle(.bordered)
                Spacer()
            }
        }
    }
}

struct AnnotationPropertiesPanel: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        if let ann = state.selectedAnnotation {
            // Header
            HStack {
                Label(ann.kind.displayName, systemImage: ann.kind.systemImage)
                    .font(.headline)
                Spacer()
                Button {
                    state.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete (⌫)")
                // Suppressed while the text editor is focused so Backspace edits
                // the text instead of deleting the annotation being typed into.
                .keyShortcut(.delete, active: !state.isEditingText)
            }

            // Z-order controls — show when there's more than one layer
            if state.annotations.count > 1 {
                ZOrderControls()
            }

            Divider()

            // Per-kind properties
            switch ann.kind {
            case .rectangle, .ellipse, .triangle:
                shapeControls(ann)
            case .arrow, .line, .pen:
                arrowControls(ann)
            case .counter:
                counterControls(ann)
            case .text:
                textControls(ann)
            case .blur:
                blurControls(ann)
            case .highlight:
                highlightControls(ann)
            case .image:
                imageControls(ann)
            case .magnifier:
                magnifierControls(ann)
            }

            // Per-layer drop shadow
            if ann.kind.supportsShadow {
                Divider()
                LayerShadowControls(annotation: ann)
            }

            Divider()
            positionControls(ann)
        }
    }

    @ViewBuilder
    private func shapeControls(_ ann: Annotation) -> some View {
        ColorRow(title: "Stroke", color: Binding(
            get: { ann.color.swiftUI },
            set: { c in state.snapshot(); state.updateSelected { $0.color = CodableColor(c) } }
        ))
        ColorRow(title: "Fill", color: Binding(
            get: { ann.fillColor.swiftUI },
            set: { c in state.snapshot(); state.updateSelected { $0.fillColor = CodableColor(c) } }
        ))
        SliderRow(label: "Fill opacity", value: Binding(
            get: { CGFloat(ann.fillOpacity) },
            set: { v in state.updateSelected { $0.fillOpacity = Double(v) } }
        ), range: 0...1, step: 0.05, unit: "",
                  onEditingChanged: { e in if e { state.snapshot() } })
        SliderRow(label: "Stroke width", value: Binding(
            get: { ann.strokeWidth },
            set: { v in state.updateSelected { $0.strokeWidth = v } }
        ), range: 1...20, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
        // Corner radius only makes sense for rectangles.
        if ann.kind == .rectangle {
            SliderRow(label: "Corner radius", value: Binding(
                get: { ann.cornerRadius },
                set: { v in state.updateSelected { $0.cornerRadius = v } }
            ), range: 0...40, step: 1, unit: "pt",
                      onEditingChanged: { e in if e { state.snapshot() } })
        }
    }

    @ViewBuilder
    private func magnifierControls(_ ann: Annotation) -> some View {
        SliderRow(label: "Zoom", value: Binding(
            get: { ann.zoom },
            set: { v in state.updateSelected { $0.zoom = v } }
        ), range: 1.2...8.0, step: 0.1, unit: "×",
                  onEditingChanged: { e in if e { state.snapshot() } })
        ColorRow(title: "Ring", color: Binding(
            get: { ann.color.swiftUI },
            set: { c in state.snapshot(); state.updateSelected { $0.color = CodableColor(c) } }
        ))
        SliderRow(label: "Ring width", value: Binding(
            get: { ann.strokeWidth },
            set: { v in state.updateSelected { $0.strokeWidth = v } }
        ), range: 0...12, step: 0.5, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
    }

    @ViewBuilder
    private func arrowControls(_ ann: Annotation) -> some View {
        ColorRow(title: "Color", color: Binding(
            get: { ann.color.swiftUI },
            set: { c in state.snapshot(); state.updateSelected { $0.color = CodableColor(c) } }
        ))
        SliderRow(label: "Thickness", value: Binding(
            get: { ann.strokeWidth },
            set: { v in state.updateSelected { $0.strokeWidth = v } }
        ), range: 1...18, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
    }

    @ViewBuilder
    private func textControls(_ ann: Annotation) -> some View {
        ColorRow(title: "Color", color: Binding(
            get: { ann.color.swiftUI },
            set: { c in state.snapshot(); state.updateSelected { $0.color = CodableColor(c) } }
        ))
        SliderRow(label: "Font size", value: Binding(
            get: { ann.fontSize },
            set: { v in state.updateSelected { $0.fontSize = v } }
        ), range: 8...96, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
        HStack {
            Text("Text")
            TextField("", text: Binding(
                get: { ann.text },
                set: { t in state.updateSelected { $0.text = t } }
            ))
            .textFieldStyle(.roundedBorder)
            .onSubmit { state.snapshot() }
        }
    }

    @ViewBuilder
    private func blurControls(_ ann: Annotation) -> some View {
        Toggle("Pixelate (mosaic)", isOn: Binding(
            get: { ann.pixelate },
            set: { v in state.snapshot(); state.updateSelected { $0.pixelate = v } }
        ))
        SliderRow(label: "Strength", value: Binding(
            get: { ann.blurRadius },
            set: { v in state.updateSelected { $0.blurRadius = v } }
        ), range: 2...60, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
    }

    @ViewBuilder
    private func counterControls(_ ann: Annotation) -> some View {
        ColorRow(title: "Badge", color: Binding(
            get: { ann.color.swiftUI },
            set: { c in state.snapshot(); state.updateSelected { $0.color = CodableColor(c) } }
        ))
        Stepper("Number: \(ann.counterValue)", value: Binding(
            get: { ann.counterValue },
            set: { v in state.updateSelected { $0.counterValue = max(0, v) } }
        ), in: 0...999)
        SliderRow(label: "Size", value: Binding(
            get: { ann.frame.width },
            set: { v in
                state.updateSelected { a in
                    let center = CGPoint(x: a.frame.midX, y: a.frame.midY)
                    a.frame = CGRect(x: center.x - v / 2, y: center.y - v / 2, width: v, height: v)
                }
            }
        ), range: 16...96, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
    }

    @ViewBuilder
    private func highlightControls(_ ann: Annotation) -> some View {
        SliderRow(label: "Dim outside", value: Binding(
            get: { CGFloat(ann.fillOpacity) },
            set: { v in state.updateSelected { $0.fillOpacity = Double(v) } }
        ), range: 0...1, step: 0.05, unit: "",
                  onEditingChanged: { e in if e { state.snapshot() } })
        SliderRow(label: "Corner radius", value: Binding(
            get: { ann.cornerRadius },
            set: { v in state.updateSelected { $0.cornerRadius = v } }
        ), range: 0...40, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })
    }

    @ViewBuilder
    private func imageControls(_ ann: Annotation) -> some View {
        SliderRow(label: "Corner radius", value: Binding(
            get: { ann.cornerRadius },
            set: { v in state.updateSelected { $0.cornerRadius = v } }
        ), range: 0...80, step: 1, unit: "pt",
                  onEditingChanged: { e in if e { state.snapshot() } })

        if let imgRef = ann.image {
            Text("Source: \(Int(imgRef.image.size.width)) × \(Int(imgRef.image.size.height)) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func positionControls(_ ann: Annotation) -> some View {
        Text("Position")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        HStack {
            NumberRow(title: "X", value: Binding(
                get: { ann.frame.minX },
                set: { v in state.updateSelected { $0.frame.origin.x = v } }
            ))
            NumberRow(title: "Y", value: Binding(
                get: { ann.frame.minY },
                set: { v in state.updateSelected { $0.frame.origin.y = v } }
            ))
        }
        HStack {
            // size.width, not frame.width: frame.width is absolute, and writing
            // a positive value back would flip a left/up-pointing arrow.
            NumberRow(title: "W", value: Binding(
                get: { ann.frame.size.width },
                set: { v in state.updateSelected { $0.frame.size.width = v } }
            ))
            NumberRow(title: "H", value: Binding(
                get: { ann.frame.size.height },
                set: { v in state.updateSelected { $0.frame.size.height = v } }
            ))
        }
    }
}

struct LayerShadowControls: View {
    @EnvironmentObject private var state: EditorState
    let annotation: Annotation

    var body: some View {
        SectionHeader("Drop shadow")
        Toggle("Enabled", isOn: Binding(
            get: { annotation.shadowEnabled },
            set: { v in
                state.snapshot()
                state.updateSelected { $0.shadowEnabled = v }
            }
        ))
        if annotation.shadowEnabled {
            SliderRow(label: "Radius", value: Binding(
                get: { annotation.shadowRadius },
                set: { v in state.updateSelected { $0.shadowRadius = v } }
            ), range: 0...80, step: 1, unit: "pt",
                      onEditingChanged: { e in if e { state.snapshot() } })
            SliderRow(label: "Opacity", value: Binding(
                get: { CGFloat(annotation.shadowOpacity) },
                set: { v in state.updateSelected { $0.shadowOpacity = Double(v) } }
            ), range: 0...1, step: 0.05, unit: "",
                      onEditingChanged: { e in if e { state.snapshot() } })
        }
    }
}

struct ZOrderControls: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        HStack(spacing: 6) {
            Button { state.sendToBack() } label: {
                Image(systemName: "square.3.layers.3d.bottom.filled")
                    .frame(width: 30, height: 26)
            }
            .help("Send to back (⌘⇧B)")
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button { state.sendBackward() } label: {
                Image(systemName: "square.2.layers.3d.bottom.filled")
                    .frame(width: 30, height: 26)
            }
            .help("Send backward (⌘[)")
            .keyboardShortcut("[", modifiers: .command)

            Button { state.bringForward() } label: {
                Image(systemName: "square.2.layers.3d.top.filled")
                    .frame(width: 30, height: 26)
            }
            .help("Bring forward (⌘])")
            .keyboardShortcut("]", modifiers: .command)

            Button { state.bringToFront() } label: {
                Image(systemName: "square.3.layers.3d.top.filled")
                    .frame(width: 30, height: 26)
            }
            .help("Bring to front (⌘⇧A)")
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Generic UI rows

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let unit: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(formatted)
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
            }
            Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
        }
    }

    private var formatted: String {
        let v = Double(value)
        if unit.isEmpty { return String(format: "%.2f", v) }
        if step < 1     { return String(format: "%.1f%@", v, unit) }
        return "\(Int(v))\(unit)"
    }
}

struct ColorRow: View {
    let title: String
    @Binding var color: Color
    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            ColorPicker("", selection: $color)
                .labelsHidden()
                .frame(width: 32)
        }
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: CGFloat
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            TextField("", value: Binding<Double>(
                get: { Double(value) },
                set: { value = CGFloat($0) }
            ), format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
        }
    }
}
