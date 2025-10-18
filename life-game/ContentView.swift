//
//  ContentView.swift
//  life-game
//
//  Created by Kevin Hill on 10/18/25.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private enum LayoutMetrics {
    static let baseCellSize: CGFloat = 24
    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 4.0
}

private enum SettingsDefaults {
    static let generationSpeed: Double = 1.0
    static let autoZoomEnabled = true
    static let autoStopEnabled = true
    static let cellColorHex = "#32D74B"
}

private enum PlaybackMetrics {
    static let baseTickInterval: TimeInterval = 0.35
}

struct ContentView: View {
    @StateObject private var engine = GameOfLifeEngine()

    @State private var zoomFactor: CGFloat = 1.0
    @State private var isPlaying = false
    @State private var showSettings = false
    @State private var firstRunDismissed = false
    @State private var playTimer: Timer?

    @AppStorage("life.settings.generationSpeed") private var generationSpeed = SettingsDefaults.generationSpeed
    @AppStorage("life.settings.autoZoomEnabled") private var autoZoomEnabled = SettingsDefaults.autoZoomEnabled
    @AppStorage("life.settings.autoStopEnabled") private var autoStopEnabled = SettingsDefaults.autoStopEnabled
    @AppStorage("life.settings.cellColorHex") private var cellColorHex = SettingsDefaults.cellColorHex

    private var shouldShowFirstRunOverlay: Bool {
        engine.liveCells.isEmpty && !firstRunDismissed
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                AnalyticsHeaderView(engine: engine)
                LifeGridContainer(
                    engine: engine,
                    zoomFactor: $zoomFactor,
                    minZoom: LayoutMetrics.minZoom,
                    maxZoom: LayoutMetrics.maxZoom,
                    baseCellSize: LayoutMetrics.baseCellSize,
                    cellColor: cellColor
                )
                ControlBarView(
                    isPlaying: isPlaying,
                    canStepBackward: engine.generation > 0,
                    onPlayToggle: togglePlayPause,
                    onStepForward: stepForward,
                    onStepBackward: stepBackward,
                    onReset: resetSimulation,
                    onZoomOut: { adjustZoom(by: -0.2) },
                    onZoomIn: { adjustZoom(by: 0.2) },
                    onZoomReset: { zoomFactor = 1.0 },
                    onShowSettings: { showSettings = true }
                )
            }
            .background(.background)

            if shouldShowFirstRunOverlay {
                FirstRunOverlayView(
                    patterns: StarterPattern.catalog,
                    onPatternSelected: { pattern in
                        engine.insert(pattern.coordinates)
                        firstRunDismissed = true
                    },
                    onDismiss: { firstRunDismissed = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                generationSpeed: $generationSpeed,
                autoZoomEnabled: $autoZoomEnabled,
                autoStopEnabled: $autoStopEnabled,
                cellColor: cellColorBinding,
                onResetDefaults: resetSettingsToDefaults
            )
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowFirstRunOverlay)
        .onChange(of: generationSpeed) { _ in
            if isPlaying { rescheduleTimer() }
        }
        .onDisappear {
            stopPlaying()
        }
    }

    private var cellColor: Color {
        Color(hex: cellColorHex) ?? .green
    }

    private var cellColorBinding: Binding<Color> {
        Binding(
            get: { cellColor },
            set: { newValue in
                if let hex = newValue.hexString {
                    cellColorHex = hex
                }
            }
        )
    }

    private func togglePlayPause() {
        if isPlaying {
            stopPlaying()
        } else {
            startPlaying()
        }
    }

    private func startPlaying() {
        guard !isPlaying else { return }
        isPlaying = true
        rescheduleTimer()
    }

    private func stopPlaying() {
        isPlaying = false
        playTimer?.invalidate()
        playTimer = nil
    }

    private func rescheduleTimer() {
        playTimer?.invalidate()
        let interval = max(0.05, PlaybackMetrics.baseTickInterval / generationSpeed)
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            stepForward()
        }
        RunLoop.main.add(timer, forMode: .common)
        playTimer = timer
    }

    private func stepForward() {
        stopPlayingIfNeeded(for: engine.step())
    }

    private func stepBackward() {
        guard engine.stepBackward() else { return }
    }

    private func resetSimulation() {
        engine.clear()
        zoomFactor = 1.0
        stopPlaying()
        firstRunDismissed = false
    }

    private func adjustZoom(by delta: CGFloat) {
        let next = zoomFactor + delta
        zoomFactor = clampZoom(next)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, LayoutMetrics.minZoom), LayoutMetrics.maxZoom)
    }

    private func resetSettingsToDefaults() {
        generationSpeed = SettingsDefaults.generationSpeed
        autoZoomEnabled = SettingsDefaults.autoZoomEnabled
        autoStopEnabled = SettingsDefaults.autoStopEnabled
        cellColorHex = SettingsDefaults.cellColorHex
    }

    private func stopPlayingIfNeeded(for outcome: GameOfLifeEngine.StepOutcome) {
        if autoStopEnabled && outcome.isTerminal {
            stopPlaying()
        }
    }
}

