//
//  life_gameTests.swift
//  life-gameTests
//
//  Created by Kevin Hill on 10/18/25.
//

import Testing
@testable import life_game

@MainActor
struct life_gameTests {

    @Test func singleCellDiesFromUnderpopulation() async throws {
        let engine = GameOfLifeEngine(initialLiveCells: [GridCoordinate(x: 0, y: 0)])

        let outcome = engine.step()

        #expect(outcome == .stabilized(.extinction))
        #expect(engine.liveCells.isEmpty)
        #expect(engine.generation == 1)
    }

    @Test func blockRemainsStable() async throws {
        let block: Set<GridCoordinate> = [
            GridCoordinate(x: 0, y: 0),
            GridCoordinate(x: 1, y: 0),
            GridCoordinate(x: 0, y: 1),
            GridCoordinate(x: 1, y: 1)
        ]
        let engine = GameOfLifeEngine(initialLiveCells: block)

        let outcome = engine.step()

        #expect(outcome == .stabilized(.staticPattern))
        #expect(engine.liveCells == block)
        #expect(engine.generation == 1)
    }

    @Test func blinkerOscillatesWithPeriodTwo() async throws {
        let blinker: Set<GridCoordinate> = [
            GridCoordinate(x: 0, y: 0),
            GridCoordinate(x: 1, y: 0),
            GridCoordinate(x: 2, y: 0)
        ]
        let engine = GameOfLifeEngine(initialLiveCells: blinker)

        let firstOutcome = engine.step()

        let verticalBlinker: Set<GridCoordinate> = [
            GridCoordinate(x: 1, y: -1),
            GridCoordinate(x: 1, y: 0),
            GridCoordinate(x: 1, y: 1)
        ]

        #expect(firstOutcome == .advanced)
        #expect(engine.liveCells == verticalBlinker)
        #expect(engine.generation == 1)

        let secondOutcome = engine.step()

        #expect(secondOutcome == .cycled(period: 2))
        #expect(engine.liveCells == blinker)
        #expect(engine.generation == 2)
    }

    @Test func boundsReflectLiveCells() async throws {
        let engine = GameOfLifeEngine(initialLiveCells: [
            GridCoordinate(x: -2, y: 3),
            GridCoordinate(x: 4, y: -1)
        ])

        let bounds = engine.bounds

        #expect(bounds?.minX == -2)
        #expect(bounds?.maxX == 4)
        #expect(bounds?.minY == -1)
        #expect(bounds?.maxY == 3)
        #expect(bounds?.width == 7)
        #expect(bounds?.height == 5)

        engine.clear()
        #expect(engine.bounds == nil)
    }

}
