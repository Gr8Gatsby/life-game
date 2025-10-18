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
    static let minZoom: CGFloat = 0.05
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
    @State private var panOffset: CGSize = .zero
    @State private var gridSize: CGSize = .zero
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
                    cellColor: cellColor,
                    panOffset: $panOffset,
                    gridSize: $gridSize
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
                    onZoomReset: {
                        zoomFactor = 1.0
                        panOffset = .zero
                    },
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
                    onCustom: {
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
            applyAutoZoomIfNeeded(force: true)
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
        let outcome = engine.step()
        applyAutoZoomIfNeeded()
        stopPlayingIfNeeded(for: outcome)
    }

    private func stepBackward() {
        guard engine.stepBackward() else { return }
        applyAutoZoomIfNeeded(force: true)
    }

    private func resetSimulation() {
        engine.clear()
        zoomFactor = 1.0
        panOffset = .zero
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

    private func applyAutoZoomIfNeeded(force: Bool = false) {
        guard (force || isPlaying),
              autoZoomEnabled,
              gridSize.width > 0,
              gridSize.height > 0,
              let bounds = engine.bounds else { return }

        let bufferMultiplier: CGFloat = 1.2
        let widthCells = max(CGFloat(bounds.width), 1)
        let heightCells = max(CGFloat(bounds.height), 1)

        let maxZoomX = gridSize.width / (LayoutMetrics.baseCellSize * widthCells * bufferMultiplier)
        let maxZoomY = gridSize.height / (LayoutMetrics.baseCellSize * heightCells * bufferMultiplier)
        let desiredZoom = min(maxZoomX, maxZoomY)
        let clampedZoom = min(LayoutMetrics.maxZoom, max(LayoutMetrics.minZoom, desiredZoom))

        let centerX = CGFloat(bounds.minX + bounds.maxX) / 2
        let centerY = CGFloat(bounds.minY + bounds.maxY) / 2
        let scale = LayoutMetrics.baseCellSize * clampedZoom

        withAnimation(.easeInOut(duration: 0.25)) {
            zoomFactor = clampedZoom
            panOffset = CGSize(
                width: -centerX * scale,
                height: centerY * scale
            )
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
    @Binding var panOffset: CGSize
    @Binding var gridSize: CGSize

    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnificationState: CGFloat = 1.0
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = geometry.size
            let gridGeometry = GridGeometry(
                canvasSize: canvasSize,
                scale: scaledCellSize,
                pan: currentPan
            )
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear { gridSize = canvasSize }
                    .onChange(of: canvasSize) { newValue in
                        gridSize = newValue
                    }
                LifeGridView(
                    engine: engine,
                    gridGeometry: gridGeometry,
                    cellColor: cellColor,
                    hoverCoordinate: hoverCoordinate(using: gridGeometry)
                )
            }
            .background(Color.black.opacity(0.85))
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(pinchGesture)
#if os(macOS)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
#endif
            .simultaneousGesture(tapGesture(using: gridGeometry))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Life grid")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentPan: CGSize {
        CGSize(width: panOffset.width + dragOffset.width,
               height: panOffset.height + dragOffset.height)
    }

    private var scaledCellSize: CGFloat {
        let temporaryZoom = zoomFactor * magnificationState
        return baseCellSize * temporaryZoom
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                panOffset.width += value.translation.width
                panOffset.height += value.translation.height
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

    private func tapGesture(using geometry: GridGeometry) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                toggleCell(at: value.location, geometry: geometry)
            }
    }

    private func toggleCell(at location: CGPoint, geometry: GridGeometry) {
        guard let coordinate = geometry.coordinate(for: location) else {
            return
        }
        engine.toggle(coordinate)
        hoverLocation = location
    }

    private func hoverCoordinate(using geometry: GridGeometry) -> GridCoordinate? {
        guard let hoverLocation else { return nil }
        return geometry.coordinate(for: hoverLocation)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }
}

private struct LifeGridView: View {
    @ObservedObject var engine: GameOfLifeEngine
    let gridGeometry: GridGeometry
    let cellColor: Color
    let hoverCoordinate: GridCoordinate?

    var body: some View {
        Canvas { context, canvasSize in
            drawGrid(in: &context, canvasSize: canvasSize)
            drawCells(in: &context)
            drawHover(in: &context)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, canvasSize: CGSize) {
        guard gridGeometry.scale > 2 else { return }

        let columns = Int(ceil(canvasSize.width / gridGeometry.scale)) + 2
        let rows = Int(ceil(canvasSize.height / gridGeometry.scale)) + 2

        var gridPath = Path()
        for column in -columns...columns {
            let x = gridGeometry.verticalLinePosition(for: column)
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: canvasSize.height))
        }

