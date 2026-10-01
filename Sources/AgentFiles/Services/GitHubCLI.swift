import Foundation

enum GitHubCLI {
  static func executable() throws -> URL {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/gh").path
    let paths = [bundled, "/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
      + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
    guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
      throw InstructionSyncError.message("GitHub sign-in is unavailable in this build. Rebuild Agent Files with GitHub CLI installed.")
    }
    return URL(fileURLWithPath: path)
  }

  /// The CLI reads the existing GitHub credential. The app never persists its token.
  static func token() async throws -> String {
    let executable = try executable()
    return try await Task.detached {
      let process = Process()
      process.executableURL = executable
      process.arguments = ["auth", "token", "--hostname", "github.com"]
      let output = Pipe()
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      process.standardInput = FileHandle.nullDevice
      try process.run()
      let deadline = Date().addingTimeInterval(10)
      defer { if process.isRunning { process.terminate() } }
      while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
      if process.isRunning {
        process.terminate()
        throw InstructionSyncError.message("GitHub sign-in timed out. Try again.")
      }
      let token = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard process.terminationStatus == 0, !token.isEmpty else {
        throw InstructionSyncError.message("Sign in to GitHub to connect your computers.")
      }
      return token
    }.value
  }

  static func signIn(progress: @escaping @Sendable (String) -> Void) async throws {
    let executable = try executable()
    try await Task.detached {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let logURL = directory.appendingPathComponent("sign-in.txt")
      FileManager.default.createFile(atPath: logURL.path, contents: nil)
      let log = try FileHandle(forWritingTo: logURL)
      defer { try? log.close() }
      let process = Process()
      process.executableURL = executable
      process.arguments = ["auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https"]
      var environment = ProcessInfo.processInfo.environment
      environment["GH_BROWSER"] = "/usr/bin/open"
      environment["GH_PROMPT_DISABLED"] = "1"
      process.environment = environment
      process.standardOutput = log
      process.standardError = log
      let input = Pipe()
      process.standardInput = input
      try process.run()
      defer { if process.isRunning { process.terminate() } }
      try input.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
      try input.fileHandleForWriting.close()
      let deadline = Date().addingTimeInterval(180)
      var lastCode = ""
      while process.isRunning, Date() < deadline {
        let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        if let range = text.range(of: "[A-Z0-9]{4}-[A-Z0-9]{4}", options: .regularExpression) {
          let code = String(text[range])
          if code != lastCode { lastCode = code; progress(code) }
        }
        try await Task.sleep(for: .milliseconds(200))
      }
      if process.isRunning {
        process.terminate()
        throw InstructionSyncError.message("GitHub sign-in expired. Start sign-in again.")
      }
      guard process.terminationStatus == 0 else {
        throw InstructionSyncError.message("GitHub sign-in was not completed. Try again.")
      }
    }.value
  }
}
