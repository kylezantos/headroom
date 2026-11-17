import Foundation

/// Runs blocking client work on its own thread rather than one of Swift's cooperative
/// threads. A client run blocks for up to its deadline, which would otherwise tie up the pool.
enum CLIProcessThread {
    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: work()) }
        }
    }
}
