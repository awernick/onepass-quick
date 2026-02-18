import Foundation
import os.log

/// Error types from op CLI interactions.
enum OPClientError: Error, Equatable {
    /// The `op` binary was not found in any known location.
    case cliNotFound
    /// The user is not signed in or biometric unlock is required.
    case notAuthenticated(String)
    /// The CLI process exited with a non-zero code.
    case executionFailed(String)
    /// JSON decoding of CLI output failed.
    case decodingFailed(String)
    /// The requested field does not exist on the item.
    case fieldNotFound(String)
    /// The CLI process exceeded the allowed time limit.
    case timeout

    var localizedDescription: String {
        switch self {
        case .cliNotFound:
            return "1Password CLI (op) not found. Install it with: brew install 1password-cli"
        case .notAuthenticated(let detail):
            return "Not authenticated: \(detail)"
        case .executionFailed(let detail):
            return "CLI error: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to parse items: \(detail)"
        case .fieldNotFound(let detail):
            return "Field not found: \(detail)"
        case .timeout:
            return "1Password CLI timed out. Check that 1Password is unlocked."
        }
    }
}

/// Async wrapper around the 1Password `op` CLI.
///
/// All credential access goes through this client. It never stores
/// or caches credentials -- that responsibility belongs to the caller.
enum OPClient {

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OnePassQuick",
        category: "OPClient"
    )

    /// Known paths where Homebrew installs the `op` binary.
    private static let knownPaths = [
        "/opt/homebrew/bin/op",   // Apple Silicon
        "/usr/local/bin/op",      // Intel
    ]

    /// Maximum time (in seconds) a CLI process is allowed to run before
    /// being terminated. Covers scenarios where `op` hangs waiting for a
    /// Touch ID prompt that never completes.
    private static let processTimeout: TimeInterval = 30

    // MARK: - Public API

    /// Fetch all items from 1Password using `op item list`.
    ///
    /// Uses `--cache` to leverage op's built-in caching.
    /// Authentication is handled by the 1Password desktop app via biometric.
    static func listItems() async throws -> [Item] {
        let opPath = try await resolveOPPath()
        log.info("Listing items via \(opPath)")

        let arguments = ["item", "list", "--format", "json", "--cache"]
        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: opPath,
            arguments: arguments
        )

        if exitCode != 0 {
            // Some op versions write errors to stdout instead of stderr
            let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = stderrTrimmed.isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderrTrimmed
            log.error("op item list failed (exit \(exitCode)): \(errorOutput)")

            if isAuthenticationError(errorOutput) {
                throw OPClientError.notAuthenticated(errorOutput)
            }
            throw OPClientError.executionFailed(errorOutput)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw OPClientError.decodingFailed("Empty or invalid output")
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let items = try decoder.decode([Item].self, from: data)
            log.info("Loaded \(items.count) items")
            return items
        } catch {
            log.error("JSON decode failed: \(error.localizedDescription)")
            throw OPClientError.decodingFailed(error.localizedDescription)
        }
    }

    /// Fetch the default 1Password account info.
    ///
    /// Calls `op account list --format json` and returns the first
    /// account. Used to construct Private Link URLs for deep linking.
    static func getAccount() async throws -> OPAccount {
        let opPath = try await resolveOPPath()
        log.info("Fetching account info via \(opPath)")

        let arguments = ["account", "list", "--format", "json"]
        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: opPath,
            arguments: arguments
        )

        if exitCode != 0 {
            let stderrTrimmed = stderr.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let errorOutput = stderrTrimmed.isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderrTrimmed
            log.error(
                "op account list failed (exit \(exitCode)): \(errorOutput)"
            )

            if isAuthenticationError(errorOutput) {
                throw OPClientError.notAuthenticated(errorOutput)
            }
            throw OPClientError.executionFailed(errorOutput)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw OPClientError.decodingFailed("Empty or invalid output")
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let accounts = try decoder.decode([OPAccount].self, from: data)
            guard let account = accounts.first else {
                throw OPClientError.executionFailed(
                    "No accounts found"
                )
            }
            log.info("Fetched account: \(account.url)")
            return account
        } catch let opError as OPClientError {
            throw opError
        } catch {
            log.error("JSON decode failed: \(error.localizedDescription)")
            throw OPClientError.decodingFailed(error.localizedDescription)
        }
    }

    /// Fetch a single field value from a 1Password item.
    ///
    /// Calls `op item get <id> --fields <field> --format json --cache`.
    /// Returns the field's `value` string directly.
    ///
    /// - Note: This triggers a Touch ID prompt via the 1Password desktop
    ///   app on every call (CLI sessions are per-tty, and `Process` has
    ///   no tty).
    static func getField(
        itemID: String,
        field: String
    ) async throws -> String {
        let opPath = try await resolveOPPath()
        log.info("Fetching field '\(field)' for item \(itemID)")

        // Note: --cache intentionally omitted. The op CLI cache may
        // persist field values to disk, violating the "never store
        // credentials on disk" rule.
        let arguments = [
            "item", "get", itemID,
            "--fields", field,
            "--format", "json",
        ]
        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: opPath,
            arguments: arguments
        )

        if exitCode != 0 {
            let stderrTrimmed = stderr.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let errorOutput = stderrTrimmed.isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderrTrimmed

            log.error(
                "op item get failed (exit \(exitCode)): \(errorOutput)"
            )

            if isAuthenticationError(errorOutput) {
                throw OPClientError.notAuthenticated(errorOutput)
            }
            if isFieldNotFoundError(errorOutput) {
                throw OPClientError.fieldNotFound(field)
            }
            throw OPClientError.executionFailed(errorOutput)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw OPClientError.decodingFailed("Empty or invalid output")
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let itemField = try decoder.decode(ItemField.self, from: data)
            log.info("Fetched field '\(field)' successfully")
            return itemField.value
        } catch {
            log.error("JSON decode failed: \(error.localizedDescription)")
            throw OPClientError.decodingFailed(error.localizedDescription)
        }
    }

    /// Fetch the current one-time password (TOTP) for a 1Password item.
    ///
    /// Calls `op item get <id> --otp`. Returns the current TOTP code as
    /// a plain string. Throws `fieldNotFound` if the item has no TOTP
    /// configuration.
    ///
    /// - Note: Triggers a Touch ID prompt via the 1Password desktop app.
    static func getOTP(itemID: String) async throws -> String {
        let opPath = try await resolveOPPath()
        log.info("Fetching OTP for item \(itemID)")

        let arguments = ["item", "get", itemID, "--otp"]
        let (stdout, stderr, exitCode) = try await runProcess(
            executablePath: opPath,
            arguments: arguments
        )

        if exitCode != 0 {
            let stderrTrimmed = stderr.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let errorOutput = stderrTrimmed.isEmpty
                ? stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                : stderrTrimmed

            log.error(
                "op item get --otp failed (exit \(exitCode)): \(errorOutput)"
            )

            if isAuthenticationError(errorOutput) {
                throw OPClientError.notAuthenticated(errorOutput)
            }
            if isOTPNotFoundError(errorOutput) {
                throw OPClientError.fieldNotFound("one-time password")
            }
            throw OPClientError.executionFailed(errorOutput)
        }

        let otp = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otp.isEmpty else {
            throw OPClientError.fieldNotFound("one-time password")
        }

        log.info("Fetched OTP successfully")
        return otp
    }

    // MARK: - Process Execution

    /// Run an external process and capture its output without blocking any thread.
    ///
    /// Uses `terminationHandler` and pipe `readabilityHandler` to avoid blocking
    /// the cooperative thread pool. Pipes are drained incrementally to prevent
    /// deadlock when output exceeds the OS pipe buffer (~64KB on macOS).
    ///
    /// Supports both **timeout** (process is terminated after `processTimeout`
    /// seconds) and **cancellation** (process is terminated when the parent
    /// Swift Task is cancelled, e.g., panel dismissed during Touch ID).
    private static func runProcess(
        executablePath: String,
        arguments: [String]
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        // State shared between the continuation, timeout, and cancellation
        // handler. `didResume` prevents double-resumption which would crash.
        let resumeGuard = ResumeGuard()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutAccumulator = PipeAccumulator()
        let stderrAccumulator = PipeAccumulator()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutAccumulator.append(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrAccumulator.append(data)
            }
        }

        /// Terminate the process and clean up pipe handlers.
        func terminateProcess() {
            if process.isRunning {
                process.terminate()
            }
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Schedule timeout
                let timeoutItem = DispatchWorkItem {
                    guard resumeGuard.tryResume() else { return }
                    log.warning(
                        "Process timed out after \(Int(processTimeout))s: \(executablePath)"
                    )
                    terminateProcess()
                    continuation.resume(throwing: OPClientError.timeout)
                }
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + processTimeout,
                    execute: timeoutItem
                )

                process.terminationHandler = { terminatedProcess in
                    timeoutItem.cancel()

                    // Stop reading handlers
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    // Drain any remaining data
                    stdoutAccumulator.append(
                        stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    )
                    stderrAccumulator.append(
                        stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    )

                    guard resumeGuard.tryResume() else { return }

                    let stdout = String(
                        data: stdoutAccumulator.data, encoding: .utf8
                    ) ?? ""
                    let stderr = String(
                        data: stderrAccumulator.data, encoding: .utf8
                    ) ?? ""

                    continuation.resume(
                        returning: (
                            stdout, stderr,
                            terminatedProcess.terminationStatus
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
                    timeoutItem.cancel()
                    terminateProcess()
                    guard resumeGuard.tryResume() else { return }
                    continuation.resume(
                        throwing: OPClientError.executionFailed(
                            "Failed to launch: \(error.localizedDescription)"
                        )
                    )
                }
            }
        } onCancel: {
            // Don't claim resumeGuard here -- let the terminationHandler
            // fire and resume the continuation normally. The caller sees
            // the result but Task.isCancelled will be true.
            log.info(
                "Task cancelled, terminating process: \(executablePath)"
            )
            terminateProcess()
        }
    }

    // MARK: - Path Resolution

    /// Find the `op` binary, checking known Homebrew paths first.
    ///
    /// The `which` fallback runs asynchronously via `runProcess` to avoid
    /// blocking the main thread when `op` isn't in a known Homebrew path.
    private static func resolveOPPath() async throws -> String {
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which op` for non-standard installations
        do {
            let (stdout, _, exitCode) = try await runProcess(
                executablePath: "/usr/bin/which",
                arguments: ["op"]
            )

            if exitCode == 0 {
                let path = stdout.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !path.isEmpty,
                    FileManager.default.isExecutableFile(atPath: path)
                {
                    return path
                }
            }
        } catch {
            log.warning("which op failed: \(error.localizedDescription)")
        }

        throw OPClientError.cliNotFound
    }

    // MARK: - Error Detection

    /// Check if the CLI error message indicates an authentication issue.
    private static func isAuthenticationError(_ message: String) -> Bool {
        let patterns = [
            "not signed in",
            "not authenticated",
            "sign in",
            "authorization prompt",
            "session expired",
            "biometric",
        ]
        let lowered = message.lowercased()
        return patterns.contains { lowered.contains($0) }
    }

    /// Check if the CLI error indicates a missing field on the item.
    ///
    /// The CLI outputs: `"username" isn't a field in the "..." item`
    private static func isFieldNotFoundError(_ message: String) -> Bool {
        message.contains("isn't a field in the")
    }

    /// Check if the CLI error indicates the item has no TOTP configuration.
    ///
    /// The CLI outputs: `"..." doesn't have a one-time password.`
    private static func isOTPNotFoundError(_ message: String) -> Bool {
        message.lowercased().contains("doesn't have a one-time password")
    }
}

// MARK: - Resume Guard

/// Thread-safe one-shot flag that ensures a continuation is resumed
/// exactly once. Used to coordinate between the termination handler,
/// the timeout, and the cancellation handler -- any of which may fire
/// first (and concurrently).
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var _didResume = false

    /// Returns `true` exactly once. All subsequent calls return `false`.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _didResume { return false }
        _didResume = true
        return true
    }
}

// MARK: - Pipe Accumulator

/// Thread-safe accumulator for pipe data arriving on background queues.
private final class PipeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        _data.append(newData)
        lock.unlock()
    }
}