        for row in -rows...rows {
            let y = gridGeometry.horizontalLinePosition(for: row)
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: canvasSize.width, y: y))
        }

        context.stroke(gridPath, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)

        var axesPath = Path()
        axesPath.move(to: CGPoint(x: 0, y: gridGeometry.center.y))
        axesPath.addLine(to: CGPoint(x: canvasSize.width, y: gridGeometry.center.y))
        axesPath.move(to: CGPoint(x: gridGeometry.center.x, y: 0))
        axesPath.addLine(to: CGPoint(x: gridGeometry.center.x, y: canvasSize.height))

        context.stroke(axesPath, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
    }

    private func drawCells(in context: inout GraphicsContext) {
        if gridGeometry.groupSize == 1 {
            for cell in engine.liveCells {
                let rect = gridGeometry.rectForCell(cell)
                let path = Path(rect)
                context.fill(path, with: .color(cellColor))
            }
        } else {
            var grouped: [GridCoordinate: Int] = [:]
            for cell in engine.liveCells {
                let key = gridGeometry.groupCoordinate(for: cell)
                grouped[key, default: 0] += 1
            }

            let groupCapacity = gridGeometry.groupSize * gridGeometry.groupSize
            for (groupCoord, count) in grouped {
                let rect = gridGeometry.rectForGroup(groupCoord)
                let occupancy = Double(count) / Double(groupCapacity)
                let alpha = 0.4 + 0.6 * occupancy
                let path = Path(rect)
                context.fill(path, with: .color(cellColor.opacity(alpha)))
            }
        }
    }

    private func drawHover(in context: inout GraphicsContext) {
        guard let hoverCoordinate else { return }
        let rect: CGRect
        if gridGeometry.groupSize == 1 {
            rect = gridGeometry.rectForCell(hoverCoordinate)
        } else {
            let groupCoord = gridGeometry.groupCoordinate(for: hoverCoordinate)
            rect = gridGeometry.rectForGroup(groupCoord)
        }
        let path = Path(rect)
        context.stroke(path, with: .color(cellColor), lineWidth: 2)
    }
}

private struct GridGeometry {
    let canvasSize: CGSize
    let scale: CGFloat
    let pan: CGSize
    let groupSize: Int

    var center: CGPoint {
        CGPoint(
            x: canvasSize.width / 2 + pan.width,
            y: canvasSize.height / 2 + pan.height
        )
    }

    init(canvasSize: CGSize, scale: CGFloat, pan: CGSize) {
        self.canvasSize = canvasSize
        self.scale = scale
        self.pan = pan
        self.groupSize = GridGeometry.computeGroupSize(for: scale)
    }

    func rectForCell(_ coordinate: GridCoordinate) -> CGRect {
        guard scale > .ulpOfOne else { return .zero }
        let origin = CGPoint(
            x: center.x + (CGFloat(coordinate.x) - 0.5) * scale,
            y: center.y - (CGFloat(coordinate.y) + 0.5) * scale
        )
        return CGRect(origin: origin, size: CGSize(width: scale, height: scale))
    }

    func rectForGroup(_ groupCoordinate: GridCoordinate) -> CGRect {
        let minX = groupCoordinate.x * groupSize
        let minY = groupCoordinate.y * groupSize

        var unionRect: CGRect?
        for x in minX..<(minX + groupSize) {
            for y in minY..<(minY + groupSize) {
                let rect = rectForCell(GridCoordinate(x: x, y: y))
                unionRect = unionRect?.union(rect) ?? rect
            }
        }
        return unionRect ?? .zero
    }

    func coordinate(for point: CGPoint) -> GridCoordinate? {
        guard scale > .ulpOfOne else { return nil }
        let dx = (point.x - center.x) / scale
        let dy = (center.y - point.y) / scale
        let x = Int(round(dx))
        let y = Int(round(dy))
        return GridCoordinate(x: x, y: y)
    }

    func groupCoordinate(for coordinate: GridCoordinate) -> GridCoordinate {
        let g = groupSize
        return GridCoordinate(
            x: GridGeometry.floorDivide(coordinate.x, g),
            y: GridGeometry.floorDivide(coordinate.y, g)
        )
    }

    func verticalLinePosition(for column: Int) -> CGFloat {
        center.x + (CGFloat(column) - 0.5) * scale
    }

    func horizontalLinePosition(for row: Int) -> CGFloat {
        center.y + (CGFloat(row) - 0.5) * scale
    }

    private static func computeGroupSize(for scale: CGFloat) -> Int {
        let normalized = scale / LayoutMetrics.baseCellSize
        if normalized >= 0.5 {
            return 1
        } else if normalized >= 0.25 {
            return 2
        } else if normalized >= 0.125 {
            return 3
        } else {
            return 4
        }
    }

    private static func floorDivide(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        let remainder = a % b
        if remainder >= 0 {
            return quotient
        } else {
            return quotient - 1
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
    let onCustom: () -> Void
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
                Button {
                    onCustom()
                } label: {
                    VStack(spacing: 6) {
                        Text("Custom")
                            .font(.headline)
                        Text("Paint your own pattern.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
