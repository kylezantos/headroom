import Foundation
import Darwin

/// A CLI spawned as its own session leader with piped stdin and stdout, so a server that
/// hangs, or leaves workers behind, can be ended as one process group. Stderr is discarded:
/// nothing a CLI prints there may reach a log or an error.
struct StdioChildProcess {
    private let pid: pid_t
    private let stdin: Int32
    private let stdout: Int32

    static func spawn(
        path: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String
    ) -> StdioChildProcess? {
        var input = [Int32](repeating: -1, count: 2)
        var output = [Int32](repeating: -1, count: 2)
        guard pipe(&input) == 0 else { return nil }
        guard pipe(&output) == 0 else {
            close(input[0]); close(input[1])
            return nil
        }
        guard fcntl(input[1], F_SETNOSIGPIPE, 1) != -1 else {
            close(input[0]); close(input[1]); close(output[0]); close(output[1])
            return nil
        }
        let devNull = open("/dev/null", O_WRONLY)

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, workingDirectory)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory)
        }
        posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        if devNull >= 0 { posix_spawn_file_actions_adddup2(&actions, devNull, STDERR_FILENO) }
        for fd in [input[0], input[1], output[0], output[1], devNull] where fd >= 0 {
            posix_spawn_file_actions_addclose(&actions, fd)
        }

        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let cEnvironment = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let cArguments = arguments.map { strdup($0) } + [nil]
        defer {
            cEnvironment.forEach { free($0) }
            cArguments.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, path, &actions, &attributes, cArguments, cEnvironment)
        close(input[0]); close(output[1])
        if devNull >= 0 { close(devNull) }
        guard spawnStatus == 0 else {
            close(input[1]); close(output[0])
            return nil
        }
        return StdioChildProcess(pid: pid, stdin: input[1], stdout: output[0])
    }

    func write(_ data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(stdin, pointer, remaining)
                guard written > 0 else { return false }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    /// Waits up to 250 ms for output and appends what arrived. False once the pipe has
    /// closed or failed; callers loop until their own deadline.
    func readOutput(into buffer: inout Data, deadline: Date) -> Bool {
        let remainingMilliseconds = max(1, Int(deadline.timeIntervalSinceNow * 1_000))
        var descriptor = pollfd(fd: stdout, events: Int16(POLLIN), revents: 0)
        let pollResult = Darwin.poll(&descriptor, 1, Int32(min(remainingMilliseconds, 250)))
        guard pollResult >= 0 else { return false }
        guard pollResult > 0 else { return true }
        var chunk = [UInt8](repeating: 0, count: 8_192)
        let count = Darwin.read(stdout, &chunk, chunk.count)
        guard count > 0 else { return false }
        buffer.append(contentsOf: chunk.prefix(count))
        return true
    }

    /// The leader's exit code once it exits within `seconds`; nil if it is still running or
    /// was killed by a signal. `WNOWAIT` leaves the leader unreaped, so `terminate()` still
    /// signals its group while the pid is held and can't be reused, then reaps it.
    func exitCode(within seconds: TimeInterval) -> Int32? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            var info = siginfo_t()
            guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 else { return nil }
            if info.si_pid == pid {
                return info.si_code == CLD_EXITED ? info.si_status : nil
            }
            usleep(10_000)
        } while Date() < deadline
        return nil
    }

    func terminate() {
        close(stdin)
        close(stdout)
        Self.terminateProcessGroup(pid)
    }

    /// The group is signalled even when the leader has already exited, because a worker it
    /// started can outlive it. Signalling before reaping keeps the group ID from being
    /// reused, since an unreaped leader still holds its pid.
    private static func terminateProcessGroup(_ pid: pid_t) {
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        if reapLeader(pid, within: 0.5), kill(-pid, 0) != 0 { return }
        kill(-pid, SIGKILL)
        _ = reapLeader(pid, within: 0.5)
    }

    /// True once the leader is reaped, or was already reaped elsewhere.
    private static func reapLeader(_ pid: pid_t, within seconds: TimeInterval) -> Bool {
        var status: Int32 = 0
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return true }
            usleep(20_000)
        } while Date() < deadline
        return false
    }
}
