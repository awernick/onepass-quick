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

    // MARK: - Public API

    /// Fetch all items from 1Password using `op item list`.
    ///
    /// Uses `--cache` to leverage op's built-in caching.
    /// Authentication is handled by the 1Password desktop app via biometric.
    static func listItems() async throws -> [Item] {
        let opPath = try resolveOPPath()
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
        let opPath = try resolveOPPath()
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

    // MARK: - Process Execution

    /// Run an external process and capture its output without blocking any thread.
    ///
    /// Uses `terminationHandler` and pipe `readabilityHandler` to avoid blocking
    /// the cooperative thread pool. Pipes are drained incrementally to prevent
    /// deadlock when output exceeds the OS pipe buffer (~64KB on macOS).
    private static func runProcess(
        executablePath: String,
        arguments: [String]
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Accumulate data as it arrives to prevent pipe buffer deadlock
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

            process.terminationHandler = { terminatedProcess in
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

                let stdout = String(
                    data: stdoutAccumulator.data, encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrAccumulator.data, encoding: .utf8
                ) ?? ""

                continuation.resume(
                    returning: (
                        stdout, stderr, terminatedProcess.terminationStatus
                    )
                )
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(
                    throwing: OPClientError.executionFailed(
                        "Failed to launch: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    // MARK: - Path Resolution

    /// Find the `op` binary, checking known Homebrew paths first.
    private static func resolveOPPath() throws -> String {
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to `which op` for non-standard installations
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["op"]

        let pipe = Pipe()
        whichProcess.standardOutput = pipe

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !path.isEmpty
                && FileManager.default.isExecutableFile(atPath: path)
            {
                return path
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
