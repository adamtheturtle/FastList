import Testing
@testable import FastList

@Suite struct FastListReachEndGateTests {
    @Test func bothBackendsCanShareOncePerCountSemantics() {
        var gate = FastListReachEndGate()

        let first = gate.consume(lastVisibleRow: 9, itemCount: 10, threshold: 0)
        let duplicate = gate.consume(lastVisibleRow: 9, itemCount: 10, threshold: 0)
        let nextCount = gate.consume(lastVisibleRow: 10, itemCount: 11, threshold: 0)

        #expect(first)
        #expect(!duplicate)
        #expect(nextCount)
    }

    @Test func aVisibleRowIsReevaluatedWhenAShortPageLands() {
        var gate = FastListReachEndGate()

        let initialPage = gate.consume(lastVisibleRow: 99, itemCount: 100, threshold: 20)
        let shortPage = gate.consume(lastVisibleRow: 99, itemCount: 120, threshold: 20)
        let outsideThreshold = gate.consume(lastVisibleRow: 99, itemCount: 121, threshold: 20)

        #expect(initialPage)
        #expect(shortPage)
        #expect(!outsideThreshold)
    }

    @Test func disablingTheHandlerRearmsTheCurrentCount() {
        var gate = FastListReachEndGate()

        let first = gate.consume(lastVisibleRow: 9, itemCount: 10, threshold: 0)
        gate.reset()
        let rearmed = gate.consume(lastVisibleRow: 9, itemCount: 10, threshold: 0)

        #expect(first)
        #expect(rearmed)
    }
}
