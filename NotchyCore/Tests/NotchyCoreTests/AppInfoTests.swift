import Testing
@testable import NotchyCore

@Test func logSubsystemMatchesBundleIdentifier() {
    #expect(AppInfo.logSubsystem == "com.mihai.notchy")
}
