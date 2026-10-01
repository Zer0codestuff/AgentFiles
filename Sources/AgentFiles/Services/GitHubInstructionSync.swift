import Foundation

/// GitHub is a private data store. Every publication is one atomic, non-forced Git commit.
struct GitHubInstructionSync: InstructionSyncRemote {
  func connect(repositoryName: String) async throws -> String {
    guard !repositoryName.isEmpty, repositoryName.count <= 100,
      repositoryName.range(of: "^[A-Za-z0-9_-][A-Za-z0-9_.-]*$", options: .regularExpression) != nil
    else { throw InstructionSyncError.message("Enter a repository name using letters, numbers, dots, or hyphens.") }
    let token = try await GitHubCLI.token()
    let user: GitHubUser = try await json("user", token: token)
    let repository = "\(user.login)/\(repositoryName)"
    do {
      _ = try await metadata(repository, token: token)
    } catch InstructionSyncError.http(404, _) {
      let created: GitHubRepository = try await json(
        "user/repos", method: "POST", body: [
          "name": repositoryName, "private": true, "auto_init": true,
          "description": "Private instruction sync for Agent Files. Skills are excluded.",
          "has_issues": false, "has_projects": false, "has_wiki": false,
        ], token: token
      )
      try created.requirePrivateWritable()
    }
    return repository
  }

  func fetch(repository: String) async throws -> InstructionSyncSnapshot {
    try validateRepository(repository)
    let token = try await GitHubCLI.token()
    let repo = try await metadata(repository, token: token)
    let reference: GitHubReference = try await json(
      "repos/\(repository)/git/ref/heads/\(repo.default_branch)", token: token
    )
    let commit: GitHubCommit = try await json(
      "repos/\(repository)/git/commits/\(reference.object.sha)", token: token
    )
    var document = InstructionSyncDocument()
    var missingArchive = false
    do {
      let data = try await request(
        "repos/\(repository)/contents/agent-files.json", token: token,
        query: [URLQueryItem(name: "ref", value: reference.object.sha)],
        accept: "application/vnd.github.raw+json"
      )
      guard data.count <= 8_000_000 else {
        throw InstructionSyncError.message("The instruction archive exceeds the 8 MB sync limit.")
      }
      document = try JSONDecoder().decode(InstructionSyncDocument.self, from: data).validated()
    } catch InstructionSyncError.http(404, _) {
      // Only a never-synced repository may start without its manifest.
      let tree: GitHubTree = try await json("repos/\(repository)/git/trees/\(commit.tree.sha)", token: token)
      missingArchive = tree.tree.contains(where: { $0.path == "instructions" })
    }
    return .init(document: document, branch: repo.default_branch,
      headSHA: reference.object.sha, treeSHA: commit.tree.sha, missingArchive: missingArchive)
  }

  func push(
    _ document: InstructionSyncDocument, repository: String, after snapshot: InstructionSyncSnapshot
  ) async throws {
    try validateRepository(repository)
    let files = try document.repositoryFiles()
    guard files.values.reduce(0, { $0 + $1.utf8.count }) <= 8_000_000 else {
      throw InstructionSyncError.message("The instruction archive exceeds the 8 MB sync limit.")
    }
    let token = try await GitHubCLI.token()
    let repo = try await metadata(repository, token: token)
    guard repo.default_branch == snapshot.branch else { throw InstructionSyncError.concurrentUpdate }
    let entries = files.keys.sorted().map { path in
      ["path": path, "mode": "100644", "type": "blob", "content": files[path]!]
    }
    let tree: GitHubObject = try await json(
      "repos/\(repository)/git/trees", method: "POST",
      body: ["base_tree": snapshot.treeSHA, "tree": entries], token: token
    )
    let commit: GitHubObject = try await json(
      "repos/\(repository)/git/commits", method: "POST",
      body: ["message": "Sync instruction files", "tree": tree.sha, "parents": [snapshot.headSHA]],
      token: token
    )
    do {
      let _: GitHubReference = try await json(
        "repos/\(repository)/git/refs/heads/\(snapshot.branch)", method: "PATCH",
        body: ["sha": commit.sha, "force": false], token: token
      )
    } catch InstructionSyncError.http(let code, _) where code == 409 || code == 422 {
      throw InstructionSyncError.concurrentUpdate
    }
  }

  private func metadata(_ repository: String, token: String) async throws -> GitHubRepository {
    let repo: GitHubRepository = try await json("repos/\(repository)", token: token)
    try repo.requirePrivateWritable()
    return repo
  }

  private func validateRepository(_ repository: String) throws {
    guard repository.range(of: "^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else {
      throw InstructionSyncError.message("The saved repository name is invalid.")
    }
  }

  private func json<T: Decodable>(
    _ path: String, method: String = "GET", body: [String: Any]? = nil, token: String
  ) async throws -> T {
    try await JSONDecoder().decode(T.self, from: request(path, method: method, body: body, token: token))
  }

  private func request(
    _ path: String, method: String = "GET", body: [String: Any]? = nil, token: String,
    query: [URLQueryItem] = [], accept: String = "application/vnd.github+json"
  ) async throws -> Data {
    var components = URLComponents(string: "https://api.github.com/\(path)")!
    if !query.isEmpty { components.queryItems = query }
    var request = URLRequest(url: components.url!)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("AgentFiles", forHTTPHeaderField: "User-Agent")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw InstructionSyncError.message("GitHub did not return a valid response.")
    }
    guard (200..<300).contains(response.statusCode) else {
      let message = (try? JSONDecoder().decode(GitHubMessage.self, from: data))?.message
        ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
      throw InstructionSyncError.http(response.statusCode, message)
    }
    return data
  }
}

private struct GitHubUser: Decodable { var login: String }
private struct GitHubObject: Decodable { var sha: String }
private struct GitHubReference: Decodable { var object: GitHubObject }
private struct GitHubCommit: Decodable { var tree: GitHubObject }
private struct GitHubMessage: Decodable { var message: String }
private struct GitHubTree: Decodable {
  struct Entry: Decodable { var path: String }
  var tree: [Entry]
}
private struct GitHubRepository: Decodable {
  var `private`: Bool
  var archived: Bool
  var default_branch: String
  var permissions: Permissions?
  struct Permissions: Decodable { var push: Bool }

  func requirePrivateWritable() throws {
    guard `private` else {
      throw InstructionSyncError.message("Sync requires a private repository. No instructions were uploaded.")
    }
    guard !archived, permissions?.push == true else {
      throw InstructionSyncError.message("This account cannot write to the sync repository.")
    }
  }
}
