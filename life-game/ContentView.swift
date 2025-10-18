//
//  ContentView.swift
//  life-game
//
//  Created by Kevin Hill on 10/18/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = GameOfLifeEngine()

    var body: some View {
        VStack(spacing: 0) {
            AnalyticsHeaderView(engine: engine)
            LifeGridContainer(engine: engine)
            ControlBarView()
        }
        .background(.background)
    }
}

private struct AnalyticsHeaderView: View {
    @ObservedObject var engine: GameOfLifeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Life Analytics")
                .font(.headline)
            HStack(spacing: 16) {
                MetricView(title: "Generation", value: "\(engine.generation)")
                MetricView(title: "Live Cells", value: "\(engine.liveCells.count)")
                MetricView(title: "Outcome", value: outcomeDescription(engine.lastOutcome))
                Spacer()
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
            return "Cycle x\(period)"
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
        }
    }
}

private struct LifeGridContainer: View {
    @ObservedObject var engine: GameOfLifeEngine
    @State private var accumulatedPan: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            LifeGridView(engine: engine, pan: currentPan)
                .background(Color.black.opacity(0.85))
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            accumulatedPan.width += value.translation.width
                            accumulatedPan.height += value.translation.height
                        }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentPan: CGSize {
        CGSize(width: accumulatedPan.width + dragOffset.width,
               height: accumulatedPan.height + dragOffset.height)
    }
}

private struct LifeGridView: View {
    @ObservedObject var engine: GameOfLifeEngine
    let pan: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            let scale: CGFloat = 24
            let center = CGPoint(x: canvasSize.width / 2 + pan.width,
                                 y: canvasSize.height / 2 + pan.height)
            drawGrid(in: &context, canvasSize: canvasSize, center: center, scale: scale)
            drawCells(in: &context, center: center, scale: scale)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, canvasSize: CGSize, center: CGPoint, scale: CGFloat) {
        let columns = Int(ceil(canvasSize.width / scale)) + 4
        let rows = Int(ceil(canvasSize.height / scale)) + 4
        let startX = center.x.truncatingRemainder(dividingBy: scale)
        let startY = center.y.truncatingRemainder(dividingBy: scale)

        var path = Path()
        for column in -columns...columns {
            let x = startX + CGFloat(column) * scale
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: canvasSize.height))
        }

        for row in -rows...rows {
            let y = startY + CGFloat(row) * scale
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: canvasSize.width, y: y))
        }

        context.stroke(path, with: .color(.gray.opacity(0.4)), lineWidth: 0.5)

        var axes = Path()
        axes.move(to: CGPoint(x: 0, y: center.y))
        axes.addLine(to: CGPoint(x: canvasSize.width, y: center.y))
        axes.move(to: CGPoint(x: center.x, y: 0))
        axes.addLine(to: CGPoint(x: center.x, y: canvasSize.height))

        context.stroke(axes, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
    }

    private func drawCells(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        let cellRect = CGRect(x: -scale / 2, y: -scale / 2, width: scale, height: scale)
        for cell in engine.liveCells {
            let position = CGPoint(
                x: center.x + CGFloat(cell.x) * scale,
                y: center.y - CGFloat(cell.y) * scale
            )
            let rectangle = Path(roundedRect: cellRect.offsetBy(dx: position.x, dy: position.y), cornerRadius: 3)
            context.fill(rectangle, with: .color(.green))
        }
    }
}

private struct ControlBarView: View {
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 20) {
            Button {
                isPlaying.toggle()
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }

            Button {
                // step
            } label: {
                Label("Step", systemImage: "forward.frame.fill")
            }

            Button {
                // reset
            } label: {
                Label("Reset", systemImage: "gobackward")
            }

            Spacer()

            Button {
                // settings placeholder
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
