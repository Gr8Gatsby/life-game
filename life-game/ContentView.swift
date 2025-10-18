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
    static let gridBackgroundHex = "#050505"
    static let gridLineHex = "#808080"
    static let axisLineHex = "#C0C0C0"
    static let autoZoomModeRawValue = AutoZoomMode.fit.rawValue
}

enum AutoZoomMode: Int, CaseIterable, Identifiable {
    case fit = 0
    case out = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fit: return "Fit"
        case .out: return "Out"
        }
    }
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
    @State private var isEditMode = true
    @State private var activePattern: PatternStamp? = nil
    @State private var playTimer: Timer?
    @State private var maxLiveCells: Int = 0
    @State private var minLiveCells: Int = 0
    @State private var populationHistory: [Int] = []
    @State private var undoHistory: [ActionRecord] = []
    @State private var redoHistory: [ActionRecord] = []

    @AppStorage("life.settings.generationSpeed") private var generationSpeed = SettingsDefaults.generationSpeed
    @AppStorage("life.settings.autoZoomEnabled") private var autoZoomEnabled = SettingsDefaults.autoZoomEnabled
    @AppStorage("life.settings.autoStopEnabled") private var autoStopEnabled = SettingsDefaults.autoStopEnabled
    @AppStorage("life.settings.cellColorHex") private var cellColorHex = SettingsDefaults.cellColorHex
    @AppStorage("life.settings.gridBackgroundHex") private var gridBackgroundHex = SettingsDefaults.gridBackgroundHex
    @AppStorage("life.settings.gridLineHex") private var gridLineHex = SettingsDefaults.gridLineHex
    @AppStorage("life.settings.axisLineHex") private var axisLineHex = SettingsDefaults.axisLineHex
    @AppStorage("life.settings.autoZoomMode") private var autoZoomModeRawValue = SettingsDefaults.autoZoomModeRawValue

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if isEditMode {
                    PatternSidebar(
                        patterns: PatternStamp.library,
                        selectedPattern: activePattern,
                        cellColor: cellColor,
                        backgroundColor: gridBackgroundColor,
                        onSelect: { activePattern = $0 }
                    )
                }

                VStack(spacing: 0) {
                    AnalyticsHeaderView(
                        engine: engine,
                        maxLiveCells: maxLiveCells,
                        minLiveCells: minLiveCells,
                        populationHistory: populationHistory,
                        cellColor: cellColor,
                        backgroundColor: gridBackgroundColor
                    )
                    LifeGridContainer(
                        engine: engine,
                        zoomFactor: $zoomFactor,
                        minZoom: LayoutMetrics.minZoom,
                        maxZoom: LayoutMetrics.maxZoom,
                        baseCellSize: LayoutMetrics.baseCellSize,
                        cellColor: cellColor,
                        gridBackgroundColor: gridBackgroundColor,
                        gridLineColor: gridLineColor,
                        axisLineColor: axisLineColor,
                        isEditMode: isEditMode,
                        activePattern: activePattern,
                        onToggleCell: { performToggle(at: $0) },
                        onStampPattern: { coordinate, pattern in performStamp(pattern: pattern, at: coordinate) },
                        panOffset: $panOffset,
                        gridSize: $gridSize
                    )
                    ControlBarView(
                        isPlaying: isPlaying,
                        isEditMode: isEditMode,
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
                        onShowSettings: { showSettings = true },
                        onEditModeToggle: { newValue in
                            isEditMode = newValue
                            if !newValue { activePattern = nil }
                        }
                    )
                }
                .background(.background)
            }

            Button(action: undoAction) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command])
                .frame(width: 0, height: 0)
                .opacity(0)

            Button(action: redoAction) { EmptyView() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .frame(width: 0, height: 0)
                .opacity(0)

            Button(action: { activePattern = nil }) { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                generationSpeed: $generationSpeed,
                autoZoomEnabled: $autoZoomEnabled,
                autoStopEnabled: $autoStopEnabled,
                autoZoomModeRawValue: $autoZoomModeRawValue,
                cellColor: cellColorBinding,
                gridBackgroundColor: gridBackgroundBinding,
                gridLineColor: gridLineBinding,
                axisLineColor: axisLineBinding,
                onResetDefaults: resetSettingsToDefaults
            )
        }
        .onChange(of: generationSpeed) { _, _ in
            if isPlaying { rescheduleTimer() }
        }
        .onDisappear {
            stopPlaying()
        }
        .onAppear {
            recordPopulationSnapshot(force: true)
        }
    }

    private var cellColor: Color {
        Color(hex: cellColorHex) ?? .green
    }

    private var gridBackgroundColor: Color {
        Color(hex: gridBackgroundHex) ?? Color(red: 5/255, green: 5/255, blue: 5/255)
    }

    private var gridLineColor: Color {
        Color(hex: gridLineHex) ?? .gray.opacity(0.35)
    }

    private var axisLineColor: Color {
        Color(hex: axisLineHex) ?? .white.opacity(0.35)
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

    private var gridBackgroundBinding: Binding<Color> {
        Binding(
            get: { gridBackgroundColor },
            set: { newValue in
                if let hex = newValue.hexString {
                    gridBackgroundHex = hex
                }
            }
        )
    }

    private var gridLineBinding: Binding<Color> {
        Binding(
            get: { gridLineColor },
            set: { newValue in
                if let hex = newValue.hexString {
                    gridLineHex = hex
                }
            }
        )
    }

    private var axisLineBinding: Binding<Color> {
        Binding(
            get: { axisLineColor },
            set: { newValue in
                if let hex = newValue.hexString {
                    axisLineHex = hex
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
        isEditMode = false
        activePattern = nil
        isPlaying = true
        clearHistories()
        recordPopulationSnapshot(force: true)
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
        recordPopulationSnapshot()
        applyAutoZoomIfNeeded()
        stopPlayingIfNeeded(for: outcome)
    }

    private func stepBackward() {
        guard engine.stepBackward() else { return }
        applyAutoZoomIfNeeded(force: true)
        recordPopulationSnapshot(force: true)
    }

    private func resetSimulation() {
        engine.clear()
        zoomFactor = 1.0
        panOffset = .zero
        stopPlaying()
        maxLiveCells = 0
        minLiveCells = 0
        populationHistory.removeAll()
        activePattern = nil
        clearHistories()
        recordPopulationSnapshot(force: true)
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
        autoZoomModeRawValue = SettingsDefaults.autoZoomModeRawValue
        gridBackgroundHex = SettingsDefaults.gridBackgroundHex
        gridLineHex = SettingsDefaults.gridLineHex
        axisLineHex = SettingsDefaults.axisLineHex
    }

    private func stopPlayingIfNeeded(for outcome: GameOfLifeEngine.StepOutcome) {
        if autoStopEnabled && outcome.isTerminal {
            stopPlaying()
        }
    }

    private func recordPopulationSnapshot(force: Bool = false) {
        let count = engine.liveCells.count
        guard force || populationHistory.last != count else { return }

        populationHistory.append(count)
        if populationHistory.count > 120 {
            populationHistory.removeFirst()
        }

        if populationHistory.count == 1 || count > maxLiveCells {
            maxLiveCells = count
        }

        if populationHistory.count == 1 || count < minLiveCells {
            minLiveCells = count
        }
    }

    private func performToggle(at coordinate: GridCoordinate) {
        guard isEditMode else { return }
        let wasAlive = engine.isAlive(coordinate)
        let nowAlive = !wasAlive
        guard wasAlive != nowAlive else { return }
        let change = CellChange(coordinate: coordinate, oldState: wasAlive, newState: nowAlive)
        applyChanges([change])
    }

    private func performStamp(pattern: PatternStamp, at coordinate: GridCoordinate) {
        guard isEditMode else { return }
        var changes: [CellChange] = []
        var seen = Set<GridCoordinate>()
        for offset in pattern.offsets {
            let target = GridCoordinate(x: coordinate.x + offset.x, y: coordinate.y + offset.y)
            guard seen.insert(target).inserted else { continue }
            let wasAlive = engine.isAlive(target)
            if !wasAlive {
                changes.append(CellChange(coordinate: target, oldState: false, newState: true))
            }
        }
        applyChanges(changes)
    }

    private func applyChanges(_ changes: [CellChange], trackHistory: Bool = true) {
        guard !changes.isEmpty else { return }

        for change in changes {
            if change.newState {
                engine.setAlive(true, at: change.coordinate)
            } else {
                engine.setAlive(false, at: change.coordinate)
            }
        }

        if trackHistory {
            undoHistory.append(ActionRecord(changes: changes))
            if undoHistory.count > 50 {
                undoHistory.removeFirst()
            }
            redoHistory.removeAll()
        }

        recordPopulationSnapshot(force: true)
    }

    private func undoAction() {
        guard let record = undoHistory.popLast() else { return }
        let reversal = record.changes.map { change in
            CellChange(coordinate: change.coordinate, oldState: change.newState, newState: change.oldState)
        }
        applyChanges(reversal, trackHistory: false)
        redoHistory.append(record)
        if redoHistory.count > 50 {
            redoHistory.removeFirst()
        }
    }

    private func redoAction() {
        guard let record = redoHistory.popLast() else { return }
        applyChanges(record.changes, trackHistory: false)
        undoHistory.append(record)
        if undoHistory.count > 50 {
            undoHistory.removeFirst()
        }
    }

    private func clearHistories() {
        undoHistory.removeAll()
        redoHistory.removeAll()
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

        if !force {
            let currentScale = LayoutMetrics.baseCellSize * zoomFactor
            if currentScale > .ulpOfOne {
                let viewHalfWidth = gridSize.width / (2 * currentScale)
                let viewHalfHeight = gridSize.height / (2 * currentScale)
                let requiredHalfWidth = widthCells * bufferMultiplier / 2
                let requiredHalfHeight = heightCells * bufferMultiplier / 2
                if viewHalfWidth >= requiredHalfWidth && viewHalfHeight >= requiredHalfHeight {
                    return
                }
            }
        }

        let centerX = CGFloat(bounds.minX + bounds.maxX) / 2
        let centerY = CGFloat(bounds.minY + bounds.maxY) / 2

        let currentZoom = zoomFactor
        let mode = AutoZoomMode(rawValue: autoZoomModeRawValue) ?? .fit
        let targetZoom: CGFloat
        switch mode {
        case .fit:
            targetZoom = clampedZoom
        case .out:
            targetZoom = min(currentZoom, clampedZoom)
        }

        let targetScale = LayoutMetrics.baseCellSize * targetZoom
        withAnimation(.easeInOut(duration: 0.25)) {
            if abs(targetZoom - zoomFactor) > 0.0005 {
                zoomFactor = targetZoom
            }
            panOffset = CGSize(
                width: -centerX * targetScale,
                height: centerY * targetScale
            )
        }
    }
}

private struct AnalyticsHeaderView: View {
    @ObservedObject var engine: GameOfLifeEngine
    let maxLiveCells: Int
    let minLiveCells: Int
    let populationHistory: [Int]
    let cellColor: Color
    let backgroundColor: Color

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
                    MetricView(title: "Max", value: "\(maxLiveCells)")
                    MetricView(title: "Min", value: "\(minLiveCells)")
                    MetricView(title: "Outcome", value: outcomeDescription(engine.lastOutcome))
                    Spacer()
                }
            } else {
                Text("Toggle cells in the grid or drop a starter pattern to begin the simulation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !populationHistory.isEmpty {
                PopulationSparkline(
                    data: populationHistory,
                    lineColor: cellColor,
                    fillColor: backgroundColor
                )
                    .padding(.top, 4)
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

private struct PopulationSparkline: View {
    let data: [Int]
    let lineColor: Color
    let fillColor: Color

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(lineColor.opacity(0.8), lineWidth: 1.5)
            .background(
                Path { path in
                    guard let first = points.first,
                          let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(fillColor.opacity(0.35))
            )
        }
        .frame(height: 36)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !data.isEmpty, size.width > 0 else { return [] }
        let maxValue = CGFloat(data.max() ?? 1)
        let minValue = CGFloat(data.min() ?? 0)
        let span = max(maxValue - minValue, 1)
        let stepX = size.width / max(CGFloat(data.count - 1), 1)

        return data.enumerated().map { index, value in
            let normalizedY = (CGFloat(value) - minValue) / span
            let x = CGFloat(index) * stepX
            let y = size.height * (1 - normalizedY)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct CellChange {
    let coordinate: GridCoordinate
    let oldState: Bool
    let newState: Bool
}

private struct ActionRecord {
    let changes: [CellChange]
}

private struct LifeGridContainer: View {
    @ObservedObject var engine: GameOfLifeEngine
    @Binding var zoomFactor: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let baseCellSize: CGFloat
    let cellColor: Color
    let gridBackgroundColor: Color
    let gridLineColor: Color
    let axisLineColor: Color
    let isEditMode: Bool
    let activePattern: PatternStamp?
    let onToggleCell: (GridCoordinate) -> Void
    let onStampPattern: (GridCoordinate, PatternStamp) -> Void
    @Binding var panOffset: CGSize
    @Binding var gridSize: CGSize

    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnificationState: CGFloat = 1.0
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = geometry.size
            let effectiveZoom = max(zoomFactor * magnificationState, LayoutMetrics.minZoom)
            let gridGeometry = GridGeometry(
                canvasSize: canvasSize,
                scale: scaledCellSize,
                pan: currentPan,
                zoomFactor: effectiveZoom
            )
            ZStack {
                gridBackgroundColor
                    .allowsHitTesting(false)
                    .onAppear { gridSize = canvasSize }
                    .onChange(of: canvasSize) { _, newValue in gridSize = newValue }
                LifeGridView(
                    engine: engine,
                    gridGeometry: gridGeometry,
                    cellColor: cellColor,
                    gridLineColor: gridLineColor,
                    axisLineColor: axisLineColor,
                    isEditMode: isEditMode,
                    activePattern: activePattern,
                    hoverCoordinate: hoverCoordinate(using: gridGeometry)
                )
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(pinchGesture)
#if os(macOS)
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard isEditMode else { hoverLocation = nil; return }
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
                applyEdit(at: value.location, geometry: geometry)
            }
    }

    private func applyEdit(at location: CGPoint, geometry: GridGeometry) {
        guard isEditMode, let coordinate = geometry.coordinate(for: location) else { return }
        if let pattern = activePattern {
            onStampPattern(coordinate, pattern)
        } else {
            onToggleCell(coordinate)
        }
        hoverLocation = location
    }

    private func hoverCoordinate(using geometry: GridGeometry) -> GridCoordinate? {
        guard isEditMode, let hoverLocation else { return nil }
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
    let gridLineColor: Color
    let axisLineColor: Color
    let isEditMode: Bool
    let activePattern: PatternStamp?
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

        let spacing = gridGeometry.aggregatedScale
        guard spacing > .ulpOfOne else { return }

        let columns = Int(ceil(canvasSize.width / spacing)) + 2
        let rows = Int(ceil(canvasSize.height / spacing)) + 2

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

        context.stroke(gridPath, with: .color(gridLineColor), lineWidth: 0.5)

        var axesPath = Path()
        axesPath.move(to: CGPoint(x: 0, y: gridGeometry.center.y))
        axesPath.addLine(to: CGPoint(x: canvasSize.width, y: gridGeometry.center.y))
        axesPath.move(to: CGPoint(x: gridGeometry.center.x, y: 0))
        axesPath.addLine(to: CGPoint(x: gridGeometry.center.x, y: canvasSize.height))

        context.stroke(axesPath, with: .color(axisLineColor), lineWidth: 1.0)
    }

    private func drawCells(in context: inout GraphicsContext) {
        for cell in engine.liveCells {
            let rect = gridGeometry.rectForCell(cell)
            let path = Path(rect)
            context.fill(path, with: .color(cellColor))
        }
    }

    private func drawHover(in context: inout GraphicsContext) {
        guard isEditMode, let hoverCoordinate else { return }
        if let pattern = activePattern {
            for offset in pattern.offsets {
                let coordinate = GridCoordinate(x: hoverCoordinate.x + offset.x, y: hoverCoordinate.y + offset.y)
                let rect = gridGeometry.rectForCell(coordinate)
                let path = Path(rect)
                context.fill(path, with: .color(cellColor.opacity(0.25)))
                context.stroke(path, with: .color(cellColor.opacity(0.6)), lineWidth: 1)
            }
        } else {
            let rect = gridGeometry.rectForCell(hoverCoordinate)
            let path = Path(rect)
            context.stroke(path, with: .color(cellColor), lineWidth: 2)
        }
    }
}

private struct PatternStamp: Identifiable, Equatable {
    struct Bounds {
        let minX: Int
        let minY: Int
        let width: Int
        let height: Int
    }

    let id: String
    let name: String
    let offsets: [GridCoordinate]

    init(name: String, offsets: [GridCoordinate]) {
        self.id = name
        self.name = name
        self.offsets = offsets
    }

    var bounds: Bounds {
        guard let minX = offsets.map(\.x).min(),
              let maxX = offsets.map(\.x).max(),
              let minY = offsets.map(\.y).min(),
              let maxY = offsets.map(\.y).max() else {
            return Bounds(minX: 0, minY: 0, width: 1, height: 1)
        }
        return Bounds(minX: minX, minY: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static let library: [PatternStamp] = [
        PatternStamp.make("Block", [(0,0),(1,0),(0,1),(1,1)]),
        PatternStamp.make("Beehive", [(1,0),(2,0),(0,1),(3,1),(1,2),(2,2)]),
        PatternStamp.make("Loaf", [(1,0),(2,0),(0,1),(3,1),(1,2),(3,2),(2,3)]),
        PatternStamp.make("Boat", [(0,0),(1,0),(0,1),(2,1),(1,2)]),
        PatternStamp.make("Blinker", [(0,0),(1,0),(2,0)]),
        PatternStamp.make("Toad", [(1,0),(2,0),(3,0),(0,1),(1,1),(2,1)]),
        PatternStamp.make("Beacon", [(0,0),(1,0),(0,1),(1,1),(2,2),(3,2),(2,3),(3,3)]),
        PatternStamp.make("Pulsar", PatternStamp.pulsarOffsets),
        PatternStamp.make("Glider", [(0,1),(1,2),(2,0),(2,1),(2,2)]),
        PatternStamp.make("R-pentomino", [(1,0),(2,0),(0,1),(1,1),(1,2)]),
        PatternStamp.make("Diehard", [(7,0),(0,1),(1,1),(1,2),(6,2),(7,2),(8,2)]),
        PatternStamp.make("Gosper Gun", PatternStamp.gosperGunOffsets)
    ]

    private static func make(_ name: String, _ tuples: [(Int, Int)]) -> PatternStamp {
        PatternStamp(name: name, offsets: tuples.map { GridCoordinate(x: $0.0, y: $0.1) })
    }

    private static let pulsarOffsets: [(Int, Int)] = [
        (2,0),(3,0),(4,0),(8,0),(9,0),(10,0),
        (0,2),(5,2),(7,2),(12,2),
        (0,3),(5,3),(7,3),(12,3),
        (0,4),(5,4),(7,4),(12,4),
        (2,5),(3,5),(4,5),(8,5),(9,5),(10,5),
        (2,7),(3,7),(4,7),(8,7),(9,7),(10,7),
        (0,8),(5,8),(7,8),(12,8),
        (0,9),(5,9),(7,9),(12,9),
        (0,10),(5,10),(7,10),(12,10),
        (2,12),(3,12),(4,12),(8,12),(9,12),(10,12)
    ]

    private static let gosperGunOffsets: [(Int, Int)] = [
        (0,4),(0,5),(1,4),(1,5),
        (10,4),(10,5),(10,6),
        (11,3),(11,7),
        (12,2),(12,8),
        (13,2),(13,8),
        (14,5),
        (15,3),(15,7),
        (16,4),(16,5),(16,6),
        (17,5),
        (20,2),(20,3),(20,4),
        (21,2),(21,3),(21,4),
        (22,1),(22,5),
        (24,0),(24,1),(24,5),(24,6),
        (34,2),(34,3),(35,2),(35,3)
    ]
}

private struct PatternThumbnail: View {
    let pattern: PatternStamp
    let cellColor: Color
    let backgroundColor: Color

    var body: some View {
        GeometryReader { geometry in
            let bounds = pattern.bounds
            let width = CGFloat(bounds.width)
            let height = CGFloat(bounds.height)
            let scale = min((geometry.size.width - 4) / max(width, 1), (geometry.size.height - 4) / max(height, 1))
            let offsetX = (geometry.size.width - width * scale) / 2
            let offsetY = (geometry.size.height - height * scale) / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor.opacity(0.6))

                ForEach(pattern.offsets, id: \.self) { coordinate in
                    let normalizedX = CGFloat(coordinate.x - bounds.minX)
                    let normalizedY = CGFloat(coordinate.y - bounds.minY)
                    let rect = CGRect(
                        x: offsetX + normalizedX * scale,
                        y: offsetY + normalizedY * scale,
                        width: scale,
                        height: scale
                    )
                    Path { path in
                        path.addRect(rect)
                    }
                    .fill(cellColor)
                }
            }
        }
    }
}

private struct PatternToolbar: View {
    let patterns: [PatternStamp]
    let selectedPattern: PatternStamp?
    let cellColor: Color
    let backgroundColor: Color
    let onSelect: (PatternStamp?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Patterns")
                    .font(.headline)
                Spacer()
                Button("Clear") { onSelect(nil) }
                    .buttonStyle(.borderless)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(patterns) { pattern in
                        Button {
                            if selectedPattern?.id == pattern.id {
                                onSelect(nil)
                            } else {
                                onSelect(pattern)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                PatternThumbnail(pattern: pattern, cellColor: cellColor, backgroundColor: backgroundColor)
                                    .frame(width: 44, height: 44)
                                Text(pattern.name)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary.opacity(0.8))
                            }
                            .padding(6)
                            .frame(width: 70)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedPattern?.id == pattern.id ? cellColor.opacity(0.18) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selectedPattern?.id == pattern.id ? cellColor : Color.primary.opacity(0.08), lineWidth: selectedPattern?.id == pattern.id ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct PatternSidebar: View {
    let patterns: [PatternStamp]
    let selectedPattern: PatternStamp?
    let cellColor: Color
    let backgroundColor: Color
    let onSelect: (PatternStamp?) -> Void

    var body: some View {
        PatternToolbar(
            patterns: patterns,
            selectedPattern: selectedPattern,
            cellColor: cellColor,
            backgroundColor: backgroundColor,
            onSelect: onSelect
        )
        .frame(width: 220)
        .background(.thinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(width: 1)
        }
    }
}

private struct GridGeometry {
    let canvasSize: CGSize
    let scale: CGFloat
    let pan: CGSize
    let aggregatedScale: CGFloat
    let groupSize: Int

    var center: CGPoint {
        CGPoint(
            x: canvasSize.width / 2 + pan.width,
            y: canvasSize.height / 2 + pan.height
        )
    }

    init(canvasSize: CGSize, scale: CGFloat, pan: CGSize, zoomFactor: CGFloat) {
        self.canvasSize = canvasSize
        self.scale = scale
        self.pan = pan
        self.groupSize = GridGeometry.computeGroupSize(for: zoomFactor)
        self.aggregatedScale = scale * CGFloat(groupSize)
    }

    func rectForCell(_ coordinate: GridCoordinate) -> CGRect {
        guard scale > .ulpOfOne else { return .zero }
        let origin = CGPoint(
            x: center.x + (CGFloat(coordinate.x) - 0.5) * scale,
            y: center.y - (CGFloat(coordinate.y) + 0.5) * scale
        )
        return CGRect(origin: origin, size: CGSize(width: scale, height: scale))
    }

    func coordinate(for point: CGPoint) -> GridCoordinate? {
        guard scale > .ulpOfOne else { return nil }
        let dx = (point.x - center.x) / scale
        let dy = (center.y - point.y) / scale
        let x = Int(round(dx))
        let y = Int(round(dy))
        return GridCoordinate(x: x, y: y)
    }

    func verticalLinePosition(for column: Int) -> CGFloat {
        center.x + (CGFloat(column) - 0.5) * aggregatedScale
    }

    func horizontalLinePosition(for row: Int) -> CGFloat {
        center.y + (CGFloat(row) - 0.5) * aggregatedScale
    }

    private static func computeGroupSize(for zoomFactor: CGFloat) -> Int {
        let safeFactor = max(zoomFactor, 0.0001)
        let zoomOut = max(1.0, 1.0 / safeFactor)
        if zoomOut < 1.5 {
            return 1
        } else if zoomOut < 2.5 {
            return 2
        } else if zoomOut < 3.5 {
            return 3
        } else {
            return 4
        }
    }
}

private struct ControlBarView: View {
    let isPlaying: Bool
    let isEditMode: Bool
    let canStepBackward: Bool
    let onPlayToggle: () -> Void
    let onStepForward: () -> Void
    let onStepBackward: () -> Void
    let onReset: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onZoomReset: () -> Void
    let onShowSettings: () -> Void
    let onEditModeToggle: (Bool) -> Void

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

            Toggle(isOn: Binding(
                get: { isEditMode },
                set: { newValue in
                    onEditModeToggle(newValue)
                }
            )) {
                Label("Edit", systemImage: "pencil.and.outline")
            }
            .toggleStyle(.button)

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


private struct SettingsView: View {
    @Binding var generationSpeed: Double
    @Binding var autoZoomEnabled: Bool
    @Binding var autoStopEnabled: Bool
    @Binding var autoZoomModeRawValue: Int
    @Binding var cellColor: Color
    @Binding var gridBackgroundColor: Color
    @Binding var gridLineColor: Color
    @Binding var axisLineColor: Color
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
                            if autoZoomEnabled {
                                Picker("Auto Zoom Mode", selection: $autoZoomModeRawValue) {
                                    ForEach(AutoZoomMode.allCases) { mode in
                                        Text(mode.label).tag(mode.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            Toggle("Auto Stop", isOn: $autoStopEnabled)
                        }
                    }

                    SettingsSection(title: "Appearance") {
                        VStack(alignment: .leading, spacing: 12) {
                            colorRow(title: "Life Cell", binding: $cellColor)
                            colorRow(title: "Grid Background", binding: $gridBackgroundColor)
                            colorRow(title: "Grid Lines", binding: $gridLineColor)
                            colorRow(title: "Center Lines", binding: $axisLineColor)
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

    private func colorRow(title: String, binding: Binding<Color>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
        }
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
