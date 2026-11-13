import Testing

/// Hosted tests share NSApplication, demo defaults and SetupSessions across suites.
/// `.serialized` only orders a suite's children; this scope also excludes other suites
/// while an asynchronous test yields the main actor.
struct SharedAppState: TestTrait, SuiteTrait, TestScoping {
    private static let gate = AppStateTestGate()

    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        !test.isSuite && testCase != nil ? self : nil
    }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        await Self.gate.acquire()
        print("SHARED_APP_SCOPE begin: \(test.name)")
        do {
            try await function()
            print("SHARED_APP_SCOPE end: \(test.name)")
            await Self.gate.release()
        } catch {
            print("SHARED_APP_SCOPE error: \(test.name)")
            await Self.gate.release()
            throw error
        }
    }
}

extension Trait where Self == SharedAppState {
    static var sharedAppState: Self { Self() }
}

private actor AppStateTestGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            held = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private actor AppStateScopeProbe {
    static let shared = AppStateScopeProbe()
    private var active = 0

    func verifyExclusiveAccess() async throws {
        active += 1
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(1))
        #expect(active == 1, "Shared app state must remain exclusive across suites and test cases")
    }
}

@Suite(.sharedAppState)
struct SharedAppStateFirstSuiteTests {
    @MainActor @Test func ordinaryTestExcludesPeerSuite() async throws {
        try await AppStateScopeProbe.shared.verifyExclusiveAccess()
    }

    @Test(arguments: 0..<8) func excludesPeerSuiteAndCases(_ caseID: Int) async throws {
        try await AppStateScopeProbe.shared.verifyExclusiveAccess()
    }
}

@Suite(.sharedAppState)
struct SharedAppStateSecondSuiteTests {
    @MainActor @Test func ordinaryTestExcludesPeerSuite() async throws {
        try await AppStateScopeProbe.shared.verifyExclusiveAccess()
    }

    @Test(arguments: 0..<8) func excludesPeerSuiteAndCases(_ caseID: Int) async throws {
        try await AppStateScopeProbe.shared.verifyExclusiveAccess()
    }
}
