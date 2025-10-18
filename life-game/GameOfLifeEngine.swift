//
//  GameOfLifeEngine.swift
//  life-game
//
//  Created by Kevin Hill on 10/18/25.
//

import Foundation
import Combine

/// Represents a coordinate on the infinite Life grid.
public struct GridCoordinate: Hashable, Comparable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static func < (lhs: GridCoordinate, rhs: GridCoordinate) -> Bool {
        if lhs.y == rhs.y {
            return lhs.x < rhs.x
        }
        return lhs.y < rhs.y
    }
}

/// Bounds that enclose every live cell.
public struct GridBounds: Equatable, Sendable {
    public let minX: Int
    public let maxX: Int
    public let minY: Int
    public let maxY: Int

    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }
}

/// Engine that advances Conway's Game of Life and keeps limited history for cycle detection.
@MainActor
public final class GameOfLifeEngine: ObservableObject {

    public enum StabilizationReason: Equatable, Sendable {
        case staticPattern
        case extinction
    }

    public enum StepOutcome: Equatable, Sendable {
        case advanced
        case stabilized(StabilizationReason)
        case cycled(period: Int)

        public var isTerminal: Bool {
            switch self {
            case .advanced:
                return false
            case .stabilized, .cycled:
                return true
            }
        }
    }

    @Published public private(set) var liveCells: Set<GridCoordinate>
    @Published public private(set) var generation: Int = 0
    @Published public private(set) var lastOutcome: StepOutcome = .advanced

    public var bounds: GridBounds? {
        guard let first = liveCells.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for cell in liveCells.dropFirst() {
            minX = min(minX, cell.x)
            maxX = max(maxX, cell.x)
            minY = min(minY, cell.y)
            maxY = max(maxY, cell.y)
        }

        return GridBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private var history: [StateSnapshot]
    private var historySet: Set<StateSnapshot>
    private let historyLimit: Int

    public init(initialLiveCells: Set<GridCoordinate>, historyLimit: Int = 256) {
        precondition(historyLimit > 1, "History limit must exceed 1 to detect cycles.")
        self.liveCells = initialLiveCells
        self.historyLimit = historyLimit
        let snapshot = StateSnapshot(cells: initialLiveCells)
        self.history = [snapshot]
        self.historySet = [snapshot]
    }

    public convenience init(historyLimit: Int = 256) {
        self.init(initialLiveCells: Set(), historyLimit: historyLimit)
    }

    /// Returns true when the coordinate currently hosts a live cell.
    public func isAlive(_ coordinate: GridCoordinate) -> Bool {
        liveCells.contains(coordinate)
    }

    /// Sets the live/dead state for a coordinate, resetting the generation counter when a change occurs.
    public func setAlive(_ alive: Bool, at coordinate: GridCoordinate) {
        let didChange: Bool
        if alive {
            didChange = liveCells.insert(coordinate).inserted
        } else {
            didChange = liveCells.remove(coordinate) != nil
        }

        if didChange {
            resetSimulationState()
        }
    }

    /// Toggles a coordinate between alive and dead states.
    public func toggle(_ coordinate: GridCoordinate) {
        if liveCells.contains(coordinate) {
            liveCells.remove(coordinate)
        } else {
            liveCells.insert(coordinate)
        }
        resetSimulationState()
    }

    /// Clears all live cells and resets the simulation.
    public func clear() {
        guard !liveCells.isEmpty else { return }
        liveCells.removeAll()
        resetSimulationState()
    }

    /// Advances the simulation by one generation and reports the outcome.
    @discardableResult
    public func step() -> StepOutcome {
        let currentSnapshot = StateSnapshot(cells: liveCells)
        var neighborCounts: [GridCoordinate: Int] = [:]
        neighborCounts.reserveCapacity(liveCells.count * 8)

        for cell in liveCells {
            for neighbor in neighbors(of: cell) {
                neighborCounts[neighbor, default: 0] += 1
            }
        }

        var nextGeneration = Set<GridCoordinate>()
        nextGeneration.reserveCapacity(liveCells.count)

        for (cell, count) in neighborCounts {
            if liveCells.contains(cell) {
                if count == 2 || count == 3 {
                    nextGeneration.insert(cell)
                }
            } else if count == 3 {
                nextGeneration.insert(cell)
            }
        }

        let nextSnapshot = StateSnapshot(cells: nextGeneration)
        let outcome: StepOutcome

        if nextGeneration.isEmpty {
            outcome = .stabilized(.extinction)
        } else if nextSnapshot == currentSnapshot {
            outcome = .stabilized(.staticPattern)
        } else if let period = cyclePeriod(for: nextSnapshot) {
            outcome = .cycled(period: period)
        } else {
            outcome = .advanced
        }

        liveCells = nextGeneration
        generation += 1
        lastOutcome = outcome

        appendToHistory(nextSnapshot)

        return outcome
    }

    // MARK: - Private

    private struct StateSnapshot: Hashable {
        let cells: [GridCoordinate]

        init(cells: Set<GridCoordinate>) {
            self.cells = cells.sorted()
        }
    }

    private func neighbors(of cell: GridCoordinate) -> [GridCoordinate] {
        var result: [GridCoordinate] = []
        result.reserveCapacity(8)
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                result.append(GridCoordinate(x: cell.x + dx, y: cell.y + dy))
            }
        }
        return result
    }

    private func cyclePeriod(for snapshot: StateSnapshot) -> Int? {
        guard historySet.contains(snapshot),
              let latestIndex = history.lastIndex(of: snapshot) else {
            return nil
        }
        let period = history.count - latestIndex
        return period > 1 ? period : nil
    }

    private func appendToHistory(_ snapshot: StateSnapshot) {
        history.append(snapshot)
        historySet.insert(snapshot)
        trimHistoryIfNeeded()
    }

    private func resetSimulationState() {
        generation = 0
        lastOutcome = .advanced
        let snapshot = StateSnapshot(cells: liveCells)
        history = [snapshot]
        historySet = [snapshot]
    }

    private func trimHistoryIfNeeded() {
        while history.count > historyLimit {
            let removed = history.removeFirst()
            if !history.contains(removed) {
                historySet.remove(removed)
            }
        }
    }
}
