import Darwin
import Testing
@testable import CobraCore

struct AppContextTests {
    @Test func sameProcessAndWindowMatches() {
        let original = context(pid: 42, window: "Draft")
        #expect(original.matchesInjectionTarget(context(pid: 42, window: "Draft")))
    }

    @Test func differentProcessDoesNotMatch() {
        let original = context(pid: 42, window: "Draft")
        #expect(!original.matchesInjectionTarget(context(pid: 43, window: "Draft")))
    }

    @Test func differentWindowDoesNotMatch() {
        let original = context(pid: 42, window: "Private message")
        #expect(!original.matchesInjectionTarget(context(pid: 42, window: "Public channel")))
    }

    @Test func unknownTargetDoesNotMatch() {
        #expect(!AppContext.unknown.matchesInjectionTarget(.unknown))
    }

    private func context(pid: pid_t, window: String?) -> AppContext {
        AppContext(
            bundleID: "example.app",
            appName: "Example",
            windowTitle: window,
            processIdentifier: pid
        )
    }
}