private struct AnalyticsHeaderView: View {
    @ObservedObject var engine: GameOfLifeEngine

    private var hasActivity: Bool {
        engine.generation > 0 || !engine.liveCells.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Life Analytics")
                .font(.headline)

            if hasActivity {
                HStack(spacing: 16) {
                    MetricView(title: "Generation", value: "\(engine.generation)")
                    MetricView(title: "Live Cells", value: "\(engine.liveCells.count)")
                    MetricView(title: "Outcome", value: outcomeDescription(engine.lastOutcome))
                    Spacer()
                }
            } else {
                Text("Toggle cells in the grid or drop a starter pattern to begin the simulation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func outcomeDescription(_ outcome: GameOfLifeEngine.StepOutcome) -> String {
        switch outcome {
        case .advanced:
            return "Running"
        case .stabilized(let reason):
            switch reason {
            case .extinction: return "Extinct"
            case .staticPattern: return "Stable"
            }
        case .cycled(let period):
            return "Cycle ×\(period)"
        }
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct LifeGridContainer: View {
    @ObservedObject var engine: GameOfLifeEngine
    @Binding var zoomFactor: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let baseCellSize: CGFloat
    let cellColor: Color

    @State private var accumulatedPan: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnificationState: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            LifeGridView(
                engine: engine,
                pan: currentPan,
                scale: scaledCellSize,
                cellColor: cellColor
            )
            .background(Color.black.opacity(0.85))
            .gesture(panGesture)
            .simultaneousGesture(pinchGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Life grid")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentPan: CGSize {
        CGSize(width: accumulatedPan.width + dragOffset.width,
               height: accumulatedPan.height + dragOffset.height)
    }

    private var scaledCellSize: CGFloat {
        let temporaryZoom = zoomFactor * magnificationState
        return baseCellSize * temporaryZoom
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                accumulatedPan.width += value.translation.width
                accumulatedPan.height += value.translation.height
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($magnificationState) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let next = zoomFactor * value
                zoomFactor = clamp(next)
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }
}

private struct LifeGridView: View {
    @ObservedObject var engine: GameOfLifeEngine
    let pan: CGSize
    let scale: CGFloat
    let cellColor: Color

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2 + pan.width,
                                 y: canvasSize.height / 2 + pan.height)
            drawGrid(in: &context, canvasSize: canvasSize, center: center)
            drawCells(in: &context, center: center)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, canvasSize: CGSize, center: CGPoint) {
        guard scale > 2 else { return }

        let columns = Int(ceil(canvasSize.width / scale)) + 4
        let rows = Int(ceil(canvasSize.height / scale)) + 4
        let startX = center.x.truncatingRemainder(dividingBy: scale)
        let startY = center.y.truncatingRemainder(dividingBy: scale)

        var gridPath = Path()
        for column in -columns...columns {
            let x = startX + CGFloat(column) * scale
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: canvasSize.height))
        }

        for row in -rows...rows {
            let y = startY + CGFloat(row) * scale
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: canvasSize.width, y: y))
        }

        context.stroke(gridPath, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)

        var axesPath = Path()
        axesPath.move(to: CGPoint(x: 0, y: center.y))
        axesPath.addLine(to: CGPoint(x: canvasSize.width, y: center.y))
        axesPath.move(to: CGPoint(x: center.x, y: 0))
        axesPath.addLine(to: CGPoint(x: center.x, y: canvasSize.height))

        context.stroke(axesPath, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
    }

    private func drawCells(in context: inout GraphicsContext, center: CGPoint) {
        let cellRect = CGRect(x: -scale / 2, y: -scale / 2, width: scale, height: scale)
        for cell in engine.liveCells {
            let position = CGPoint(
                x: center.x + CGFloat(cell.x) * scale,
                y: center.y - CGFloat(cell.y) * scale
            )
            let rect = cellRect.offsetBy(dx: position.x, dy: position.y)
            let path = Path(rect)
            context.fill(path, with: .color(cellColor))
        }
    }
}

