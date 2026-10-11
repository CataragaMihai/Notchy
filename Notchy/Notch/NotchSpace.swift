import AppKit

// Private SkyLight calls, as used by other notch apps. Not public API: if a macOS update changes
// them, the windows still work and simply slide with desktop switches again.
private typealias ConnectionID = UInt32
private typealias SpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func CGSDefaultConnection() -> ConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ connection: ConnectionID, _ flags: Int32, _ options: NSDictionary?) -> SpaceID
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ connection: ConnectionID, _ space: SpaceID, _ level: Int32)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ connection: ConnectionID, _ spaces: NSArray)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ connection: ConnectionID, _ windows: NSArray, _ spaces: NSArray)

/// A space above all desktops that never moves. Notchy's windows live there, so they stay put on
/// the notch while desktops slide past, instead of sliding out and back in.
@MainActor
final class NotchSpace {
    static let shared = NotchSpace()
    private let id: SpaceID
    private var added: Set<Int> = []

    private init() {
        let connection = CGSDefaultConnection()
        id = CGSSpaceCreate(connection, 0x1, nil)
        CGSSpaceSetAbsoluteLevel(connection, id, Int32.max)
        CGSShowSpaces(connection, [NSNumber(value: id)] as NSArray)
    }

    /// Adds a window once it has a window number (after it was first ordered in).
    func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, !added.contains(number) else { return }
        added.insert(number)
        CGSAddWindowsToSpaces(CGSDefaultConnection(), [NSNumber(value: number)] as NSArray,
                              [NSNumber(value: id)] as NSArray)
    }
}
