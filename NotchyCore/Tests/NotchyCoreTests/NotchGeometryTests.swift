import CoreGraphics
import Testing
@testable import NotchyCore

struct NotchGeometryTests {
    // MacBook Air 13" at its default scaled resolution.
    let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test func notchIsTheGapBetweenAuxiliaryAreas() throws {
        let notch = try #require(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 32,
                                                         leftAreaWidth: 640, rightAreaWidth: 640))
        #expect(notch == CGRect(x: 640, y: 924, width: 190, height: 32))
    }

    @Test func noNotch() {
        #expect(NotchGeometry.notchRect(screenFrame: screen, safeAreaTop: 0,
                                        leftAreaWidth: nil, rightAreaWidth: nil) == nil)
    }

    @Test func secondaryScreenOffset() throws {
        let external = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let notch = try #require(NotchGeometry.notchRect(screenFrame: external, safeAreaTop: 32,
                                                         leftAreaWidth: 860, rightAreaWidth: 860))
        #expect(notch.minX == -1060)
        #expect(notch.maxY == external.maxY)
    }

    @Test func dropdownHangsFromTopCentredOnNotch() {
        let notch = CGRect(x: 640, y: 924, width: 190, height: 32)
        let frame = NotchGeometry.dropdownFrame(notch: notch, screenFrame: screen,
                                                size: CGSize(width: 520, height: 300))
        #expect(frame == CGRect(x: 475, y: 656, width: 520, height: 300))
    }

    @Test func dropdownWithoutNotchCentresOnScreen() {
        let frame = NotchGeometry.dropdownFrame(notch: nil, screenFrame: screen,
                                                size: CGSize(width: 520, height: 100))
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY)
    }
}