private struct ControlBarView: View {
    let isPlaying: Bool
    let canStepBackward: Bool
    let onPlayToggle: () -> Void
    let onStepForward: () -> Void
    let onStepBackward: () -> Void
    let onReset: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onZoomReset: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onPlayToggle) {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }

            Button(action: onStepBackward) {
                Label("Step Back", systemImage: "backward.frame.fill")
            }
            .disabled(!canStepBackward || isPlaying)

            Button(action: onStepForward) {
                Label("Step", systemImage: "forward.frame.fill")
            }
            .disabled(isPlaying)

            Button(action: onReset) {
                Label("Reset", systemImage: "gobackward")
            }

            Divider()
                .frame(height: 18)
                .overlay(Color.secondary.opacity(0.4))

            Button(action: onZoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }

            Button(action: onZoomIn) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }

            Button(action: onZoomReset) {
                Label("Reset Zoom", systemImage: "arrow.uturn.backward")
            }

            Spacer()

            Button(action: onShowSettings) {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct FirstRunOverlayView: View {
    let patterns: [StarterPattern]
    let onPatternSelected: (StarterPattern) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jump Start Your Universe")
                .font(.title3.weight(.semibold))

            Text("Start by toggling cells on the grid or drop one of these classic patterns. Pan with a drag, pinch (or use the buttons below) to zoom.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(patterns) { pattern in
                    Button {
                        onPatternSelected(pattern)
                    } label: {
                        VStack(spacing: 6) {
                            Text(pattern.name)
                                .font(.headline)
                            Text(pattern.caption)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 8)
    }
}

private struct StarterPattern: Identifiable {
    let id = UUID()
    let name: String
    let caption: String
    let coordinates: [GridCoordinate]

    static let catalog: [StarterPattern] = [
        StarterPattern(
            name: "Glider",
            caption: "A self-propelled spaceship.",
            coordinates: [
                GridCoordinate(x: 0, y: 0),
                GridCoordinate(x: 1, y: 0),
                GridCoordinate(x: 2, y: 0),
                GridCoordinate(x: 2, y: -1),
                GridCoordinate(x: 1, y: -2)
            ]
        ),
        StarterPattern(
            name: "Blinker",
            caption: "Oscillates every other tick.",
            coordinates: [
                GridCoordinate(x: -1, y: 0),
                GridCoordinate(x: 0, y: 0),
                GridCoordinate(x: 1, y: 0)
            ]
        ),
        StarterPattern(
            name: "Block",
            caption: "Simple still life.",
            coordinates: [
                GridCoordinate(x: 0, y: 0),
                GridCoordinate(x: 1, y: 0),
                GridCoordinate(x: 0, y: 1),
                GridCoordinate(x: 1, y: 1)
            ]
        )
    ]
}

private struct SettingsView: View {
    @Binding var generationSpeed: Double
    @Binding var autoZoomEnabled: Bool
    @Binding var autoStopEnabled: Bool
    @Binding var cellColor: Color
    let onResetDefaults: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsSection(title: "Simulation Speed") {
                        Slider(
                            value: $generationSpeed,
                            in: 0.25...4.0,
                            step: 0.25
                        ) {
                            Text("Speed")
                        }
                        .accessibilityLabel("Generation speed")

                        HStack {
                            Text("0.25×")
                            Spacer()
                            Text("\(generationSpeed, specifier: "%.2f")×")
                                .monospacedDigit()
                                .font(.headline)
                            Spacer()
                            Text("4×")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    SettingsSection(title: "Automation") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Auto Zoom", isOn: $autoZoomEnabled)
                            Toggle("Auto Stop", isOn: $autoStopEnabled)
                        }
                    }

                    SettingsSection(title: "Appearance") {
                        HStack {
                            Text("Life Cell Color")
                            Spacer()
                            ColorPicker("", selection: $cellColor, supportsOpacity: false)
                                .labelsHidden()
                        }
                    }

                    Button("Reset to Defaults") {
                        onResetDefaults()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 420, alignment: .leading)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 440, minHeight: 300)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: { content })
        }
    }
}

private extension Color {
#if canImport(AppKit)
    typealias PlatformColor = NSColor
#elseif canImport(UIKit)
    typealias PlatformColor = UIColor
#endif

    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6,
              let value = Int(sanitized, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String? {
        #if canImport(AppKit)
        let platformColor = PlatformColor(self)
        guard let rgbColor = platformColor.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        #elseif canImport(UIKit)
        let platformColor = PlatformColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard platformColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let r = Int(round(r * 255))
        let g = Int(round(g * 255))
        let b = Int(round(b * 255))
        #else
        return nil
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
