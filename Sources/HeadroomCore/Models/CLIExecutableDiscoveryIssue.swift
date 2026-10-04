public enum CLIExecutableDiscoveryIssue: String, Sendable, Equatable {
    case shellTimeout
    case shellSpawnFailure
    case invalidShellOutput
    case inaccessibleCandidate
    case invalidatedHint
    case launchRace
    case npmPrefixUnresolved
}
